// Translating whole library books, a little at a time, while the app runs.

// Dart imports:
import 'dart:async';
import 'dart:io';
import 'dart:isolate';

// Flutter imports:
import 'package:flutter/widgets.dart';

// Package imports:
// ignore: implementation_imports
import 'package:epub_view/src/data/epub_parser.dart'
    show parseChapters, parseParagraphs;
import 'package:epubx/epubx.dart' show EpubReader;
import 'package:path/path.dart' as p;

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/logger.dart';
import 'package:openlib/services/translation/paragraph_text.dart';
import 'package:openlib/services/translation/translation_cache.dart';
import 'package:openlib/services/translation/translation_model_store.dart';
import 'package:openlib/services/translation/translation_models.dart';
import 'package:openlib/services/translation/translator.dart';

/// Preference: translate library books in the background.
const autoTranslateLibraryPref = 'autoTranslateLibrary';

enum BookTranslationState { waiting, translating, done, failed }

@immutable
class BookTranslationProgress {
  final String fileName;
  final String title;
  final int done;
  final int total;
  final BookTranslationState state;

  const BookTranslationProgress({
    required this.fileName,
    required this.title,
    required this.done,
    required this.total,
    required this.state,
  });

  double get fraction => total == 0 ? 1 : done / total;
}

/// The translatable text of every paragraph of an EPUB, in reading order,
/// split exactly as the reader splits it (so both share one cache). Null
/// entries need no translation (images, scene breaks).
Future<List<String?>> epubParagraphTexts(String path) => Isolate.run(() async {
      final book = await EpubReader.readBook(await File(path).readAsBytes());
      final chapters = parseChapters(book);
      final paragraphs = parseParagraphs(chapters, book.Content).flatParagraphs;
      return [
        for (final paragraph in paragraphs)
          () {
            final element = paragraph.element;
            if (containsImage(element)) return null;
            final text = paragraphText(element);
            return shouldTranslate(text) ? text : null;
          }(),
      ];
    });

