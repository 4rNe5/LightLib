// Books' glossaries ([BookGlossary]): kept per book file in the app's
// support directory, made by the translation model the first time a book
// is translated, and edited by the reader.

// Dart imports:
import 'dart:async';
import 'dart:io';
import 'dart:isolate';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// Project imports:
import 'package:openlib/services/logger.dart';
import 'package:openlib/services/translation/book_glossary.dart';
import 'package:openlib/services/translation/translator.dart';

class GlossaryService extends ChangeNotifier {
  GlossaryService._();
  static final GlossaryService instance = GlossaryService._();

  /// Where glossaries are kept (replaceable in tests).
  Future<Directory> Function() directory = () async =>
      Directory(p.join((await getApplicationSupportDirectory()).path,
          'glossaries'));

  final Map<String, BookGlossary> _loaded = {};
  final Map<String, Future<BookGlossary>> _making = {};
  final AppLogger _logger = AppLogger();

  /// Books whose glossary the model is making now.
  bool isMaking(String bookFile) => _making.containsKey(bookFile);

  /// The glossary in memory, if loaded.
  BookGlossary? cached(String bookFile) => _loaded[bookFile];

  Future<File> _file(String bookFile) async {
    final dir = await directory();
    if (!await dir.exists()) await dir.create(recursive: true);
    final safe = bookFile.replaceAll(RegExp(r'[^\w.\-]'), '_');
    return File(p.join(dir.path, '$safe.json'));
  }

  Future<BookGlossary> load(String bookFile) async {
    final known = _loaded[bookFile];
    if (known != null) return known;
    try {
      final file = await _file(bookFile);
      final glossary = await file.exists()
          ? BookGlossary.decode(await file.readAsString())
          : BookGlossary.empty;
      return _loaded[bookFile] = glossary;
    } catch (_) {
      return BookGlossary.empty;
    }
  }

  Future<void> save(String bookFile, BookGlossary glossary) async {
    _loaded[bookFile] = glossary;
    notifyListeners();
    try {
      await (await _file(bookFile)).writeAsString(glossary.encode());
    } catch (e) {
      _logger.warning('Glossary not saved', tag: 'Glossary', error: e);
    }
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
    final job = _make(bookFile, bookPath, translator, priority)
        .whenComplete(() {
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
    final survey = await Isolate.run(() async =>
            epubSurvey(await File(bookPath).readAsBytes()))
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
          maxTokens: 36 * chunk.length + 48, priority: priority);
      if (answer == null) break;
      answered = true;
      entries.addAll(parseGlossaryAnswer(answer, chunk));
    }
    if (!answered) return old;
    final glossary = mergeGlossary(old, entries).copyWith(
        narration: survey.narration, hero: survey.hero);
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
