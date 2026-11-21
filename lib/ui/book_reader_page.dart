// The EPUB reader: the book is laid out by foliate-js in a web view
// (assets/reader, built from reader_web/), which renders EPUBs the way
// dedicated readers do - the book's own CSS, vertical Japanese with ruby,
// SVG and full-page images, fixed-layout books - and this page adds the
// app around it: bars, contents, themes and type, on-device translation
// and reading aloud.

// Dart imports:
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui show FrameTiming;

// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/services.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:url_launcher/url_launcher.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/database.dart'
    show BookReading, MyLibraryDb;
import 'package:openlib/services/epub_package.dart';
import 'package:openlib/services/heavy_work.dart';
import 'package:openlib/services/platform_utils.dart';
import 'package:openlib/services/logger.dart';
import 'package:openlib/services/reader_fonts.dart';
import 'package:openlib/services/reader_settings.dart';
import 'package:openlib/services/study/book_difficulty.dart';
import 'package:openlib/services/study/japanese_tools.dart';
import 'package:openlib/services/study/study_assistant.dart';
import 'package:openlib/services/study/study_data.dart';
import 'package:openlib/services/study/study_settings.dart';
import 'package:openlib/services/storage/app_files.dart';
import 'package:openlib/services/sync/sync_service.dart';
import 'package:openlib/services/study/study_store.dart';
import 'package:openlib/services/translation/glossary_service.dart';
import 'package:openlib/services/translation/reader_translation_controller.dart';
import 'package:openlib/services/translation/translation_cache.dart';
import 'package:openlib/services/translation/translation_model_store.dart';
import 'package:openlib/services/translation/translation_models.dart';
import 'package:openlib/services/translation/translation_engine.dart';
import 'package:openlib/services/translation/translation_repair.dart';
import 'package:openlib/services/translation/translator.dart';
import 'package:openlib/services/tts_service.dart';
import 'package:openlib/ui/components/paged_book_view.dart' show ReaderLayout;
import 'package:openlib/ui/components/motion.dart';
import 'package:openlib/ui/components/glossary_sheet.dart';
import 'package:openlib/ui/components/reader_settings_sheet.dart';
import 'package:openlib/ui/components/snack_bar_widget.dart';
import 'package:openlib/ui/components/study_sheets.dart';
import 'package:openlib/ui/study_page.dart';
import 'package:openlib/ui/translation_settings_page.dart';
import 'package:openlib/ui/reader_host/reader_host.dart';
import 'package:openlib/ui/reader_host/reader_resources.dart';
import 'package:openlib/web/web_settings_page.dart';

export 'package:openlib/ui/reader_host/reader_resources.dart';

/// Whether this platform has the web view the book reader needs (Android,
/// Apple platforms and the web); elsewhere the Flutter-drawn reader is used.
bool bookReaderSupported() =>
    PlatformUtils.isWeb ||
    PlatformUtils.isAndroid ||
    PlatformUtils.isIOS ||
    PlatformUtils.isMacOS;

/// Saved positions of this reader carry this prefix (a foliate CFI); the
/// older reader's positions are not CFIs it can resolve.
const bookReaderPositionPrefix = 'foliate:';

/// The CFI in a saved position, or null when it is not one of ours.
String? bookReaderCfi(String? saved) =>
    saved != null && saved.startsWith(bookReaderPositionPrefix)
        ? saved.substring(bookReaderPositionPrefix.length)
        : null;

/// Paragraph keys for the translator: one index space across sections.
const _sectionStride = 100000;

class BookReaderPage extends ConsumerStatefulWidget {
  const BookReaderPage({
    super.key,
    required this.fileName,
    required this.filePath,
    this.onFallback,
    this.opening,
  });

  final String fileName;
  final String filePath;

  /// What to show until the book's first page is up, instead of the
  /// spinner (the web: the book's cover and name).
  final WidgetBuilder? opening;

  /// Opens the book in the older reader instead (shown when this one
  /// cannot display it).
  final VoidCallback? onFallback;

  @override
  ConsumerState<BookReaderPage> createState() => _BookReaderPageState();
}

class _TocEntry {
  _TocEntry(this.label, this.href, this.depth);
  final String label;
  final String href;
  final int depth;
}

class _BookReaderPageState extends ConsumerState<BookReaderPage> {
  final AppLogger _logger = AppLogger();
  late final ReaderResources _resources =
      ReaderResources(bookPath: widget.filePath);
  ReaderHostController? _host;
  bool _pageReady = false;
  bool _opened = false;

  /// The book's first page is on screen.
  bool _shown = false;

  /// The picture shown while the book opens has been up long enough to
  /// be seen (a book that opens at once would flash it otherwise; on
  /// the web it goes the moment the page is there).
  bool _openingSeen = kIsWeb;
  Timer? _openingTimer;

  /// The page may start (its web view be made). With the opening picture
  /// it waits for the way in to end: making a web view and loading a
  /// book are work on the thread the frames are drawn on, and begun
  /// with the route they made the cover's flight here stutter.
  bool _hostAllowed = true;
  Animation<double>? _wayIn;

  /// The opening picture is taken down: the first page is up, the
  /// picture was seen, and frames come evenly again ([_leaveOpening]).
  bool _openingGone = false;
  EvenFrames? _calm;

  /// Frames drawn while the book opens, for the log: the way in, the
  /// loading under the picture, the picture leaving. (Whether the way in
  /// is smooth on a phone cannot be seen from a desk; the owner's log
  /// says how many frames were late, and in which part.)
  final List<_FrameCount> _openingFrames = [
    _FrameCount('way in'),
    _FrameCount('loading'),
    _FrameCount('leaving'),
  ];
  int _openingPart = 0;
  bool _timingFrames = false;
  Timer? _framesTimer;

  void _onFrameTimings(List<ui.FrameTiming> timings) {
    for (final t in timings) {
      _openingFrames[_openingPart].add(t);
    }
  }

  void _logOpeningFrames() {
    if (!_timingFrames) return;
    _timingFrames = false;
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    _logger.info('Opening frames', tag: 'ReaderPage', metadata: {
      for (final part in _openingFrames) part.name: part.summary,
    });
  }
  String? _error;

  // The book.
  String? _title;
  String? _language;
  String _dir = '';
  bool _fixedLayout = false;
  List<_TocEntry> _toc = const [];

  // Where the reader is.
  String? _cfi;
  double _fraction = 0;
  String _tocLabel = '';
  String _tocHref = '';
  int _section = -1;
  Timer? _saveTimer;

  /// The book is marked finished (as saved, or since its end was reached
  /// here).
  bool _finished = false;

  // The bars over the page: shown on open and on a tap in the middle.
  bool _chrome = true;
  double? _seeking;

  // Paragraph texts of the loaded sections, for translating and reading.
  final Map<int, List<String>> _sections = {};
  final Map<int, Set<int>> _sent = {};

  // Translation.
  ReaderTranslationController? _translation;
  TranslationCache? _cache;
  bool _translateOn = false;
  bool _translationStarting = false;
  String? _targetCode;
  bool _pushScheduled = false;

