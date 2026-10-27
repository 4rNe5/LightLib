// The EPUB reader: the book is laid out by foliate-js in a web view
// (assets/reader, built from reader_web/), which renders EPUBs the way
// dedicated readers do - the book's own CSS, vertical Japanese with ruby,
// SVG and full-page images, fixed-layout books - and this page adds the
// app around it: bars, contents, themes and type, on-device translation
// and reading aloud.

// Dart imports:
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/database.dart' show MyLibraryDb;
import 'package:openlib/services/epub_package.dart';
import 'package:openlib/services/logger.dart';
import 'package:openlib/services/reader_fonts.dart';
import 'package:openlib/services/reader_settings.dart';
import 'package:openlib/services/translation/glossary_service.dart';
import 'package:openlib/services/translation/reader_translation_controller.dart';
import 'package:openlib/services/translation/translation_cache.dart';
import 'package:openlib/services/translation/translation_model_store.dart';
import 'package:openlib/services/translation/translation_models.dart';
import 'package:openlib/services/translation/translation_engine.dart';
import 'package:openlib/services/translation/translator.dart';
import 'package:openlib/services/tts_service.dart';
import 'package:openlib/state/state.dart' show saveEpubState;
import 'package:openlib/ui/components/paged_book_view.dart' show ReaderLayout;
import 'package:openlib/ui/components/glossary_sheet.dart';
import 'package:openlib/ui/components/reader_settings_sheet.dart';
import 'package:openlib/ui/components/snack_bar_widget.dart';
import 'package:openlib/ui/translation_settings_page.dart';

/// Whether this platform has the web view the book reader needs (Android
/// and Apple platforms); elsewhere the Flutter-drawn reader is used.
bool bookReaderSupported() =>
    Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

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

/// What the reader serves to the page, by path.
@immutable
class ReaderResource {
  const ReaderResource(this.contentType, this.bytes);
  final String contentType;
  final Uint8List bytes;
}

/// Serves the reader page, the book and font files to the web view from
/// one origin, so the page can fetch them (Android intercepts an https
/// origin, Apple platforms a custom scheme).
class ReaderResources {
  ReaderResources({required this.bookPath, AssetBundle? bundle})
      : _bundle = bundle ?? rootBundle;

  final String bookPath;
  final AssetBundle _bundle;
  final Map<String, File> _fonts = {};

  static const androidOrigin = 'https://appassets.androidplatform.net';
  static const appleScheme = 'lightlib';
  static const appleOrigin = '$appleScheme://reader';

  static String get origin =>
      Platform.isAndroid ? '$androidOrigin/reader' : appleOrigin;

  /// Makes [file] loadable at the returned URL.
  String addFont(File file) {
    final key = 'f${_fonts.length}${_extensionOf(file.path)}';
    _fonts[key] = file;
    return '$origin/fonts/$key';
  }