/// Works through the library's EPUBs one paragraph at a time with the
/// shared engine at background priority, so a book being read (urgent
/// requests) always goes first. Results go to the book's translation file
/// next to the book. Stops while the app is in the background and picks
/// up where it left off.
class BookTranslationService extends ChangeNotifier
    with WidgetsBindingObserver {
  BookTranslationService._();
  static final BookTranslationService instance = BookTranslationService._();

  /// Pause between paragraphs, so a long run does not keep the GPU and
  /// battery at full load the whole time.
  static const breather = Duration(milliseconds: 400);

  final AppLogger _logger = AppLogger();
  final Map<String, BookTranslationProgress> _progress = {};
  bool _started = false;
  bool _running = false;
  bool _foreground = true;
  bool _enabled = true;
  bool _rescan = false;
  String? _error;

  Map<String, BookTranslationProgress> get progress =>
      Map.unmodifiable(_progress);
  bool get enabled => _enabled;
  bool get running => _running;
  String? get error => _error;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    final saved = await MyLibraryDb.instance
        .getPreference(autoTranslateLibraryPref)
        .catchError((_) => null);
    _enabled = saved != 0;
    final style = await MyLibraryDb.instance
        .getPreference(translationLightNovelStylePref)
        .catchError((_) => null);
    TranslationStyle.lightNovel = style != 0;
    scanSoon();
  }

  Future<void> setEnabled(bool on) async {
    _enabled = on;
    await MyLibraryDb.instance
        .savePreference(autoTranslateLibraryPref, on ? 1 : 0)
        .catchError((_) {});
    notifyListeners();
    if (on) scanSoon();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasForeground = _foreground;
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && !wasForeground) scanSoon();
  }

  /// Looks at the library again (after an import, a download, a model
  /// or language change) and continues with what is left.
  void scanSoon() {
    _rescan = true;
    _error = null;
    if (!_running) unawaited(_run());
  }

  Future<void> _run() async {
    if (_running) return;
    _running = true;
    notifyListeners();
    LocalLlmTranslator? translator;
    try {
      while (_rescan) {
        _rescan = false;
        if (!_enabled) break;
        final model = await TranslationModelStore.instance.activeModel();
        if (model == null) break;
        final target = languageForCode(await MyLibraryDb.instance
            .getPreference(translationTargetLanguagePref)
            .catchError((_) => null) as String?);
        final books = (await MyLibraryDb.instance.getAll())
            .where((b) => (b.format ?? '').toLowerCase() == 'epub')
            .toList();
        final storage =
            (await MyLibraryDb.instance.getPreference('bookStorageDirectory'))
                .toString();

        for (final book in books) {
          if (!_enabled || _rescan) break;
          while (!_foreground) {
            await Future<void>.delayed(const Duration(seconds: 2));
          }
          final fileName = book.getFileName();
          final path = p.join(storage, fileName);
          if (!await File(path).exists()) continue;
          translator ??= await SharedTranslationEngine.instance.acquire();
          if (translator == null) break;
          await _translateBook(
            translator: translator,
            path: path,
            fileName: fileName,
            title: book.title,
            modelId: TranslationStyle.cacheModelId(model.fileName),
            targetLanguage: target,
          );
        }
      }
    } catch (e) {
      _error = e.toString();
      _logger.warning('Background book translation stopped',
          tag: 'BookTranslation', error: e);
    } finally {
      if (translator != null) SharedTranslationEngine.instance.release();
      _running = false;
      notifyListeners();
    }
  }

  Future<void> _translateBook({
    required LocalLlmTranslator translator,
    required String path,
    required String fileName,
    required String title,
    required String modelId,
    required TranslationLanguage targetLanguage,
  }) async {
    final cache = await TranslationCache.open(
      bookFileName: fileName,
      targetLanguage: targetLanguage.code,
      modelId: modelId,
    );
    final List<String?> texts;
    try {
      texts = await epubParagraphTexts(path);
    } catch (e) {
      _progress[fileName] = BookTranslationProgress(
          fileName: fileName,
          title: title,
          done: 0,
          total: 0,
          state: BookTranslationState.failed);
      notifyListeners();
      return;
    }
    final unique = <String>{
      for (final t in texts)
        if (t != null) t
    };
    int done() => unique.where((t) => cache.lookup(t) != null).length;

    void report(BookTranslationState state) {
      _progress[fileName] = BookTranslationProgress(
        fileName: fileName,
        title: title,
        done: done(),
        total: unique.length,
        state: state,
      );
      notifyListeners();
    }

    if (done() == unique.length) {
      report(BookTranslationState.done);
      return;
    }
    report(BookTranslationState.translating);

    final source = sourceLanguageName(await _bookLanguage(path));
    final seen = <String>{};
    for (var i = 0; i < texts.length; i++) {
      if (!_enabled || _rescan) {
        report(BookTranslationState.waiting);
        await cache.flush();
        return;
      }
      while (!_foreground) {
        await cache.flush();
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      final text = texts[i];
      if (text == null || !seen.add(text) || cache.lookup(text) != null) {
        continue;
      }
      try {
        final out = await translator.translate(
          text,
          targetLanguage: targetLanguage.englishName,
          sourceLanguage: source,
        );
        if (out.isNotEmpty) cache.store(text, out);
      } catch (e) {
        _logger.warning('Paragraph translation failed',
            tag: 'BookTranslation', error: e);
        // A model that cannot load fails every paragraph alike.
        if (translator.deviceLabel == null) rethrow;
      }
      if (i % 5 == 0) report(BookTranslationState.translating);
      await Future<void>.delayed(breather);
    }
    await cache.flush();
    report(done() == unique.length
        ? BookTranslationState.done
        : BookTranslationState.waiting);
  }

  Future<String?> _bookLanguage(String path) async {
    try {
      return await Isolate.run(() async {
        final book = await EpubReader.openBook(await File(path).readAsBytes());
        final languages = book.Schema?.Package?.Metadata?.Languages;
        return (languages == null || languages.isEmpty)
            ? null
            : languages.first;
      });
    } catch (_) {
      return null;
    }
  }
}