  // Study.
  StudySettingsData get _study => StudySettings.instance.value;
  bool _toolsLoaded = false;
  bool _toolsLoading = false;
  Translator? _studyTranslator;
  Future<Translator?>? _studyTranslatorFuture;
  StudyAssistant? _assistantCache;
  TranslationLanguage? _studyLanguage;
  Map<String, dynamic>? _selection;
  final ValueNotifier<double> _analysisProgress = ValueNotifier(0);
  Completer<BookDifficulty?>? _analysis;
  final Map<int, Set<int>> _readParagraphs = {};
  int _unsavedChars = 0;
  String? _lastStudyJson;

  // Reading aloud.
  TtsService? _tts;
  TtsState _ttsState = TtsState.idle;
  List<String> _speech = const [];
  int _speechIndex = 0;
  bool _speechWaitsForSection = false;

  AppLifecycleListener? _lifecycle;
  Timer? _settingsTimer;
  String? _lastSettingsJson;
  final FocusNode _focus = FocusNode();

  ReaderSettingsData get _settings => ReaderSettings.instance.value;

  @override
  void initState() {
    super.initState();
    SyncService.instance.arrived.addListener(_onSyncArrived);
    redoMarks.addListener(_onRedoMarked);
    if (!_openingSeen && widget.opening != null) {
      _hostAllowed = false;
      _timingFrames = true;
      SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
      _openingTimer = Timer(const Duration(milliseconds: 520), () {
        if (!mounted) return;
        setState(() => _openingSeen = true);
        _leaveOpening();
      });
    } else {
      _openingSeen = true;
    }
    SharedTranslationEngine.instance.enterReader();
    ReaderSettings.instance.addListener(_onSettingsChanged);
    ReaderFonts.instance.addListener(_onSettingsChanged);
    unawaited(ReaderSettings.instance.load());
    unawaited(ReaderFonts.instance.load());
    StudySettings.instance.addListener(_onStudyChanged);
    JapaneseTools.instance.addListener(_onStudyChanged);
    unawaited(StudySettings.instance.load());
    unawaited(StudyStore.instance.load());
    unawaited(StudyData.instance.load());
    if (ttsAvailableOnPlatform()) {
      _tts = TtsService();
      _tts!.onStateChanged.listen((s) {
        if (mounted) setState(() => _ttsState = s);
      });
      _tts!.onChunkComplete(_speakNext);
    }
    _lifecycle = AppLifecycleListener(
      onHide: () {
        _translation?.pause();
        // (The home-screen widgets show where the book is by the time
        // the home screen is back.)
        _saveNow(leaving: true);
      },
      onShow: () => _translation?.resume(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hostAllowed || _wayIn != null) return;
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null ||
        animation.isCompleted ||
        AppMotion.reduced(context)) {
      _hostAllowed = true;
      _openingPart = 1;
      return;
    }
    _wayIn = animation..addStatusListener(_onWayIn);
  }

  void _onWayIn(AnimationStatus status) {
    // (Completed: the page is in. Dismissed: it was left on the way.)
    if (status != AnimationStatus.completed) return;
    _wayIn?.removeStatusListener(_onWayIn);
    if (mounted && !_hostAllowed) {
      setState(() {
        _hostAllowed = true;
        _openingPart = 1;
      });
    }
  }

  void _openingLeft() {
    if (!mounted) return;
    setState(() => _openingGone = true);
    _openingPart = 2;
    // (The fade is 260 ms; a little after it, what was counted is
    // written down.)
    _framesTimer = Timer(const Duration(milliseconds: 600), _logOpeningFrames);
  }

  /// Takes the opening picture down once the first page is up and the
  /// picture was seen - and not in the middle of the page's own work: it
  /// waits until a few frames in a row came on time (at most 0.8 s), so
  /// the fade is drawn evenly. The first page of a book is laid out,
  /// its translation put back and its settings sent just then; a fade
  /// begun at that moment lost most of its frames.
  void _leaveOpening() {
    if (_openingGone || _calm != null || widget.opening == null) return;
    if (!(_shown && _openingSeen)) return;
    if (kIsWeb || AppMotion.reduced(context)) {
      _openingLeft();
      return;
    }
    _calm = EvenFrames(onEven: _openingLeft)..start();
  }

