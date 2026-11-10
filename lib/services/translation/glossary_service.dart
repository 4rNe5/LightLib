// Books' glossaries ([BookGlossary]): kept per book file in the app's
// support directory, made by the translation model the first time a book
// is translated, and edited by the reader.

// Dart imports:
import 'dart:async';
import 'dart:io';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:path/path.dart' as p;

// Project imports:
import 'package:openlib/services/heavy_work.dart';
import 'package:openlib/services/logger.dart';
import 'package:openlib/services/storage/app_files.dart';
import 'package:openlib/services/translation/book_glossary.dart';
import 'package:openlib/services/translation/translator.dart';

class GlossaryService extends ChangeNotifier {
  GlossaryService._();
  static final GlossaryService instance = GlossaryService._();

  /// Where glossaries are kept (replaceable in tests).
  Future<String> Function() folder =
      () async => p.join(await AppFiles.instance.supportPath(), 'glossaries');

  /// Tests: keep glossaries in [dir].
  set directory(Future<Directory> Function() dir) =>
      folder = () async => (await dir()).path;

  final Map<String, BookGlossary> _loaded = {};

  /// Called with a book's file name after its glossary is saved here
  /// (sync sends it on); not for one that came from another device.
  static void Function(String bookFile)? onSaved;
  final Map<String, Future<BookGlossary>> _making = {};
  final AppLogger _logger = AppLogger();

  /// Books whose glossary the model is making now.
  bool isMaking(String bookFile) => _making.containsKey(bookFile);

  /// The glossary in memory, if loaded.
  BookGlossary? cached(String bookFile) => _loaded[bookFile];

  Future<String> _file(String bookFile) async {
    final safe = bookFile.replaceAll(RegExp(r'[^\w.\-]'), '_');
    return p.join(await folder(), '$safe.json');
  }

  Future<BookGlossary> load(String bookFile) async {
    final known = _loaded[bookFile];
    if (known != null) return known;
    try {
      final saved = await AppFiles.instance.readString(await _file(bookFile));
      final glossary =
          saved != null ? BookGlossary.decode(saved) : BookGlossary.empty;
      return _loaded[bookFile] = glossary;
    } catch (_) {
      return BookGlossary.empty;
    }
  }

  Future<void> save(String bookFile, BookGlossary glossary) async {
    _loaded[bookFile] = glossary;
    notifyListeners();
    try {
      await AppFiles.instance
          .writeString(await _file(bookFile), glossary.encode());
      onSaved?.call(bookFile);
    } catch (e) {
      _logger.warning('Glossary not saved', tag: 'Glossary', error: e);
    }
  }

  /// [bookFile]'s glossary as saved (JSON), or null.
  Future<String?> savedText(String bookFile) async =>
      AppFiles.instance.readString(await _file(bookFile));

  /// A glossary from another device ([data] is its JSON): kept and shown,
  /// without counting as a change made here.
  Future<void> applySynced(String bookFile, String data) async {
    final glossary = BookGlossary.decode(data);
    await AppFiles.instance.writeString(await _file(bookFile), data);
    _loaded[bookFile] = glossary;
    notifyListeners();
  }

  /// [bookFile]'s glossary, made with [translator] when the book has none
  /// yet (once at a time per book). Without a model that takes free-form
  /// requests it stays as it is.
  Future<BookGlossary> ensure({
    required String bookFile,
    required String bookPath,
    required Translator translator,
    TranslationPriority priority = TranslationPriority.ahead,
  }) async {
    final current = await load(bookFile);
    if (current.complete) return current;
    return make(
        bookFile: bookFile,
        bookPath: bookPath,
        translator: translator,
        priority: priority);
  }

  /// Makes [bookFile]'s glossary again; the reader's edits stay.
  Future<BookGlossary> make({
    required String bookFile,
    required String bookPath,
    required Translator translator,
    TranslationPriority priority = TranslationPriority.ahead,
  }) {
    final running = _making[bookFile];
    if (running != null) return running;
    final job =
        _make(bookFile, bookPath, translator, priority).whenComplete(() {
      _making.remove(bookFile);
      notifyListeners();
    });
    _making[bookFile] = job;
    notifyListeners();
    return job;
  }

  Future<BookGlossary> _make(String bookFile, String bookPath,
      Translator translator, TranslationPriority priority) async {
    final old = await load(bookFile);
    final watch = Stopwatch()..start();
    final survey = await AppFiles.instance
        .readBytes(bookPath)
        .then((bytes) => runHeavy(() => epubSurvey(bytes!)))
        .catchError((_) => (
              candidates: <GlossaryCandidate>[],
              narration: Narration.unknown,
              hero: null as String?,
            ));
    final candidates = survey.candidates;
    if (candidates.isEmpty) return old;
    final entries = <GlossaryEntry>[];
    var answered = false;
    for (var i = 0; i < candidates.length; i += glossaryRequestSize) {
      final chunk = candidates.sublist(
          i, (i + glossaryRequestSize).clamp(0, candidates.length));
      final answer = await translator.complete(glossaryPrompt(chunk),
          maxTokens: 36 * chunk.length + 48,
          // Not with the instructions as a system message: measured, the
          // model then names and sorts the entries worse.
          priority: priority);
      if (answer == null) break;
      answered = true;
      entries.addAll(parseGlossaryAnswer(answer, chunk));
    }
    if (!answered) return old;
    final glossary = mergeGlossary(old, entries)
        .copyWith(narration: survey.narration, hero: survey.hero);
    _logger.info('Glossary made', tag: 'Glossary', metadata: {
      'book': bookFile,
      'candidates': candidates.length,
      'entries': glossary.entries.length,
      'names': glossary.entries.where((e) => e.isName).length,
      'narration': glossary.narration.name,
      'hero': glossary.hero,
      'ms': watch.elapsedMilliseconds,
    });
    await save(bookFile, glossary);
    return glossary;
  }

  /// Forgets [bookFile]'s glossary (the book was removed).
  Future<void> remove(String bookFile) async {
    _loaded.remove(bookFile);
    try {
      await AppFiles.instance.delete(await _file(bookFile));
    } catch (_) {}
  }

  /// [entry] changed by the reader (replacing the one with its source).
  Future<void> updateEntry(String bookFile, GlossaryEntry entry) async {
    final glossary = await load(bookFile);
    final entries = [
      for (final e in glossary.entries)
        if (e.source != entry.source) e,
      entry.copyWith(edited: true),
    ];
    await save(bookFile, glossary.copyWith(entries: entries));
  }

  /// Removes [source]: kept as an empty, edited entry so making the
  /// glossary again does not bring it back.
  Future<void> removeEntry(String bookFile, String source) async {
    final glossary = await load(bookFile);
    final removed = glossary.entries.where((e) => e.source == source).toList();
    if (removed.isEmpty) return;
    await updateEntry(bookFile, removed.first.copyWith(target: ''));
  }
}
