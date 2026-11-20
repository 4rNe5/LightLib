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
import 'package:openlib/services/translation/gemini/cloud_translator.dart';
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
    if (current.complete) {
      return current.version < BookGlossary.currentVersion
          ? upgrade(bookFile: bookFile, bookPath: bookPath)
          : current;
    }
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

  /// Called with a book's file name after its glossary was set right
  /// ([upgrade]): translations already made can be set right with it.
  static void Function(String bookFile, String bookPath, BookGlossary glossary)?
      onUpgraded;

  final Map<String, Future<BookGlossary>> _upgrading = {};

  /// The glossaries of the other volumes of [bookFile]'s series the
  /// library has (the app says which books those are): what they settled
  /// carries over ([inheritSeries]).
  static Future<List<BookGlossary>> Function(String bookFile)? seriesOf;

  Future<BookGlossary> _withSeries(
      String bookFile, BookGlossary glossary, String text) async {
    final others = seriesOf;
    if (others == null || text.isEmpty) return glossary;
    try {
      return inheritSeries(glossary, await others(bookFile), text);
    } catch (e) {
      _logger.warning('Series glossaries not read', tag: 'Glossary', error: e);
      return glossary;
    }
  }

  /// The book read whole by Gemini, a part at a time: its names and
  /// special terms, with readings where the book gives none. Empty when
  /// Gemini does not answer (the candidates' way is taken then);
  /// `cutShort` when it stopped answering part of the way (the day's
  /// quota, no connection).
  Future<({List<GlossaryEntry> entries, bool cutShort})> _readWhole(
      CloudTranslator gemini, BookSurvey survey) async {
    final answers = <String>[];
    final chunks = bookAnalysisChunks(survey.text);
    for (final chunk in chunks) {
      final answer = await gemini.analyse(
          system: bookAnalysisInstructions,
          user: chunk,
          schema: bookAnalysisSchema);
      if (answer == null) break;
      answers.add(answer);
    }
    return (
      entries: parseBookAnalysis(answers, survey),
      cutShort: answers.length < chunks.length,
    );
  }

  /// A glossary made by an earlier version, set right from the book's
  /// own text ([upgradeGlossary]); no model is asked.
  Future<BookGlossary> upgrade(
          {required String bookFile, required String bookPath}) =>
      _upgrading[bookFile] ??= _upgrade(bookFile, bookPath).whenComplete(() {
        // (Not `=> remove`: that returns this very future, and waiting
        // for it here would never end.)
        _upgrading.remove(bookFile);
      });

  Future<BookGlossary> _upgrade(String bookFile, String bookPath) async {
    final old = await load(bookFile);
    if (old.version >= BookGlossary.currentVersion) return old;
    final survey = await _survey(bookPath);
    // The book could not be read now: tried again next time.
    if (survey.candidates.isEmpty && survey.places.isEmpty) return old;
    final glossary = await _withSeries(
        bookFile, upgradeGlossary(old, survey), survey.text);
    _logger.info('Glossary set right', tag: 'Glossary', metadata: {
      'book': bookFile,
      'entries': glossary.entries.length,
      'changed': [
        for (final e in glossary.entries)
          if (!old.entries.any((o) =>
              o.source == e.source && o.target == e.target))
            e.source,
      ].length,
    });
    await save(bookFile, glossary);
    onUpgraded?.call(bookFile, bookPath, glossary);
    return glossary;
  }

  Future<BookSurvey> _survey(String bookPath) => AppFiles.instance
      .readBytes(bookPath)
      .then((bytes) => runHeavy(() => epubSurvey(bytes!)))
      .catchError((_) => emptySurvey);

  Future<BookGlossary> _make(String bookFile, String bookPath,
      Translator translator, TranslationPriority priority) async {
    final old = await load(bookFile);
    final watch = Stopwatch()..start();
    final survey = await _survey(bookPath);
    final entries = <GlossaryEntry>[];
    var answered = false;
    // Gemini reads the book itself: names no furigana or honorific points
    // to (a place, an item, a spell), and how they are read.
    var whole = 0;
    var cutShort = false;
    if (translator is CloudTranslator && survey.text.isNotEmpty) {
      final read = await _readWhole(translator, survey);
      whole = read.entries.length;
      cutShort = read.cutShort;
      entries.addAll(read.entries);
      answered = read.entries.isNotEmpty;
    }
    final candidates = unnamedCandidates(survey, entries);
    if (survey.candidates.isEmpty && entries.isEmpty) return old;
    var asked = false;
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
      asked = true;
      entries.addAll(parseGlossaryAnswer(answer, chunk));
    }
    if (!answered) return old;
    // The places the book names and the names it writes in hiragana come
    // first: the model's entry for the same word, if it made one, is the
    // one kept.
    // Part of the book read and nobody to ask about the rest (the day's
    // quota ran out, no model on the phone): what was read is used, and
    // the glossary is made again when the book is next translated.
    final unfinished = cutShort && candidates.isNotEmpty && !asked;
    final glossary = await _withSeries(
        bookFile,
        mergeGlossary(
                old, [...survey.places, ...hiraganaNames(survey), ...entries])
            .copyWith(
                narration: survey.narration,
                hero: survey.hero,
                complete: !unfinished),
        survey.text);
    _logger.info('Glossary made', tag: 'Glossary', metadata: {
      'book': bookFile,
      'readWhole': whole,
      if (cutShort) 'readCutShort': true,
      if (unfinished) 'unfinished': true,
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

  /// Called after the reader changed [entry] of [bookFile] (the series'
  /// other volumes are told: `passOnToSeries`).
  static Future<void> Function(String bookFile, GlossaryEntry entry)? onEdited;

  /// [entry] changed by the reader (replacing the one with its source).
  Future<void> updateEntry(String bookFile, GlossaryEntry entry) async {
    final glossary = await load(bookFile);
    final edited = entry.copyWith(edited: true);
    final entries = [
      for (final e in glossary.entries)
        if (e.source != entry.source) e,
      edited,
    ];
    await save(bookFile, glossary.copyWith(entries: entries));
    // (Not waited for: the other volumes' translations are gone through
    // too, and the reader's edit is done.)
    final passOn = onEdited;
    if (passOn != null) {
      unawaited(passOn(bookFile, edited).catchError((Object e) {
        _logger.warning('Glossary edit not passed on',
            tag: 'Glossary', error: e);
      }));
    }
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