  @override
  void dispose() {
    _wayIn?.removeStatusListener(_onWayIn);
    _calm?.dispose();
    _framesTimer?.cancel();
    _logOpeningFrames();
    _saveNow(leaving: true);
    // What was read and translated goes to the other devices.
    SyncService.instance.arrived.removeListener(_onSyncArrived);
    redoMarks.removeListener(_onRedoMarked);
    SyncService.instance.readerClosed();
    SharedTranslationEngine.instance.leaveReader();
    ReaderSettings.instance.removeListener(_onSettingsChanged);
    ReaderFonts.instance.removeListener(_onSettingsChanged);
    StudySettings.instance.removeListener(_onStudyChanged);
    JapaneseTools.instance.removeListener(_onStudyChanged);
    _analysisProgress.dispose();
    unawaited(_studyTranslator?.dispose());
    _lifecycle?.dispose();
    _saveTimer?.cancel();
    _openingTimer?.cancel();
    _settingsTimer?.cancel();
    GlossaryService.instance.removeListener(_onGlossaryChanged);
    _translation?.removeListener(_onTranslationChanged);
    _translation?.dispose();
    _tts?.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // The page
  // ------------------------------------------------------------------

  Future<void> _js(String code) async {
    try {
      await _host?.evaluate(code);
    } catch (e) {
      _logger.warning('Reader script failed', tag: 'Reader', error: e);
    }
  }

  Future<void> _openBook() async {
    if (_opened || !_pageReady) return;
    _opened = true;
    // Where the book was left on another device, and what was translated
    // there - waited for a few seconds at most (offline, it opens as is).
    await SyncService.instance
        .syncBook(widget.fileName)
        .timeout(const Duration(seconds: 4), onTimeout: () {});
    final saved = await MyLibraryDb.instance
        .getBookState(widget.fileName)
        .catchError((_) => null);
    _finished = await MyLibraryDb.instance
        .isCompleted(widget.fileName)
        .catchError((_) => false);
    final String url;
    try {
      url = await _host!.bookUrl();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
      return;
    }
    final options = {
      'url': url,
      'name': widget.fileName,
      'cfi': bookReaderCfi(saved),
      'settings': await _jsSettings(),
    };
    await _js('window.reader.open(${jsonEncode(options)})');
  }

  void _onMessage(Map<String, dynamic> msg) {
    if (!mounted) return;
    switch (msg['type']) {
      case 'pageReady':
        _pageReady = true;
        unawaited(_openBook());
      case 'book':
        setState(() {
          _title = (msg['title'] as String?)?.trim();
          _language = msg['language'] as String?;
          _dir = msg['dir'] as String? ?? '';
          _fixedLayout = msg['fixedLayout'] == true;
          _toc = [
            for (final t in (msg['toc'] as List? ?? const []))
              _TocEntry('${t['label']}', '${t['href']}',
                  (t['depth'] as num?)?.toInt() ?? 0),
          ];
        });
        unawaited(_restoreTranslation());
        _lastStudyJson = null;
        unawaited(_pushStudy());
        // Which way the book is written is known now: a wide screen's
        // two pages are for text that runs across.
        if (!kIsWeb && _layoutWidth >= 600) unawaited(_pushSettings());
      case 'relocate':
        final cfi = msg['cfi'] as String?;
        final fraction = (msg['fraction'] as num?)?.toDouble() ?? _fraction;
        final label = msg['tocLabel'] as String? ?? '';
        // The web: every frame the app draws is drawn on the thread the
        // page scrolls on, so one is asked for only when something on
        // screen changes (the footer's chapter or whole percent; with the
        // bars up, the slider).
        final seen = !kIsWeb ||
            _chrome ||
            !_shown ||
            label != _tocLabel ||
            (fraction * 100).round() != (_fraction * 100).round();
        void take() {
          _shown = true;
          if (cfi != null && cfi.isNotEmpty) _cfi = cfi;
          _fraction = fraction;
          _tocLabel = label;
          _tocHref = msg['tocHref'] as String? ?? '';
          _section = (msg['section'] as num?)?.toInt() ?? _section;
        }

        seen ? setState(take) : take();
        _leaveOpening();
        _saveSoon();
        // The last page: the book is finished (a short book's last page
        // starts well before 99.5%, so the page says when it is the end).
        final sections = (msg['sections'] as num?)?.toInt() ?? 0;
        final lastPage = sections > 0 &&
            _section == sections - 1 &&
            (msg['atEnd'] == true || _fixedLayout);
        if (!_finished &&
            (lastPage || fraction >= BookReading.finishedFraction)) {
          _finished = true;
          _saveNow(finished: true);
        }
        if (_speechWaitsForSection) _continueSpeechInSection();
      case 'paragraphs':
        final section = (msg['section'] as num).toInt();
        _sections[section] = [
          for (final t in (msg['texts'] as List? ?? const [])) '$t'
        ];
        _sent[section] = {};
        if (_translateOn) _pushTranslations();
      case 'visible':
        final section = (msg['section'] as num).toInt();
        final first = (msg['first'] as num).toInt();
        final last = (msg['last'] as num).toInt();
        _countRead(section, first, last);
        if (_translateOn && first >= 0) {
          _translation?.ensureAhead(
            section * _sectionStride + first,
            textAt: _textAt,
            itemCount: (section + 2) * _sectionStride,
            visibleEnd: section * _sectionStride + last,
          );
        }
      case 'turn':
        SharedTranslationEngine.instance.noteInteraction();
        if (_chrome) setState(() => _chrome = false);
      case 'tap':
        setState(() => _chrome = !_chrome);
      case 'word':
        unawaited(_openWord(msg));
      case 'selection':
        // Japanese books: the questions are about Japanese.
        final text = '${msg['text'] ?? ''}';
        if (!_japanese && _selection == null) return;
        setState(() => _selection = text.isEmpty ? null : msg);
      case 'studyTools':
        _toolsLoading = false;
        _toolsLoaded = msg['ready'] == true;
        if (!_toolsLoaded) {
          _logger.warning('Word tools not loaded',
              tag: 'Study', metadata: {'message': '${msg['message']}'});
        }
        if (mounted) setState(() {});
      case 'analysis':
        final result = msg['result'];
        if (msg['progress'] is num) {
          _analysisProgress.value = (msg['progress'] as num).toDouble();
        }
        if (result is Map) {
          final d = BookDifficulty.fromJson(Map<String, dynamic>.from(result));
          StudyStore.instance.keepAnswer(_analysisKey, d.toJson());
          _analysis?.complete(d);
          _analysis = null;
        } else if (msg['error'] != null) {
          _analysis?.complete(null);
          _analysis = null;
        }
      case 'externalLink':
        final href = msg['href'] as String?;
        if (href != null) {
          unawaited(
              launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication)
                  .catchError((_) => false));
        }
      case 'error':
        setState(() => _error = msg['message'] as String? ?? 'error');
        _logger.warning('Book could not be shown',
            tag: 'Reader', metadata: {'message': '${msg['message']}'});
      case 'log':
        _logger.info('${msg['message']}', tag: 'ReaderPage');
    }
  }

  String? _textAt(int index) {
    final texts = _sections[index ~/ _sectionStride];
    final n = index % _sectionStride;
    if (texts == null || n >= texts.length) return null;
    return texts[n];
  }

  // ------------------------------------------------------------------
  // Position
  // ------------------------------------------------------------------

