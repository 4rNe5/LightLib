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
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/database.dart';
import 'package:openlib/services/epub_package.dart';
import 'package:openlib/services/logger.dart';
import 'package:openlib/services/translation/background_translation_notice.dart';
import 'package:openlib/services/translation/paragraph_text.dart';
import 'package:openlib/services/translation/translation_cache.dart';
import 'package:openlib/services/translation/translation_model_store.dart';
import 'package:openlib/services/translation/translation_models.dart';
import 'package:openlib/services/translation/reader_translation_controller.dart'
    show precedingContext;
import 'package:openlib/services/translation/translator.dart';

/// Preference: translate library books in the background (off unless
/// turned on).
const autoTranslateLibraryPref = 'autoTranslateLibrary';

/// Preference: library books only while the phone charges.
const translateLibraryChargingOnlyPref = 'translateLibraryChargingOnly';

/// Why library translation is waiting.
enum BookTranslationWait {
  none,

  /// A book is open: the reader gets the engine and the GPU.
  reading,

  /// The app is in the background without its notification service.
  appClosed,

  /// The phone is warm (thermal status moderate or worse).
  warm,
  batteryLow,
  powerSave,

  /// "Only while charging" is on and no charger is connected.
  needsCharger,
}

/// Whether library translation may run now, and if not why.
BookTranslationWait backgroundWaitReason({
  required DeviceLoad load,
  required bool reading,
  required bool canRunNow,
  required bool chargingOnly,
}) {
  if (reading) return BookTranslationWait.reading;
  if (!canRunNow) return BookTranslationWait.appClosed;
  if (load.thermal >= 2) return BookTranslationWait.warm;
  if (chargingOnly && !load.charging) return BookTranslationWait.needsCharger;
  if (!load.charging && load.powerSave) return BookTranslationWait.powerSave;
  if (!load.charging && load.battery < 20) {
    return BookTranslationWait.batteryLow;
  }
  return BookTranslationWait.none;
}

/// How long to rest after a paragraph that took [took]: busy at most 40% of
/// the time (50% on a charger), 25% once the phone warms up.
Duration backgroundRest(Duration took, DeviceLoad load) {
  final factor = load.thermal >= 1
      ? 3.0
      : load.charging
          ? 1.0
          : 1.5;
  final rest = took * factor;
  const min = Duration(milliseconds: 300);
  const max = Duration(seconds: 30);
  return rest < min
      ? min
      : rest > max
          ? max
          : rest;
}

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
/// split exactly as the book reader splits it (so both share one cache).
/// Books it cannot read fall back to the older reader's parser, whose
/// null entries need no translation (images, scene breaks).
Future<List<String?>> epubParagraphTexts(String path) => Isolate.run(() async {
      final bytes = await File(path).readAsBytes();
      final paragraphs = epubReaderParagraphs(bytes);
      if (paragraphs != null && paragraphs.isNotEmpty) return paragraphs;
      final book = await EpubReader.readBook(bytes);
      final chapters = parseChapters(book);
      final flat = parseParagraphs(chapters, book.Content).flatParagraphs;
      return [
        for (final paragraph in flat)
          () {
            final element = paragraph.element;
            if (containsImage(element)) return null;
            final text = paragraphText(element);
            return shouldTranslate(text) ? text : null;
          }(),
      ];
    });