  static String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    return dot < 0 ? '' : path.substring(dot).toLowerCase();
  }

  static String _typeOf(String path) {
    switch (_extensionOf(path)) {
      case '.html':
        return 'text/html';
      case '.js':
        return 'text/javascript';
      case '.css':
        return 'text/css';
      case '.otf':
        return 'font/otf';
      case '.ttf':
        return 'font/ttf';
      case '.woff2':
        return 'font/woff2';
      default:
        return 'application/octet-stream';
    }
  }

  /// The resource at [uri], or null for anything else.
  Future<ReaderResource?> resolve(Uri uri) async {
    var path = uri.path;
    if (path.startsWith('/reader/')) path = path.substring('/reader'.length);
    if (path == '/' || path.isEmpty) path = '/index.html';
    try {
      if (path == '/book') {
        final bytes = await File(bookPath).readAsBytes();
        return ReaderResource('application/epub+zip', bytes);
      }
      if (path.startsWith('/fonts/')) {
        final file = _fonts[path.substring('/fonts/'.length)];
        if (file == null) return null;
        return ReaderResource(_typeOf(file.path), await file.readAsBytes());
      }
      if (path == '/index.html' || path == '/reader.js') {
        final data = await _bundle.load('assets/reader$path');
        return ReaderResource(_typeOf(path), data.buffer.asUint8List());
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}

class BookReaderPage extends ConsumerStatefulWidget {
  const BookReaderPage({
    super.key,
    required this.fileName,
    required this.filePath,
    this.onFallback,
  });

  final String fileName;
  final String filePath;

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
  InAppWebViewController? _web;
  bool _pageReady = false;
  bool _opened = false;
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
    SharedTranslationEngine.instance.enterReader();
    ReaderSettings.instance.addListener(_onSettingsChanged);
    ReaderFonts.instance.addListener(_onSettingsChanged);
    unawaited(ReaderSettings.instance.load());
    unawaited(ReaderFonts.instance.load());
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
        _saveNow();
      },
      onShow: () => _translation?.resume(),
    );
  }

  @override
  void dispose() {
    _saveNow();
    SharedTranslationEngine.instance.leaveReader();
    ReaderSettings.instance.removeListener(_onSettingsChanged);
    ReaderFonts.instance.removeListener(_onSettingsChanged);
    _lifecycle?.dispose();
    _saveTimer?.cancel();
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
      await _web?.evaluateJavascript(source: code);
    } catch (e) {
      _logger.warning('Reader script failed', tag: 'Reader', error: e);
    }
  }

  Future<void> _openBook() async {
    if (_opened || !_pageReady) return;
    _opened = true;
    final saved = await MyLibraryDb.instance
        .getBookState(widget.fileName)
        .catchError((_) => null);
    final options = {
      'url': '${ReaderResources.origin}/book',
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
      case 'relocate':
        final cfi = msg['cfi'] as String?;
        setState(() {
          if (cfi != null && cfi.isNotEmpty) _cfi = cfi;
          _fraction = (msg['fraction'] as num?)?.toDouble() ?? _fraction;
          _tocLabel = msg['tocLabel'] as String? ?? '';
          _tocHref = msg['tocHref'] as String? ?? '';
          _section = (msg['section'] as num?)?.toInt() ?? _section;
        });
        _saveSoon();
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

  void _saveNow() {
    _saveTimer?.cancel();
    final cfi = _cfi;
    if (cfi == null || cfi.isEmpty) return;
    unawaited(
        saveEpubState(widget.fileName, '$bookReaderPositionPrefix$cfi', ref)
            .catchError((_) {}));
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

  FontScript get _displayScript => _translateOn && _targetCode != null
      ? ReaderFonts.scriptForLanguage(_targetCode)
      : ReaderFonts.scriptForLanguage(_language);

  Future<Map<String, Object?>> _jsSettings() async {
    final s = _settings;
    final palette = _palette();
    final scheme = Theme.of(context).colorScheme;
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
      'link':
          _css(palette.dark ? scheme.primary.withAlpha(230) : scheme.primary),
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
    };
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
        if (!quiet) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(l10n.translationNoModel),
            action: SnackBarAction(
              label: l10n.translationOpenSettings,
              onPressed: _openTranslationSettings,
            ),
          ));
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
      unawaited(Isolate.run(() async {
        final book = EpubPackage.open(await File(path).readAsBytes());
        return book == null ? <String, String>{} : epubRubyReadings(book);
      }).then((r) => controller.readings = r, onError: (_) {}));
      // The book's names and terms: loaded, or made once by the model
      // while the first pages are translated ([_onGlossaryChanged]).
      GlossaryService.instance.removeListener(_onGlossaryChanged);
      GlossaryService.instance.addListener(_onGlossaryChanged);
      unawaited(GlossaryService.instance
          .load(widget.fileName)
          .then((_) => _onGlossaryChanged()));
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
      MaterialPageRoute(builder: (_) => const TranslationSettingsPage()),
    );
    // A new model or language applies from the next start.
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
    }
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
    final result = await _web?.evaluateJavascript(
        source: 'JSON.stringify(window.reader.textFromHere())');
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

  Widget _webView() {
    final settings = InAppWebViewSettings(
      javaScriptEnabled: true,
      transparentBackground: true,
      supportZoom: false,
      builtInZoomControls: false,
      displayZoomControls: false,
      disableHorizontalScroll: false,
      verticalScrollBarEnabled: false,
      horizontalScrollBarEnabled: false,
      overScrollMode: OverScrollMode.NEVER,
      useShouldInterceptRequest: true,
      resourceCustomSchemes: const [ReaderResources.appleScheme],
      allowFileAccess: false,
      allowContentAccess: false,
      mediaPlaybackRequiresUserGesture: true,
      isInspectable: false,
      useHybridComposition: true,
    );
    return InAppWebView(
      key: const ValueKey('bookReaderWebView'),
      initialUrlRequest:
          URLRequest(url: WebUri('${ReaderResources.origin}/index.html')),
      initialSettings: settings,
      onWebViewCreated: (controller) {
        _web = controller;
        controller.addJavaScriptHandler(
          handlerName: 'reader',
          callback: (args) {
            final msg = args.isEmpty ? null : args.first;
            if (msg is Map) _onMessage(Map<String, dynamic>.from(msg));
            return null;
          },
        );
      },
      shouldInterceptRequest: (controller, request) async {
        final uri = request.url;
        if (uri.host != Uri.parse(ReaderResources.androidOrigin).host) {
          return null;
        }
        final res = await _resources.resolve(uri);
        if (res == null) {
          return WebResourceResponse(
              statusCode: 404, reasonPhrase: 'Not Found', data: Uint8List(0));
        }
        return WebResourceResponse(
          contentType: res.contentType,
          contentEncoding: 'utf-8',
          data: res.bytes,
          statusCode: 200,
          reasonPhrase: 'OK',
          headers: const {'Cache-Control': 'no-store'},
        );
      },
      onLoadResourceWithCustomScheme: (controller, request) async {
        final res = await _resources.resolve(request.url);
        if (res == null) return null;
        return CustomSchemeResponse(
            data: res.bytes, contentType: res.contentType);
      },
      onConsoleMessage: (controller, message) {
        if (message.messageLevel == ConsoleMessageLevel.ERROR) {
          _logger.warning(message.message, tag: 'ReaderPage');
        }
      },
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame == true && mounted) {
          setState(() => _error = error.description);
        }
      },
    );
  }

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
          if (busy)
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
                      color: Theme.of(context).colorScheme.primary)),
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
                        color: _translateOn
                            ? Theme.of(context).colorScheme.primary
                            : iconColor),
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
                data: SliderTheme.of(context).copyWith(
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

  @override
  Widget build(BuildContext context) {
    final palette = _palette();
    final l10n = AppLocalizations.of(context);
    final overlay =
        palette.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark;
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
                      : _webViewWidget,
                ),
              ),
              if (!_opened && _error == null)
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
                  child: _topBar(palette, l10n),
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
                      _status(palette),
                      if (_error != null)
                        const SizedBox.shrink()
                      else if (_chrome)
                        _bottomBar(palette)
                      else
                        _footer(palette),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