  void _saveSoon() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), _saveNow);
  }

  /// Saves where the reader is. [leaving]: the reader is going away (or
  /// the app is), so the library and the widgets are told once the
  /// position is written - asked before, they would read the one saved a
  /// page ago. [finished]: the end was just reached.
  void _saveNow({bool leaving = false, bool finished = false}) {
    _saveTimer?.cancel();
    if (_unsavedChars > 0) {
      StudyStore.instance.count(StudyDay(chars: _unsavedChars));
      _unsavedChars = 0;
    }
    final cfi = _cfi;
    if (cfi == null || cfi.isEmpty) {
      if (leaving) MyLibraryDb.readingChanged.value++;
      return;
    }
    final db = MyLibraryDb.instance;
    final file = widget.fileName;
    final fraction = _fraction.clamp(0, 1).toStringAsFixed(4);
    // How far that is, for a library that lists the book without its
    // file (written first: saving the position starts the sync).
    unawaited(db
        .setSyncState('frac:$file', fraction)
        .catchError((_) {})
        .then((_) => db.saveBookState(file, '$bookReaderPositionPrefix$cfi'))
        .catchError((_) {})
        .then((_) =>
            finished ? db.setCompleted(file, true) : Future<void>.value())
        .catchError((_) {})
        .whenComplete(() {
      if (leaving) MyLibraryDb.readingChanged.value++;
    }));
  }

  // ------------------------------------------------------------------
  // Settings
  // ------------------------------------------------------------------

  ReaderPalette _palette() => paletteFor(_settings.theme,
      appDark: Theme.of(context).brightness == Brightness.dark);

  static String _css(Color c) =>
      'rgba(${(c.r * 255).round()},${(c.g * 255).round()},'
      '${(c.b * 255).round()},${c.a.toStringAsFixed(3)})';

  bool get _bookIsVertical =>
      _dir == 'rtl' &&
      RegExp(r'^(ja|zh)', caseSensitive: false).hasMatch(_language ?? '');

  /// The writing direction shown: the reader's choice, except that a
  /// vertical Japanese book translated into a language not written
  /// vertically is laid out across.
  ReaderWriting get _writing {
    final chosen = _settings.writing;
    if (chosen != ReaderWriting.auto) return chosen;
    final target = _targetCode ?? '';
    if (_translateOn &&
        _bookIsVertical &&
        !target.startsWith('ja') &&
        !target.startsWith('zh')) {
      return ReaderWriting.horizontal;
    }
    return ReaderWriting.auto;
  }

  /// The script on the page: the translation's while it shows in place,
  /// the book's otherwise (side by side, the original leads).
  FontScript get _displayScript => _translateOn &&
          _targetCode != null &&
          _study.layout == TranslationLayout.replace
      ? ReaderFonts.scriptForLanguage(_targetCode)
      : ReaderFonts.scriptForLanguage(_language);

  Future<Map<String, Object?>> _jsSettings() async {
    final s = _settings;
    final palette = _palette();
    final fonts = ReaderFonts.instance;
    // The chosen fonts, the shown script's first; none chosen keeps the
    // book's own.
    final families = <String>[];
    final faces = <Map<String, String>>[];
    final scripts = [
      _displayScript,
      ...FontScript.values.where((x) => x != _displayScript),
    ];
    for (final script in scripts) {
      final choice = fonts.choiceFor(script);
      if (choice.isSystem) continue;
      final files = await fonts.filesOf(choice);
      if (files.isEmpty) continue;
      final family = 'll-${script.name}';
      families.add('"$family"');
      faces.add({'family': family, 'url': _resources.addFont(files.first)});
    }
    return {
      'background': _css(palette.background),
      'foreground': _css(palette.text),
      'secondary': _css(palette.secondaryText),
      'link': _css(palette.accent),
      'dark': palette.dark,
      'fontSize': s.fontSize,
      'lineHeight': s.lineHeight,
      'letterSpacing': s.letterSpacing,
      // The paginator puts half a side margin on the outer edge.
      'margin': s.margin * 2,
      'marginTop': 14,
      'marginBottom': 26,
      'justify': s.justify,
      'bold': s.boldFor(palette),
      'flow': s.layout == ReaderLayout.scroll ? 'scrolled' : 'paginated',
      'writing': _writing.name,
      'fontFamily': families.isEmpty ? null : families.join(', '),
      'fontFaces': faces,
      'animated': true,
      // A wide window: a column a line can be read across (one when
      // scrolling, two side by side when turning pages).
      if (kIsWeb) 'maxInlineSize': 760,
      if (kIsWeb) 'maxColumns': s.layout == ReaderLayout.scroll ? 1 : 2,
      if (!kIsWeb) ..._wideLayout(s),
    };
  }

  /// The window's width the page was last laid out for.
  double _layoutWidth = 0;

  /// On a wide screen (an unfolded phone, a tablet): two pages side by
  /// side when pages are turned and the text runs across - they meet in
  /// the middle, where a foldable folds - and one column no wider than a
  /// line reads well when scrolling. A phone's width, and text written
  /// down the page: as the page lays itself out.
  Map<String, Object?> _wideLayout(ReaderSettingsData s) {
    final width = _layoutWidth;
    // (Written down the page: by the reader's choice, or the book's own
    // way when the reader leaves it to the book.)
    final writing = _writing;
    final vertical = writing == ReaderWriting.vertical ||
        (writing == ReaderWriting.auto && _bookIsVertical);
    if (width < 600 || vertical) return const {};
    if (s.layout == ReaderLayout.scroll) {
      return const {'maxInlineSize': 680, 'maxColumns': 1};
    }
    if (!s.twoPages) return const {'maxColumns': 1};
    // (The page counts its columns as the width over this, rounded up:
    // anything from half the width to all of it makes two.)
    return {'maxInlineSize': (width * 0.6).round(), 'maxColumns': 2};
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    setState(() {});
    _settingsTimer?.cancel();
    _settingsTimer = Timer(const Duration(milliseconds: 160), _pushSettings);
  }

  Future<void> _pushSettings() async {
    if (!mounted || !_opened) return;
    final json = jsonEncode(await _jsSettings());
    if (json == _lastSettingsJson) return;
    _lastSettingsJson = json;
    await _js('window.reader.setSettings($json)');
  }

  Future<void> _openSettingsSheet() => showReaderSettingsSheet(context,
      script: _displayScript, bookLayout: true);

  // ------------------------------------------------------------------
  // Translation
  // ------------------------------------------------------------------

  static const _translatePref = 'readerTranslate';

  Future<void> _restoreTranslation() async {
    final saved = await MyLibraryDb.instance
        .getPreference(_translatePref)
        .catchError((_) => null);
    if (saved == 1 && mounted) await _setTranslation(true, quiet: true);
  }

  Future<void> _setTranslation(bool on, {bool quiet = false}) async {
    if (_translationStarting) return;
    if (!on) {
      setState(() => _translateOn = false);
      _translation?.pause();
      await _js('window.reader.showTranslations(false)');
      unawaited(_pushSettings());
      await MyLibraryDb.instance
          .savePreference(_translatePref, 0)
          .catchError((_) {});
      return;
    }
    final l10n = AppLocalizations.of(context);
    if (_translation != null) {
      _translation!.resume();
      setState(() => _translateOn = true);
      await _js("window.reader.showTranslations(true, '$_targetCode')");
      unawaited(_pushSettings());
      _pushTranslations();
      await _js('window.reader.reportVisible()');
      await MyLibraryDb.instance
          .savePreference(_translatePref, 1)
          .catchError((_) {});
      return;
    }
    setState(() => _translationStarting = true);
    try {
      final modelId = await TranslationEngines.cacheModelId();
      if (!mounted) return;
      if (modelId == null) {
        // No engine here (the web without a Gemini key, a phone without a
        // model): what was already translated - here or on another
        // device - still shows.
        if (await _showSavedTranslations(quiet: quiet)) return;
        if (!quiet && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(_messageWithAction(
              kIsWeb ? l10n.webTranslateNoEngine : l10n.translationNoModel,
              l10n.translationOpenSettings,
              _openTranslationSettings));
        }
        return;
      }
      final target = languageForCode(await MyLibraryDb.instance
          .getPreference(translationTargetLanguagePref)
          .catchError((_) => null) as String?);
      final cache = await TranslationEngines.openCache(
        bookFileName: widget.fileName,
        targetLanguage: target.code,
      );
      final shared = await TranslationEngines.forReader();
      if (!mounted || shared == null) {
        await shared?.dispose();
        await cache.flush();
        return;
      }
      _targetCode = target.code;
      _cache = cache;
      final urgent = shared;
      _glossaryTranslator = urgent;
      final controller = ReaderTranslationController(
        translator: urgent,
        cache: cache,
        targetLanguage: target.englishName,
        sourceLanguage: sourceLanguageName(_language),
      );
      controller.addListener(_onTranslationChanged);
      // How the book's names are read, from its ruby, for the model.
      final path = widget.filePath;
      unawaited(AppFiles.instance
          .readBytes(path)
          .then((bytes) => runHeavy(() {
                final book = bytes == null ? null : EpubPackage.open(bytes);
                return book == null
                    ? <String, String>{}
                    : epubRubyReadings(book);
              }))
          .then((r) => controller.readings = r, onError: (_) {}));
      // The book's names and terms: loaded, or made once by the model
      // while the first pages are translated ([_onGlossaryChanged]).
      GlossaryService.instance.removeListener(_onGlossaryChanged);
      GlossaryService.instance.addListener(_onGlossaryChanged);
      unawaited(GlossaryService.instance
          .load(widget.fileName)
          .then((_) => _onGlossaryChanged()));
      installTranslationRepair();
      unawaited(GlossaryService.instance
          .ensure(bookFile: widget.fileName, bookPath: path, translator: urgent)
          .then((_) {}, onError: (e) {
        _logger.warning('Glossary not made', tag: 'Glossary', error: e);
      }));
      setState(() {
        _translation = controller;
        _translateOn = true;
      });
      for (final s in _sent.values) {
        s.clear();
      }
      await _js("window.reader.clearTranslations();"
          "window.reader.showTranslations(true, '${target.code}')");
      unawaited(_pushSettings());
      _pushTranslations();
      // Start with what is on screen now.
      await _js('window.reader.reportVisible()');
      await MyLibraryDb.instance
          .savePreference(_translatePref, 1)
          .catchError((_) {});
    } finally {
      if (mounted) setState(() => _translationStarting = false);
    }
  }

  /// Turns translation on with the saved translations only (no engine to
  /// make more); false when this book has none in the chosen language.
  Future<bool> _showSavedTranslations({required bool quiet}) async {
    final target = languageForCode(await MyLibraryDb.instance
        .getPreference(translationTargetLanguagePref)
        .catchError((_) => null) as String?);
    final cache = await TranslationEngines.openCache(
      bookFileName: widget.fileName,
      targetLanguage: target.code,
    );
    if (cache.length == 0 || !mounted) return false;
    _targetCode = target.code;
    _cache = cache;
    setState(() => _translateOn = true);
    for (final s in _sent.values) {
      s.clear();
    }
    await _js("window.reader.clearTranslations();"
        "window.reader.showTranslations(true, '${target.code}')");
    unawaited(_pushSettings());
    _pushTranslations();
    await MyLibraryDb.instance
        .savePreference(_translatePref, 1)
        .catchError((_) {});
    if (!quiet && mounted) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(_messageWithAction(
          l10n.translationSavedOnly,
          l10n.translationOpenSettings,
          _openTranslationSettings));
    }
    return true;
  }

  /// Sync brought translations (from another device): the page gets the
  /// ones it has not shown.
  void _onSyncArrived() {
    if (mounted && _translateOn) _pushTranslations();
  }

  /// The reader set a name right in this book and its paragraphs are to
  /// be made again: the page starts over - what still stands is sent
  /// again, the rest shows as written until it is translated, what is on
  /// screen first. (The page is sent each paragraph once: without this
  /// the old words stayed, and the new ones never showed.)
  void _onRedoMarked() {
    if (!mounted || !_translateOn || redoMarks.bookFile != widget.fileName) {
      return;
    }
    for (final s in _sent.values) {
      s.clear();
    }
    unawaited(() async {
      await _js("window.reader.clearTranslations();"
          "window.reader.showTranslations(true, '$_targetCode')");
      _pushTranslations();
      await _js('window.reader.reportVisible()');
    }());
  }

  void _onTranslationChanged() {
    if (!mounted) return;
    setState(() {});
    _pushTranslations();
  }

  /// Sends the page every translation it does not have yet, once per
  /// microtask however many arrived.
  void _pushTranslations() {
    if (_pushScheduled) return;
    _pushScheduled = true;
    scheduleMicrotask(() async {
      _pushScheduled = false;
      final cache = _cache;
      if (cache == null || !_translateOn) return;
      final entries = <Map<String, Object>>[];
      for (final MapEntry(key: section, value: texts) in _sections.entries) {
        final sent = _sent.putIfAbsent(section, () => {});
        for (var n = 0; n < texts.length; n++) {
          if (sent.contains(n)) continue;
          final out = cache.lookup(texts[n]);
          if (out == null) continue;
          entries.add({'section': section, 'n': n, 'text': out});
          sent.add(n);
        }
      }
      if (entries.isEmpty) return;
      await _js('window.reader.setTranslations('
          '${jsonEncode(entries)}, ${jsonEncode(_targetCode)})');
    });
  }

  /// The translator the glossary is made with (the reader's).
  Translator? _glossaryTranslator;

  void _onGlossaryChanged() {
    final glossary = GlossaryService.instance.cached(widget.fileName);
    if (glossary != null) _translation?.glossary = glossary;
    if (mounted) setState(() {});
  }

  Future<void> _openGlossary() => showGlossarySheet(
        context,
        bookFile: widget.fileName,
        onRemake: _glossaryTranslator == null
            ? null
            : () => GlossaryService.instance.make(
                bookFile: widget.fileName,
                bookPath: widget.filePath,
                translator: _glossaryTranslator!),
      );

  Future<void> _openTranslationSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => kIsWeb
              // The web has Gemini only: no models to manage.
              ? const WebSettingsPage()
              : const TranslationSettingsPage()),
    );
    // A new model or language applies from the next start.
    _studyLanguage = null;
    _assistantCache = null;
    final old = _translation;
    if (old != null && mounted) {
      final wasOn = _translateOn;
      old.removeListener(_onTranslationChanged);
      setState(() {
        _translation = null;
        _translateOn = false;
      });
      old.dispose();
      await _js('window.reader.clearTranslations()');
      if (wasOn) await _setTranslation(true, quiet: true);
    } else if (_translateOn && mounted) {
      // Saved translations only so far: an engine may be set up now.
      await _setTranslation(true, quiet: true);
    }
  }

  // ------------------------------------------------------------------
  // Study
  // ------------------------------------------------------------------

  bool get _japanese =>
      RegExp(r'^ja', caseSensitive: false).hasMatch(_language ?? '');

  String get _bookTitle =>
      _title?.isNotEmpty == true ? _title! : widget.fileName;

  String get _analysisKey => 'a\u0001${widget.fileName}';

  void _onStudyChanged() {
    if (!mounted) return;
    setState(() {});
    unawaited(_pushStudy());
    // Side by side or in place changes the shown script (fonts).
    _onSettingsChanged();
  }

  /// Sends the study settings to the page, loading the word tools there
  /// when they are wanted and downloaded.
  Future<void> _pushStudy() async {
    if (!_opened) return;
    final s = _study;
    final json = jsonEncode({
      'layout': s.layout.name,
      'furigana': s.furigana.name,
      'level': s.level,
      'wordTap': s.wordTap,
    });
    if (json != _lastStudyJson) {
      _lastStudyJson = json;
      await _js('window.reader.setStudy($json)');
    }
    if (s.needsTools && _japanese) await _loadTools();
  }

  /// Loads the word tools in the page; false when they are not
  /// downloaded.
  Future<bool> _loadTools() async {
    if (_toolsLoaded) return true;
    if (!await JapaneseTools.instance.installed()) return false;
    if (!_toolsLoading) {
      _toolsLoading = true;
      await _js('window.reader.loadStudyTools()');
    }
    return false;
  }

  Future<TranslationLanguage> _studyTarget() async =>
      _studyLanguage ??= languageForCode(await MyLibraryDb.instance
          .getPreference(translationTargetLanguagePref)
          .catchError((_) => null) as String?);

  /// The engine study questions go to: the reader's translator when it
  /// runs, else one of its own (made on the first question).
  Future<Translator?> _studyEngine() async {
    final reader = _glossaryTranslator;
    if (reader != null && _translation != null) return reader;
    if (_studyTranslator != null) return _studyTranslator;
    return _studyTranslatorFuture ??= () async {
      if (await TranslationEngines.cacheModelId() == null) return null;
      final t = await TranslationEngines.forReader();
      if (!mounted) {
        await t?.dispose();
        return null;
      }
      return _studyTranslator = t;
    }()
        .whenComplete(() => _studyTranslatorFuture = null);
  }

  Future<StudyAssistant?> _assistant() async {
    if (await TranslationEngines.cacheModelId() == null) return null;
    final target = await _studyTarget();
    return _assistantCache ??= StudyAssistant(
      translator: _studyEngine,
      targetLanguage: target.englishName,
      targetCode: target.code,
    );
  }

  Future<void> _openWord(Map<String, dynamic> msg) async {
    final query = WordQuery(
      base: '${msg['base'] ?? msg['surface'] ?? ''}',
      surface: '${msg['surface'] ?? ''}',
      reading: '${msg['reading'] ?? ''}',
      sentence: '${msg['sentence'] ?? ''}',
      pos: '${msg['pos'] ?? ''}',
      level: (msg['level'] as num?)?.toInt() ?? 0,
    );
    if (query.base.isEmpty) return;
    final assistant = await _assistant();
    final target = await _studyTarget();
    if (!mounted) return;
    await showWordSheet(context,
        query: query,
        assistant: assistant,
        book: _bookTitle,
        targetCode: target.code,
        onExplain: _explain);
    await _js('window.reader.clearHighlight()');
  }

  Future<void> _explain(String sentence) async {
    final assistant = await _assistant();
    if (!mounted) return;
    await showExplanationSheet(context,
        sentence: sentence,
        assistant: assistant,
        book: _bookTitle,
        level: _study.level);
  }

  /// The selection bar's actions.
  Future<void> _lookUpSelection() async {
    final sel = _selection;
    if (sel == null) return;
    setState(() => _selection = null);
    await _js('window.reader.clearSelection()');
    final text = '${sel['text']}';
    final base = '${sel['base'] ?? text}';
    await _openWord({
      'base': base,
      'surface': text,
      'reading': sel['reading'] ??
          (RegExp(r'^[\u3040-\u30FFー]+$').hasMatch(base)
              ? StudyData.hiragana(base)
              : ''),
      'sentence': sel['sentence'] ?? '',
      'pos': sel['pos'] ?? '',
      'level': sel['level'] ?? StudyData.instance.levelOf(base),
    });
  }

  Future<void> _explainSelection() async {
    final sel = _selection;
    if (sel == null) return;
    setState(() => _selection = null);
    await _js('window.reader.clearSelection()');
    final text = '${sel['text']}';
    final sentence = '${sel['sentence'] ?? ''}';
    // A long selection is the thing to explain; a word, its sentence.
    await _explain(text.length > 12 || sentence.isEmpty ? text : sentence);
  }

  Future<void> _openStudySheet() => showStudySettingsSheet(
        context,
        japanese: _japanese,
        translating: _translateOn,
        onDifficulty: _openDifficulty,
        onWordBook: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const StudyPage())),
      );

  Future<void> _openDifficulty() async {
    final l10n = AppLocalizations.of(context);
    final known = StudyStore.instance.answer(_analysisKey);
    Future<BookDifficulty?> result;
    if (known is Map) {
      result = Future.value(
          BookDifficulty.fromJson(Map<String, dynamic>.from(known)));
    } else {
      if (!await JapaneseTools.instance.installed()) {
        if (mounted) {
          showSnackBar(context: context, message: l10n.studyToolsWhy);
          await _openStudySheet();
        }
        return;
      }
      if (!_toolsLoaded) {
        await _loadTools();
        for (var i = 0; i < 100 && !_toolsLoaded && _toolsLoading; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        if (!_toolsLoaded) {
          if (mounted) {
            showSnackBar(context: context, message: l10n.studyAnalysisFailed);
          }
          return;
        }
      }
      final job = _analysis ??= Completer<BookDifficulty?>();
      _analysisProgress.value = 0;
      unawaited(_js('window.reader.analyze()'));
      result = job.future;
    }
    if (!mounted) return;
    final glossary = GlossaryService.instance.cached(widget.fileName) ??
        await GlossaryService.instance.load(widget.fileName);
    if (!mounted) return;
    await showDifficultySheet(
      context,
      progress: _analysisProgress,
      result: result,
      book: _bookTitle,
      names: {for (final e in glossary.entries) e.source},
      onAdded: (words) => unawaited(_fillMeanings(words)),
    );
  }

  /// Looks up words added without a meaning (from the difficulty list),
  /// one at a time.
  Future<void> _fillMeanings(List<BookWord> words) async {
    final assistant = await _assistant();
    if (assistant == null) return;
    for (final w in words) {
      if (!mounted) return;
      final m = await assistant
          .meaning(
              WordQuery(base: w.base, reading: w.reading, sentence: w.sentence))
          .catchError((_) => null);
      if (m != null && StudyStore.instance.has(w.base, w.reading)) {
        await StudyStore.instance
            .add(word: w.base, reading: w.reading, meaning: m.meaning);
      }
    }
  }

  /// Characters read in the original (a Japanese book, not shown
  /// translated in place), once per paragraph a session.
  void _countRead(int section, int first, int last) {
    if (!_japanese || first < 0) return;
    if (_translateOn && _study.layout == TranslationLayout.replace) return;
    final texts = _sections[section];
    if (texts == null) return;
    final seen = _readParagraphs.putIfAbsent(section, () => {});
    for (var n = first; n <= last && n < texts.length; n++) {
      if (seen.add(n)) _unsavedChars += texts[n].length;
    }
  }

  Widget _selectionBar(ReaderPalette palette) {
    final l10n = AppLocalizations.of(context);
    final sel = _selection;
    if (sel == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('studySelectionBar'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: palette.dark ? scheme.surfaceContainerHigh : scheme.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
              blurRadius: 12, color: Color(0x33000000), offset: Offset(0, 3))
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton.icon(
            key: const ValueKey('studySelectionMeaning'),
            onPressed: _lookUpSelection,
            icon: const Icon(Icons.search, size: 18),
            label: Text(l10n.studyMeaning),
          ),
          TextButton.icon(
            key: const ValueKey('studySelectionExplain'),
            onPressed: _explainSelection,
            icon: const Icon(Icons.menu_book_outlined, size: 18),
            label: Text(l10n.studyExplain),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            icon: const Icon(Icons.close, size: 18),
            onPressed: () {
              setState(() => _selection = null);
              unawaited(_js('window.reader.clearSelection()'));
            },
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // Reading aloud
  // ------------------------------------------------------------------

  String get _speechLanguage {
    final code = (_translateOn ? _targetCode : _language) ?? 'en';
    if (code.startsWith('ko')) return 'ko-KR';
    if (code.startsWith('ja')) return 'ja-JP';
    if (code.startsWith('zh')) return 'zh-CN';
    return code.contains('-') ? code : 'en-US';
  }

  Future<List<String>> _textsFromHere() async {
    final result =
        await _host?.evaluate('JSON.stringify(window.reader.textFromHere())');
    if (result is! String) return const [];
    final data = jsonDecode(result) as Map<String, dynamic>;
    final texts = [for (final t in (data['texts'] as List? ?? [])) '$t'];
    final cache = _cache;
    return [
      for (final t in texts)
        ...splitIntoSpeechChunks(
            _translateOn && cache != null ? (cache.lookup(t) ?? t) : t),
    ];
  }

  Future<void> _startTts() async {
    final tts = _tts;
    if (tts == null) return;
    _speech = await _textsFromHere();
    _speechIndex = 0;
    if (!mounted) return;
    if (_speech.isEmpty) {
      showSnackBar(
          context: context,
          message: AppLocalizations.of(context).nothingToRead);
      return;
    }
    if (!await tts.ensureEngineReady(_speechLanguage)) {
      if (mounted) {
        showSnackBar(
            context: context,
            message: AppLocalizations.of(context).ttsEngineMissing);
      }
      return;
    }
    await tts.speak(_speech.first);
  }

  void _speakNext() {
    final tts = _tts;
    if (tts == null || tts.state != TtsState.idle) return;
    _speechIndex++;
    if (_speechIndex < _speech.length) {
      unawaited(tts.speak(_speech[_speechIndex]));
      return;
    }
    // The section is done: on to the next, reading resumes when it shows.
    _speechWaitsForSection = true;
    unawaited(_js('window.reader.nextSection()'));
  }

  Future<void> _continueSpeechInSection() async {
    _speechWaitsForSection = false;
    _speech = await _textsFromHere();
    _speechIndex = 0;
    if (_speech.isNotEmpty) await _tts?.speak(_speech.first);
  }

  Future<void> _toggleTts() async {
    final tts = _tts;
    if (tts == null) return;
    switch (_ttsState) {
      case TtsState.idle:
        await _startTts();
      case TtsState.playing:
        await tts.pause();
      case TtsState.paused:
        await tts.resume();
    }
  }

  // ------------------------------------------------------------------
  // UI
  // ------------------------------------------------------------------

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      unawaited(_js('window.reader.goLeft()'));
    } else if (key == LogicalKeyboardKey.arrowRight) {
      unawaited(_js('window.reader.goRight()'));
    } else if (key == LogicalKeyboardKey.pageDown ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.arrowDown) {
      unawaited(_js('window.reader.next()'));
    } else if (key == LogicalKeyboardKey.pageUp ||
        key == LogicalKeyboardKey.arrowUp) {
      unawaited(_js('window.reader.prev()'));
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// Built once: the page's state changes (position, translation status)
  /// rebuild the bars around it, never the web view.
  late final Widget _webViewWidget = RepaintBoundary(child: _webView());

  Widget _webView() => readerHostView(
        resources: _resources,
        onCreated: (host) => _host = host,
        onMessage: _onMessage,
        onPageError: (message) => _logger.warning(message, tag: 'ReaderPage'),
        onLoadError: (description) {
          if (mounted) setState(() => _error = description);
        },
      );

  Widget _status(ReaderPalette palette) {
    final controller = _translation;
    if (!_translateOn || controller == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final status = controller.status;
    final busy = status == ReaderTranslationStatus.loadingModel ||
        status == ReaderTranslationStatus.translating;
    final String label;
    switch (status) {
      case ReaderTranslationStatus.loadingModel:
        label = l10n.translationLoadingModel;
      case ReaderTranslationStatus.translating:
        label = l10n.translationTranslating(
            controller.pendingCount, controller.deviceLabel ?? '');
      case ReaderTranslationStatus.paused:
        label = l10n.translationPaused;
      case ReaderTranslationStatus.error:
        label = l10n.translationFailed;
      case ReaderTranslationStatus.idle:
        label = controller.failedCount > 0
            ? l10n.translationSomeFailed(controller.failedCount)
            : controller.deviceLabel == null
                ? l10n.translationReadyPlain
                : l10n.translationReady(controller.deviceLabel!);
    }
    final canRetry = status == ReaderTranslationStatus.error ||
        (status == ReaderTranslationStatus.idle && controller.failedCount > 0);
    // Quiet once everything near the reader is done and the bars are
    // hidden.
    if (!_chrome && status == ReaderTranslationStatus.idle && !canRetry) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: palette.text.withAlpha(18),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The web: nothing keeps moving over the book's page (every
          // frame of it is drawn on the thread the page works on).
          if (busy && !kIsWeb)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                  strokeWidth: 1.6, color: palette.secondaryText),
            )
          else
            Icon(Icons.translate, size: 14, color: palette.secondaryText),
          const SizedBox(width: 8),
          Flexible(
            child: Text(label,
                key: const ValueKey('translationStatus'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: palette.secondaryText)),
          ),
          if (canRetry) ...[
            const SizedBox(width: 6),
            GestureDetector(
              key: const ValueKey('translationRetry'),
              onTap: controller.retry,
              child: Text(l10n.retry,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: palette.accent)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _topBar(ReaderPalette palette, AppLocalizations l10n) {
    final iconColor = palette.text.withAlpha(215);
    return Material(
      color: palette.background.withAlpha(245),
      elevation: 0,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                icon: Icon(Icons.arrow_back, color: iconColor),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: Text(
                  _title?.isNotEmpty == true ? _title! : l10n.appTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: palette.text),
                ),
              ),
              IconButton(
                key: const ValueKey('translateToggle'),
                tooltip: _translateOn
                    ? l10n.translationShowOriginal
                    : l10n.translationTranslate,
                icon: _translationStarting
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: iconColor))
                    : Icon(_translateOn ? Icons.g_translate : Icons.translate,
                        color: _translateOn ? palette.accent : iconColor),
                onPressed:
                    _fixedLayout ? null : () => _setTranslation(!_translateOn),
              ),
              if (_translateOn)
                IconButton(
                  key: const ValueKey('glossaryButton'),
                  tooltip: l10n.glossaryTitle,
                  icon: GlossaryService.instance.isMaking(widget.fileName)
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: iconColor))
                      : Icon(Icons.badge_outlined, color: iconColor),
                  onPressed: _openGlossary,
                ),
              if (_tts != null)
                IconButton(
                  tooltip: _ttsState == TtsState.playing
                      ? l10n.pauseReadingAloud
                      : l10n.resumeReadingAloud,
                  icon: Icon(
                    _ttsState == TtsState.playing
                        ? Icons.pause_circle
                        : _ttsState == TtsState.paused
                            ? Icons.play_circle
                            : Icons.headphones_outlined,
                    color: iconColor,
                  ),
                  onPressed: _toggleTts,
                ),
              if (_ttsState != TtsState.idle)
                IconButton(
                  tooltip: l10n.stopReadingAloud,
                  icon: Icon(Icons.stop_circle, color: iconColor),
                  onPressed: () => _tts?.stop(),
                ),
              if (!_fixedLayout)
                IconButton(
                  key: const ValueKey('studyButton'),
                  tooltip: l10n.studyTitle,
                  icon: Icon(Icons.school_outlined, color: iconColor),
                  onPressed: _openStudySheet,
                ),
              IconButton(
                key: const ValueKey('readerContents'),
                tooltip: l10n.readerContents,
                icon: Icon(Icons.format_list_bulleted, color: iconColor),
                onPressed: _toc.isEmpty ? null : _openContents,
              ),
              IconButton(
                key: const ValueKey('readerSettingsButton'),
                tooltip: l10n.readerThemesSettings,
                icon: Text('Aa',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: iconColor)),
                onPressed: _openSettingsSheet,
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomBar(ReaderPalette palette) {
    final value = (_seeking ?? _fraction).clamp(0.0, 1.0);
    return Material(
      color: palette.background.withAlpha(245),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(_tocLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, color: palette.secondaryText)),
                  ),
                  Text('${(value * 100).round()}%',
                      style: TextStyle(
                          fontSize: 12,
                          color: palette.secondaryText,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                ],
              ),
              SliderTheme(
                // The page's colours, not the app's: a thumb in the app
                // theme's colour was white on a paper page, or black on
                // a night one.
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: palette.accent,
                  inactiveTrackColor: palette.text.withAlpha(40),
                  thumbColor: palette.accent,
                  overlayColor: palette.accent.withAlpha(40),
                  trackHeight: 3,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 7),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 14),
                ),
                child: Slider(
                  key: const ValueKey('readerProgress'),
                  value: value,
                  onChanged: (v) => setState(() => _seeking = v),
                  onChangeEnd: (v) {
                    setState(() => _seeking = null);
                    unawaited(_js('window.reader.goToFraction($v)'));
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The quiet line under the page while the bars are hidden.
  Widget _footer(ReaderPalette palette) => IgnorePointer(
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(_tocLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          color: palette.secondaryText.withAlpha(200))),
                ),
                Text('${(_fraction * 100).round()}%',
                    style: TextStyle(
                        fontSize: 11,
                        color: palette.secondaryText.withAlpha(200),
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ],
            ),
          ),
        ),
      );

  Future<void> _openContents() async {
    final href = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        final current = _toc.lastIndexWhere((t) =>
            _tocHref.isNotEmpty &&
            (t.href == _tocHref || t.href.split('#').first == _tocHref));
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          builder: (context, scroll) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(l10n.readerContents,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scroll,
                  itemCount: _toc.length,
                  itemBuilder: (context, i) {
                    final t = _toc[i];
                    final selected = i == current;
                    return ListTile(
                      key: ValueKey('toc-$i'),
                      contentPadding:
                          EdgeInsets.only(left: 20.0 + t.depth * 16, right: 16),
                      selected: selected,
                      title: Text(t.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w400,
                              fontSize: t.depth == 0 ? 15 : 14)),
                      onTap: () => Navigator.pop(context, t.href),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
    if (href != null) {
      setState(() => _chrome = false);
      await _js('window.reader.goTo(${jsonEncode(href)})');
    }
  }

  Widget _errorView(ReaderPalette palette, AppLocalizations l10n) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.menu_book_outlined,
                  size: 40, color: palette.secondaryText),
              const SizedBox(height: 12),
              Text(l10n.readerLoadFailed,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: palette.text, fontSize: 15)),
              const SizedBox(height: 6),
              Text(_error ?? '',
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.secondaryText, fontSize: 12)),
              if (widget.onFallback != null) ...[
                const SizedBox(height: 16),
                FilledButton.tonal(
                  key: const ValueKey('readerFallback'),
                  onPressed: widget.onFallback,
                  child: Text(l10n.readerOpenSimple),
                ),
              ],
            ],
          ),
        ),
      );

  /// [child] drawn over the book's page takes its own taps. On the web
  /// the page is an iframe, and the browser gives it every tap inside its
  /// box - the bars over it included - unless something of the page's
  /// own sits under them.
  /// [shown] false (a bar slid away) or nothing to show: no element is
  /// laid over the page for it - each one is another layer the browser
  /// composes with every frame.
  Widget _onPage(Widget child, {bool shown = true}) => PointerInterceptor(
      intercepting: kIsWeb &&
          shown &&
          !(child is SizedBox && child.width == 0 && child.height == 0),
      child: child);

  /// A message with a button. On the web the button sits in the message
  /// itself, which takes its taps (see [_onPage]).
  SnackBar _messageWithAction(
      String text, String label, VoidCallback onPressed) {
    if (!kIsWeb) {
      return SnackBar(
        content: Text(text),
        action: SnackBarAction(label: label, onPressed: onPressed),
      );
    }
    final theme = Theme.of(context);
    return SnackBar(
      content: _onPage(Row(
        children: [
          Expanded(child: Text(text)),
          TextButton(
            style: TextButton.styleFrom(
                foregroundColor: theme.snackBarTheme.actionTextColor ??
                    theme.colorScheme.inversePrimary),
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              onPressed();
            },
            child: Text(label),
          ),
        ],
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = _palette();
    final l10n = AppLocalizations.of(context);
    final overlay =
        palette.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark;
    if (kIsWeb) {
      // The browser tab says which book is open.
      return Title(
        title:
            _title?.isNotEmpty == true ? '${_title!} · LightLib' : 'LightLib',
        color: palette.background,
        child: _page(palette, l10n, overlay),
      );
    }
    return _page(palette, l10n, overlay);
  }

  Widget _page(ReaderPalette palette, AppLocalizations l10n,
      SystemUiOverlayStyle overlay) {
    // Unfolded or folded while reading: the page is laid out again for
    // the room there is now (two pages, or one).
    final width = MediaQuery.sizeOf(context).width;
    if (width != _layoutWidth) {
      final known = _layoutWidth != 0;
      _layoutWidth = width;
      if (known && !kIsWeb) {
        _settingsTimer?.cancel();
        _settingsTimer =
            Timer(const Duration(milliseconds: 160), _pushSettings);
      }
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: palette.background),
      child: Scaffold(
        backgroundColor: palette.background,
        body: Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Stack(
            children: [
              Positioned.fill(
                child: SafeArea(
                  child: _error != null
                      ? _errorView(palette, l10n)
                      : _hostAllowed
                          ? _webViewWidget
                          : const SizedBox.expand(),
                ),
              ),
              if (!_opened && _error == null && widget.opening == null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                      color: palette.background,
                      child: Center(
                        child: SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.4, color: palette.secondaryText),
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  offset: _chrome || _error != null
                      ? Offset.zero
                      : const Offset(0, -1.2),
                  child: _onPage(_topBar(palette, l10n),
                      shown: _chrome || _error != null),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.bottomCenter,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _onPage(_selectionBar(palette)),
                      _onPage(_status(palette)),
                      if (_error != null)
                        const SizedBox.shrink()
                      else if (_chrome)
                        _onPage(_bottomBar(palette))
                      else
                        _footer(palette),
                    ],
                  ),
                ),
              ),
              // Over everything until the first page is up; gone from the
              // tree afterwards (it would take the page's taps).
              if (widget.opening case final opening?)
                Positioned.fill(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    switchOutCurve: Curves.easeOut,
                    // A plain fade of one flat layer: the picture behind
                    // it is a picture (nothing is blurred as it goes),
                    // and nothing in it changes size.
                    child: _openingGone || _error != null
                        ? const SizedBox.shrink()
                        : RepaintBoundary(child: _onPage(opening(context))),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Frames of one part of a book's opening, counted for the log.
class _FrameCount {
  _FrameCount(this.name);

  final String name;
  int frames = 0;
  int late = 0;
  int worstWait = 0;
  int worstBuild = 0;
  int worstRaster = 0;
  int worstTotal = 0;

  void add(ui.FrameTiming t) {
    frames++;
    final total = t.totalSpan.inMilliseconds;
    // (Late: more than a frame of a 60 Hz screen and a little.)
    if (total > 20) late++;
    if (total > worstTotal) worstTotal = total;
    // (Waiting: from the screen's tick to the frame being begun - the
    // thread was busy with something else, the page's work for one.)
    final wait = t.vsyncOverhead.inMilliseconds;
    if (wait > worstWait) worstWait = wait;
    final build = t.buildDuration.inMilliseconds;
    if (build > worstBuild) worstBuild = build;
    final raster = t.rasterDuration.inMilliseconds;
    if (raster > worstRaster) worstRaster = raster;
  }

  String get summary => '$frames frames, $late over 20 ms '
      '(worst $worstTotal ms; waited $worstWait, build $worstBuild, '
      'raster $worstRaster)';
}