/// Works through the library's EPUBs one paragraph at a time with the
/// shared engine at background priority, only when turned on, and gently:
/// - it waits while a book is open, so reading never competes with it;
/// - it rests after every paragraph (busy at most 40% of the time) and
///   waits while the phone is warm, on battery saver or low on battery;
/// - on Android it keeps going after the app is left, with an ongoing
///   notification and progress bar (a foreground service); elsewhere it
///   waits until the app is back.
/// Results go to the book's translation file next to the book, so it
/// picks up where it left off.
class BookTranslationService extends ChangeNotifier
    with WidgetsBindingObserver {
  BookTranslationService._();
  static final BookTranslationService instance = BookTranslationService._();

  /// How often the battery and temperature are read again.
  static const loadCheck = Duration(seconds: 20);

  final AppLogger _logger = AppLogger();
  final Map<String, BookTranslationProgress> _progress = {};
  final BackgroundTranslationNotice _notice =
      BackgroundTranslationNotice.instance;
  bool _started = false;
  bool _running = false;
  bool _foreground = true;
  bool _enabled = false;
  bool _chargingOnly = false;
  bool _rescan = false;
  bool _serviceTimedOut = false;
  String? _error;
  BookTranslationWait _wait = BookTranslationWait.none;
  DeviceLoad _load = DeviceLoad.nominal;
  DateTime? _loadAt;
  AppLocalizations? _l10n;
  DateTime _noticeAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _translatedThisRun = 0;
  int _bookNumber = 0;
  int _bookCount = 0;
  String? _currentFile;

  Map<String, BookTranslationProgress> get progress =>
      Map.unmodifiable(_progress);
  bool get enabled => _enabled;
  bool get chargingOnly => _chargingOnly;
  bool get running => _running;
  String? get error => _error;

  /// Why it is waiting now ([BookTranslationWait.none] while translating).
  BookTranslationWait get wait => _wait;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    final db = MyLibraryDb.instance;
    Future<Object?> pref(String key) =>
        db.getPreference(key).catchError((_) => null);
    _enabled = await pref(autoTranslateLibraryPref) == 1;
    _chargingOnly = await pref(translateLibraryChargingOnlyPref) == 1;
    TranslationStyle.lightNovel =
        await pref(translationLightNovelStylePref) != 0;
    SharedTranslationEngine.cpuOnly =
        await pref(translationDevicePref) == 'cpu';
    final formats = await pref(TranslationPromptFormats.pref);
    TranslationPromptFormats.overrides =
        TranslationPromptFormats.decode(formats is String ? formats : null);
    _notice.onStopRequested = () => unawaited(setEnabled(false));
    _notice.onTimedOut = () => _serviceTimedOut = true;
    SharedTranslationEngine.instance.readers.addListener(_onReaders);
    scanSoon();
  }

  Future<void> setEnabled(bool on) async {
    _enabled = on;
    await MyLibraryDb.instance
        .savePreference(autoTranslateLibraryPref, on ? 1 : 0)
        .catchError((_) {});
    notifyListeners();
    if (on) {
      scanSoon();
    } else {
      await _notice.hide();
    }
  }

  Future<void> setChargingOnly(bool on) async {
    _chargingOnly = on;
    _loadAt = null;
    await MyLibraryDb.instance
        .savePreference(translateLibraryChargingOnlyPref, on ? 1 : 0)
        .catchError((_) {});
    notifyListeners();
  }

  void _onReaders() {
    // A book was closed: the waiting loop notices within a few seconds;
    // nothing else to do here.
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasForeground = _foreground;
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && !wasForeground) {
      _serviceTimedOut = false;
      scanSoon();
    }
  }

  /// Looks at the library again (after an import, a download, a model
  /// or language change) and continues with what is left.
  void scanSoon() {
    _rescan = true;
    _error = null;
    if (!_running) unawaited(_run());
  }

  bool get _stopRequested => !_enabled || _rescan;

  Future<void> _run() async {
    if (_running) return;
    _running = true;
    _translatedThisRun = 0;
    notifyListeners();
    LocalLlmTranslator? translator;
    var finished = false;
    try {
      while (_rescan) {
        _rescan = false;
        if (!_enabled) break;
        final model = await TranslationModelStore.instance.activeModel();
        if (model == null) break;
        _l10n = await _localizations();
        final target = languageForCode(await MyLibraryDb.instance
            .getPreference(translationTargetLanguagePref)
            .catchError((_) => null) as String?);
        final books = (await MyLibraryDb.instance.getAll())
            .where((b) => (b.format ?? '').toLowerCase() == 'epub')
            .toList();
        final storage =
            (await MyLibraryDb.instance.getPreference('bookStorageDirectory'))
                .toString();

        _bookCount = books.length;
        for (var n = 0; n < books.length; n++) {
          if (_stopRequested) break;
          final book = books[n];
          _bookNumber = n + 1;
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
        finished = _enabled && !_rescan;
      }
    } catch (e) {
      _error = e.toString();
      _logger.warning('Background book translation stopped',
          tag: 'BookTranslation', error: e);
    } finally {
      if (translator != null) SharedTranslationEngine.instance.release();
      _running = false;
      _wait = BookTranslationWait.none;
      _currentFile = null;
      final l10n = _l10n;
      final allDone = finished &&
          _error == null &&
          _progress.values.every((b) => b.state == BookTranslationState.done);
      await _notice.hide(
          doneTitle: allDone && _translatedThisRun > 0
              ? l10n?.translationNoticeDone
              : null,
          doneText: allDone && _translatedThisRun > 0
              ? l10n?.translationNoticeDoneCount(_progress.length)
              : null);
      notifyListeners();
    }
  }

  Future<AppLocalizations> _localizations() async {
    final saved = await MyLibraryDb.instance
        .getPreference('locale')
        .catchError((_) => null);
    var locale = saved is String && saved.isNotEmpty
        ? Locale(saved)
        : WidgetsBinding.instance.platformDispatcher.locale;
    final supported = AppLocalizations.supportedLocales
        .any((l) => l.languageCode == locale.languageCode);
    if (!supported) locale = const Locale('en');
    return lookupAppLocalizations(Locale(locale.languageCode));
  }

  Future<DeviceLoad> _deviceLoad() async {
    final at = _loadAt;
    if (at == null || DateTime.now().difference(at) > loadCheck) {
      _load = await _notice.deviceLoad();
      _loadAt = DateTime.now();
    }
    return _load;
  }

  /// Returns when a paragraph may run, false when the run should stop.
  /// While waiting, the reason is shown in settings and the notification.
  Future<bool> _waitForRoom() async {
    while (true) {
      if (_stopRequested) return false;
      final load = await _deviceLoad();
      final reason = backgroundWaitReason(
        load: load,
        reading: SharedTranslationEngine.instance.readers.value > 0,
        canRunNow: _foreground || (_notice.showing && !_serviceTimedOut),
        chargingOnly: _chargingOnly,
      );
      if (reason != _wait) {
        _wait = reason;
        notifyListeners();
        await _updateNotice(force: true);
      }
      if (reason == BookTranslationWait.none) return true;
      await Future<void>.delayed(reason == BookTranslationWait.reading
          ? const Duration(seconds: 2)
          : const Duration(seconds: 5));
      if (reason != BookTranslationWait.reading) _loadAt = null;
    }
  }

  String? _waitText(AppLocalizations l10n) => switch (_wait) {
        BookTranslationWait.none => null,
        BookTranslationWait.reading => l10n.translationWaitReading,
        BookTranslationWait.appClosed => l10n.translationWaitAppClosed,
        BookTranslationWait.warm => l10n.translationWaitWarm,
        BookTranslationWait.batteryLow => l10n.translationWaitBattery,
        BookTranslationWait.powerSave => l10n.translationWaitPowerSave,
        BookTranslationWait.needsCharger => l10n.translationWaitCharger,
      };

  /// The progress notification, at most once a second unless [force].
  Future<void> _updateNotice({bool force = false}) async {
    final l10n = _l10n;
    final file = _currentFile;
    if (l10n == null || file == null || !_enabled) return;
    final now = DateTime.now();
    if (!force && now.difference(_noticeAt) < const Duration(seconds: 1)) {
      return;
    }
    _noticeAt = now;
    final book = _progress[file];
    if (book == null) return;
    final percent = (book.fraction * 100).floor();
    // Started from the foreground only; Android refuses it from the
    // background, and then the run waits for the app.
    if (!_notice.showing && !_foreground) return;
    await _notice.show(
      channelName: l10n.translationNoticeChannel,
      title: _waitText(l10n) ?? l10n.translationNoticeTitle,
      text: l10n.translationNoticeProgress(book.title, percent),
      subText: l10n.translationNoticeCount(
          book.done, book.total, _bookNumber, _bookCount),
      progress: book.done,
      max: book.total,
      stopLabel: l10n.translationNoticeStop,
    );
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
    _currentFile = fileName;
    report(BookTranslationState.translating);
    await _updateNotice(force: true);

    final source = sourceLanguageName(await _bookLanguage(path));
    final readings = await Isolate.run(() async {
      final book = EpubPackage.open(await File(path).readAsBytes());
      return book == null ? <String, String>{} : epubRubyReadings(book);
    }).catchError((_) => <String, String>{});
    final seen = <String>{};
    bool pending(String? t) =>
        t != null && !seen.contains(t) && cache.lookup(t) == null;
    for (var i = 0; i < texts.length; i++) {
      final text = texts[i];
      if (!pending(text)) continue;
      if (!await _waitForRoom()) {
        report(BookTranslationState.waiting);
        await cache.flush();
        return;
      }
      // This paragraph and the next ones, as many as one request takes
      // (a line-broken paragraph goes alone).
      final batch = <int>[i];
      final size = text!.contains('\n') ? 1 : translator.batchSize;
      for (var k = i + 1; k < texts.length && batch.length < size; k++) {
        final t = texts[k];
        if (t == null) continue;
        if (!pending(t) || t.contains('\n')) break;
        batch.add(k);
      }
      for (final k in batch) {
        seen.add(texts[k]!);
      }
      final started = DateTime.now();
      try {
        if (batch.length == 1) {
          final out = await translator.translate(
            text,
            targetLanguage: targetLanguage.englishName,
            sourceLanguage: source,
            context: precedingContext(i, (j) => texts[j]),
            following: i + 1 < texts.length ? texts[i + 1] : null,
          );
          if (out.isNotEmpty) {
            cache.store(text, out);
            _translatedThisRun++;
          }
        } else {
          final before = <String>[
            for (var k = i - 1; k >= 0 && k >= i - 6; k--)
              if (texts[k] != null) texts[k]!,
          ].take(3).toList().reversed.toList();
          await translator.translateBatch(
            [for (final k in batch) texts[k]!],
            targetLanguage: targetLanguage.englishName,
            sourceLanguage: source,
            before: before,
            beforeTranslations: [for (final t in before) cache.lookup(t)],
            readings: readings,
            onEach: (n, out) {
              cache.store(texts[batch[n]]!, out);
              _translatedThisRun++;
            },
          );
        }
      } catch (e) {
        _logger.warning('Paragraph translation failed',
            tag: 'BookTranslation', error: e);
        // A model that cannot load fails every paragraph alike.
        if (translator.deviceLabel == null) rethrow;
      }
      i = batch.last;
      await cache.flush();
      report(BookTranslationState.translating);
      await _updateNotice();
      // The time includes waiting behind the reader's requests; resting
      // in proportion to it only makes the pace gentler.
      await Future<void>.delayed(
          backgroundRest(DateTime.now().difference(started), _load));
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
