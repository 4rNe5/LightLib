// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:openlib/l10n/app_localizations.dart';

// Package imports:
import 'package:epub_view/epub_view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_file/open_file.dart';

// Project imports:
import 'package:openlib/services/files.dart' show getFilePath;
import 'package:openlib/services/translation/reader_translation_controller.dart';
import 'package:openlib/services/translation/translation_cache.dart';
import 'package:openlib/services/translation/translation_model_store.dart';
import 'package:openlib/services/translation/translation_models.dart';
import 'package:openlib/services/translation/translator.dart';
import 'package:openlib/services/tts_service.dart';
import 'package:openlib/ui/components/translated_chapter_builder.dart';
import 'package:openlib/ui/components/paged_book_view.dart';
import 'package:openlib/ui/reader_font_settings_page.dart';
import 'package:openlib/services/reader_fonts.dart';
// ignore: implementation_imports
import 'package:epub_view/src/data/epub_parser.dart'
    show parseChapters, parseParagraphs;
// ignore: implementation_imports
import 'package:epub_view/src/data/models/paragraph.dart';
import 'dart:async';
import 'package:openlib/ui/translation_settings_page.dart';
import 'package:openlib/ui/components/snack_bar_widget.dart';
import 'package:openlib/state/state.dart'
    show
        filePathProvider,
        saveEpubState,
        getBookPosition,
        openEpubWithExternalAppProvider;
import 'package:openlib/services/database.dart' show MyLibraryDb;
import 'package:openlib/services/platform_utils.dart';
import 'package:openlib/ui/components/reader_help_overlay.dart';

Future<void> launchEpubViewer({
  required String fileName,
  required BuildContext context,
  required WidgetRef ref,
}) async {
  try {
    String path = await getFilePath(fileName);
    bool openWithExternalApp = ref.watch(openEpubWithExternalAppProvider);

    // Check if user wants external app
    if (openWithExternalApp) {
      await OpenFile.open(path,
          linuxByProcess: true, type: "application/epub+zip");
    } else {
      try {
        // Use internal Epub Viewer for all platforms (epub_view supports desktop)
        if (context.mounted) {
          Navigator.push(context,
              MaterialPageRoute(builder: (BuildContext context) {
            return EpubViewerWidget(fileName: fileName);
          }));
        }
      } catch (e) {
        if (context.mounted) {
          showSnackBar(context: context, message: "Unable to open epub!");
        }
      }
    }
  } catch (e) {
    // File doesn't exist or can't be accessed
    if (context.mounted) {
      showSnackBar(
          context: context,
          message: "File not found. The download may have failed.");
    }
  }
}

class EpubViewerWidget extends ConsumerStatefulWidget {
  const EpubViewerWidget({super.key, required this.fileName});

  final String fileName;

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _EpubViewState();
}

class _EpubViewState extends ConsumerState<EpubViewerWidget> {
  @override
  Widget build(BuildContext context) {
    final filePath = ref.watch(filePathProvider(widget.fileName));
    return filePath.when(
      data: (data) {
        return EpubViewer(filePath: data, fileName: widget.fileName);
      },
      error: (error, stack) {
        return Scaffold(
          appBar: AppBar(
            backgroundColor: Theme.of(context).colorScheme.primary,
            title: Text(AppLocalizations.of(context).appTitle),
            titleTextStyle: Theme.of(context).textTheme.displayLarge,
          ),
          body: Center(child: Text(error.toString())),
        );
      },
      loading: () {
        return Scaffold(
          appBar: AppBar(
            backgroundColor: Theme.of(context).colorScheme.primary,
            title: Text(AppLocalizations.of(context).appTitle),
            titleTextStyle: Theme.of(context).textTheme.displayLarge,
          ),
          body: Center(
            child: SizedBox(
              width: 25,
              height: 25,
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
          ),
        );
      },
    );
  }
}

class EpubViewer extends ConsumerStatefulWidget {
  const EpubViewer({super.key, required this.filePath, required this.fileName});

  final String filePath;
  final String fileName;

  @override
  ConsumerState<EpubViewer> createState() => _EpubViewerState();
}

class _EpubViewerState extends ConsumerState<EpubViewer> {
  late EpubController _epubReaderController;
  bool _showTutorial = false;
  final FocusNode _focusNode = FocusNode();

  static const _defaultFontSize = 16.0;
  static const _minFontSize = 10.0;
  static const _maxFontSize = 32.0;
  static const _fontSizeStep = 2.0;
  double _fontSize = _defaultFontSize;

  // Text-to-speech (mobile only): speaks the current chapter chunk by
  // chunk and follows the reader along.
  TtsService? _tts;
  TtsState _ttsState = TtsState.idle;
  List<String> _speechChunks = const [];
  int _speechChunkIndex = 0;

  // On-device translation: the reader shows translated paragraphs in
  // place of the originals while this is on.
  ReaderTranslationController? _translation;
  bool _translateOn = false;
  bool _translationStarting = false;
  String? _bookLanguage;
  final ParagraphTextMemo _paragraphTexts = ParagraphTextMemo();
  AppLifecycleListener? _lifecycle;
  String? _targetCode;

  // Reading layout: one long column, or pages turned like an e-reader.
  ReaderLayout _layout = ReaderLayout.scroll;
  EpubBook? _pagedBook;
  List<Paragraph>? _pagedParagraphs;
  int _pagedParagraph = 0;
  int _pagedRevision = 0;
  Timer? _pagedRevisionTimer;
  int? _pendingScrollIndex;
  final GlobalKey<PagedBookViewState> _pagedKey = GlobalKey();

  String get _pagedPosPref => 'pagedPos:${widget.fileName}';

  @override
  void initState() {
    super.initState();
    // Initialize with standard options
    _epubReaderController = EpubController(
      document: EpubDocument.openFile(File(widget.filePath)),
      // NOTE: We'll set CFI later in onDocumentLoaded because we need to fetch it async
    );

    _loadFontSize();
    _loadLayout();
    ReaderFonts.instance.addListener(_onFontsChanged);
    ReaderFonts.instance.load();

    if (ttsAvailableOnPlatform()) {
      _tts = TtsService();
      _tts!.onStateChanged.listen((s) {
        if (mounted) setState(() => _ttsState = s);
      });
      _tts!.onChunkComplete(_speakNextChunk);
    }

    // Translation stops queueing work in the background: the OS would
    // suspend it anyway, and nobody is reading.
    _lifecycle = AppLifecycleListener(
      onHide: () => _translation?.pause(),
      onShow: () => _translation?.resume(),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkTutorial();
      _focusNode.requestFocus();
      _restoreTranslation();
    });
  }

  // ------------------------------------------------------------------
  // Layout (scroll / pages)
  // ------------------------------------------------------------------

  static const _layoutPref = 'readerLayout';

  void _onFontsChanged() {
    if (!mounted) return;
    setState(() => _pagedRevision++);
  }

  Future<void> _loadLayout() async {
    final saved = await MyLibraryDb.instance
        .getPreference(_layoutPref)
        .catchError((_) => null);
    final layout = ReaderLayout.fromName(saved as String?);
    if (layout.paged) {
      final pos = await MyLibraryDb.instance
          .getPreference(_pagedPosPref)
          .catchError((_) => null);
      _pagedParagraph = int.tryParse('$pos') ?? 0;
      await _ensurePagedBook();
    }
    if (mounted) setState(() => _layout = layout);
  }

  /// Loads the book and its paragraphs for the page view (split exactly
  /// as the scroll view splits them, so positions carry over).
  Future<void> _ensurePagedBook() async {
    if (_pagedBook != null) return;
    final book = await EpubDocument.openFile(File(widget.filePath));
    final paragraphs =
        parseParagraphs(parseChapters(book), book.Content).flatParagraphs;
    final languages = book.Schema?.Package?.Metadata?.Languages;
    _bookLanguage ??=
        (languages == null || languages.isEmpty) ? null : languages.first;
    _pagedBook = book;
    _pagedParagraphs = paragraphs;
  }

  Future<void> _setLayout(ReaderLayout layout) async {
    if (layout == _layout) return;
    if (layout.paged) {
      if (!_layout.paged) {
        _pagedParagraph =
            _epubReaderController.currentValue?.position.index ?? 0;
      }
      await _ensurePagedBook();
    } else if (_layout.paged) {
      // Back to scrolling: land on the paragraph the page started with.
      _pendingScrollIndex = _pagedParagraph;
    }
    if (!mounted) return;
    setState(() => _layout = layout);
    await MyLibraryDb.instance
        .savePreference(_layoutPref, layout.name)
        .catchError((_) {});
  }

  void _onPagedParagraph(int index) {
    _pagedParagraph = index;
    MyLibraryDb.instance
        .savePreference(_pagedPosPref, index)
        .catchError((_) {});
  }

  /// The font script of what the reader shows: the translation's language
  /// while translating, the book's language otherwise.
  FontScript get _displayScript => _translateOn && _targetCode != null
      ? ReaderFonts.scriptForLanguage(_targetCode)
      : ReaderFonts.scriptForLanguage(_bookLanguage);

  TextStyle _baseTextStyle(bool isDarkMode) => TextStyle(
        height: 1.6,
        fontSize: _fontSize,
        color: isDarkMode ? const Color(0xfff5f5f5) : Colors.black,
      );

  Widget _buildPaged(BuildContext context, bool isDarkMode) {
    final book = _pagedBook;
    final paragraphs = _pagedParagraphs;
    if (book == null || paragraphs == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final base = _baseTextStyle(isDarkMode);
    final hanAs =
        ReaderFonts.scriptForLanguage(_bookLanguage) == FontScript.korean
            ? FontScript.korean
            : FontScript.japanese;
    final translation = _translateOn ? _translation : null;
    return PagedBookView(
      key: _pagedKey,
      book: book,
      paragraphs: paragraphs,
      layout: _layout,
      textStyle: base,
      revision: _pagedRevision,
      styleFor: (text, heading) => ReaderFonts.instance.styleFor(
          text,
          heading
              ? base.copyWith(
                  fontSize: _fontSize * 1.3, fontWeight: FontWeight.bold)
              : base,
          hanAs: hanAs),
      initialParagraph: _pagedParagraph,
      onParagraphChanged: _onPagedParagraph,
      translationOf: (i) {
        if (translation == null) return null;
        final text = _paragraphTexts.textAt(paragraphs, i);
        return text == null ? null : translation.translationOf(text);
      },
      onPageShown: (first, last) {
        translation?.ensureAhead(first,
            textAt: (i) => _paragraphTexts.textAt(paragraphs, i),
            itemCount: paragraphs.length);
      },
    );
  }

  // ------------------------------------------------------------------
  // Translation
  // ------------------------------------------------------------------

  static const _translatePref = 'readerTranslate';

  /// Turns translation back on when the reader left it on last time and a
  /// model is still installed.
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
      await MyLibraryDb.instance
          .savePreference(_translatePref, 0)
          .catchError((_) {});
      return;
    }

    final l10n = AppLocalizations.of(context);
    if (_translation != null) {
      _translation!.resume();
      setState(() => _translateOn = true);
      await MyLibraryDb.instance
          .savePreference(_translatePref, 1)
          .catchError((_) {});
      return;
    }

    setState(() => _translationStarting = true);
    try {
      final model = await TranslationModelStore.instance.activeModel();
      if (!mounted) return;
      if (model == null) {
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
      final cache = await TranslationCache.open(
        bookFileName: widget.fileName,
        targetLanguage: target.code,
        modelId: model.fileName,
      );
      // The shared engine: the background book translator uses the same
      // loaded model, and the page on screen jumps its queue.
      final shared = await SharedTranslationEngine.instance.acquire();
      if (!mounted || shared == null) {
        if (shared != null) SharedTranslationEngine.instance.release();
        await cache.flush();
        return;
      }
      _targetCode = target.code;
      final controller = ReaderTranslationController(
        translator: UrgentTranslator(shared),
        cache: cache,
        targetLanguage: target.englishName,
        sourceLanguage: sourceLanguageName(_bookLanguage),
      );
      controller.addListener(_onTranslationChanged);
      setState(() {
        _translation = controller;
        _translateOn = true;
      });
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
    // Pages are laid out again for new translations, at most every
    // couple of seconds so the page under the finger does not jump.
    if (_layout.paged && _pagedRevisionTimer == null) {
      _pagedRevisionTimer = Timer(const Duration(seconds: 2), () {
        _pagedRevisionTimer = null;
        if (mounted) setState(() => _pagedRevision++);
      });
    }
  }

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
      if (wasOn) await _setTranslation(true, quiet: true);
    }
  }

  Widget _buildTranslationStatus(BuildContext context) {
    final controller = _translation;
    if (!_translateOn || controller == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
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
        label = l10n.translationReady(controller.deviceLabel ?? '');
    }
    return Material(
      color: scheme.surfaceContainerHighest.withAlpha(120),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Icon(Icons.translate, size: 14, color: scheme.tertiary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    key: const ValueKey('translationStatus'),
                    style: TextStyle(fontSize: 12, color: scheme.tertiary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (status == ReaderTranslationStatus.error)
                  TextButton(
                    onPressed: controller.retry,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(l10n.retry),
                  ),
              ],
            ),
          ),
          if (busy)
            LinearProgressIndicator(
              minHeight: 2,
              color: scheme.secondary,
              backgroundColor: Colors.transparent,
            ),
        ],
      ),
    );
  }

  Future<void> _loadFontSize() async {
    final saved = await MyLibraryDb.instance
        .getPreference('readerFontSize')
        .catchError((_) => null);
    if (saved != null && mounted) {
      final parsed = double.tryParse(saved.toString());
      if (parsed != null && parsed >= _minFontSize && parsed <= _maxFontSize) {
        setState(() => _fontSize = parsed);
      }
    }
  }

  Future<void> _changeFontSize(double delta) async {
    final next = (_fontSize + delta).clamp(_minFontSize, _maxFontSize);
    if (next == _fontSize) return;
    setState(() => _fontSize = next);
    // savePreference only accepts bool/int/String, so the double goes in
    // as text; _loadFontSize parses it back out. Writing here (not on
    // close) keeps tests free of lifecycle writes.
    await MyLibraryDb.instance
        .savePreference('readerFontSize', next.toString())
        .catchError((_) {});
  }

  // ------------------------------------------------------------------
  // Text-to-speech
  // ------------------------------------------------------------------

  /// Speaks the current chapter from wherever the reader is, then keeps
  /// going chunk by chunk until the chapter is done.
  Future<void> _startTts() async {
    final tts = _tts;
    if (tts == null) return;

    final chapter = _epubReaderController.currentValue?.chapter;
    final html = chapter?.HtmlContent ?? '';
    final text = htmlToSpeechText(html);
    if (text.isEmpty) {
      if (mounted) {
        showSnackBar(
            context: context,
            message: AppLocalizations.of(context).nothingToRead);
      }
      return;
    }

    _speechChunks = splitIntoSpeechChunks(text);
    _speechChunkIndex = 0;
    if (_speechChunks.isEmpty) return;

    // Some engines only register the short language code; the service
    // falls back to it and reports whether any engine answered at all.
    final engineReady = await tts.ensureEngineReady('en-US');
    if (!engineReady) {
      if (mounted) {
        showSnackBar(
            context: context,
            message: AppLocalizations.of(context).ttsEngineMissing);
      }
      return;
    }
    await tts.setRate(TtsService.defaultRate);
    await tts.speak(_speechChunks.first);
  }

  /// Advances to the next chunk, or the next chapter when this one ends.
  void _speakNextChunk() {
    final tts = _tts;
    if (tts == null || tts.state != TtsState.idle) return;

    _speechChunkIndex++;
    if (_speechChunkIndex < _speechChunks.length) {
      tts.speak(_speechChunks[_speechChunkIndex]);
      return;
    }

    // Chapter done: move to the next one; onChapterChanged picks up reading.
    _advanceToNextChapter();
  }

  /// Jumps to the next chapter. Reading continues from onChapterChanged,
  /// which fires once the view lands there.
  void _advanceToNextChapter() {
    final toc = _epubReaderController.tableOfContents();
    final current = _epubReaderController.currentValue;
    if (current == null) return;
    final currentIndex =
        toc.indexWhere((c) => c.title == current.chapter?.Title);
    if (currentIndex < 0 || currentIndex + 1 >= toc.length) {
      // End of book - nothing further to read.
      setState(() => _ttsState = TtsState.idle);
      return;
    }
    _epubReaderController.scrollTo(
      index: toc[currentIndex + 1].startIndex,
      duration: const Duration(milliseconds: 300),
    );
  }

  Future<void> _toggleTts() async {
    final tts = _tts;
    if (tts == null) return;
    switch (_ttsState) {
      case TtsState.idle:
        await _startTts();
        break;
      case TtsState.playing:
        await tts.pause();
        break;
      case TtsState.paused:
        await tts.resume();
        break;
    }
  }

  Future<void> _stopTts() async {
    await _tts?.stop();
  }

  /// Cycles the speech rate between slow / normal / fast.
  Future<void> _cycleTtsRate() async {
    final tts = _tts;
    if (tts == null) return;
    final current = tts.rate;
    final next = current < 0.35
        ? 0.5
        : current < 0.75
            ? 1.0
            : 0.25;
    await tts.setRate(next);
    // Restart the current chunk so the new rate applies immediately.
    if (_ttsState != TtsState.idle &&
        _speechChunkIndex < _speechChunks.length) {
      await tts.speak(_speechChunks[_speechChunkIndex]);
    }
    if (mounted) setState(() {});
  }

  String get _ttsRateLabel {
    final rate = _tts?.rate ?? TtsService.defaultRate;
    if (rate < 0.35) return '0.5x';
    if (rate < 0.75) return '1x';
    return '2x';
  }

  Future<void> _checkTutorial() async {
    try {
      final prefs = MyLibraryDb.instance;
      final hasSeen = await prefs
              .getPreference('hasSeenReaderTutorial')
              .catchError((_) => 0) ??
          0;

      if (hasSeen == 0) {
        if (mounted) setState(() => _showTutorial = true);
        await prefs.savePreference('hasSeenReaderTutorial', 1);
      }
    } catch (e) {
      debugPrint("Error checking tutorial: $e");
    }
  }

  @override
  void deactivate() {
    // Save EPUB state when leaving (the page view keeps its own position).
    if (!_layout.paged) {
      final cfi = _epubReaderController.generateEpubCfi();
      saveEpubState(widget.fileName, cfi, ref);
    }
    super.deactivate();
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    _pagedRevisionTimer?.cancel();
    ReaderFonts.instance.removeListener(_onFontsChanged);
    _translation?.removeListener(_onTranslationChanged);
    _translation?.dispose();
    _tts?.dispose();
    _focusNode.dispose();
    _epubReaderController.dispose();
    super.dispose();
  }

  EpubViewBuilders<DefaultBuilderOptions> _buildersFor(bool isDarkMode) {
    final options = DefaultBuilderOptions(
      textStyle: ReaderFonts.instance.styleForScript(
          _displayScript, _baseTextStyle(isDarkMode).copyWith(height: 1.4)),
    );
    final translation = _translation;
    if (_translateOn && translation != null) {
      return EpubViewBuilders<DefaultBuilderOptions>(
        options: options,
        chapterDividerBuilder: (_) => const Divider(),
        chapterBuilder: translatingChapterBuilder(
          controller: translation,
          memo: _paragraphTexts,
        ),
      );
    }
    return EpubViewBuilders<DefaultBuilderOptions>(
      options: options,
      chapterDividerBuilder: (_) => const Divider(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watch for saved position
    final positionAsync = ref.watch(getBookPosition(widget.fileName));
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        // Use surface color in dark mode so it's not white
        backgroundColor: isDarkMode
            ? Theme.of(context).colorScheme.surface
            : Theme.of(context).colorScheme.primary,
        title: Text(AppLocalizations.of(context).appTitle),
        titleTextStyle: Theme.of(context).textTheme.displayLarge,
        leading: IconButton(
          icon: Icon(Icons.arrow_back,
              color: Theme.of(context).colorScheme.tertiary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          PopupMenuButton<Object>(
            key: const ValueKey('readerViewMenu'),
            tooltip: AppLocalizations.of(context).readerViewOptions,
            icon: Icon(Icons.chrome_reader_mode_outlined,
                color: Theme.of(context).colorScheme.tertiary),
            onSelected: (value) {
              if (value is ReaderLayout) {
                _setLayout(value);
              } else if (value == 'fonts') {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ReaderFontSettingsPage()));
              }
            },
            itemBuilder: (context) {
              final l10n = AppLocalizations.of(context);
              final labels = {
                ReaderLayout.scroll: l10n.readerLayoutScroll,
                ReaderLayout.pagesLtr: l10n.readerLayoutPagesLtr,
                ReaderLayout.pagesRtl: l10n.readerLayoutPagesRtl,
              };
              return [
                for (final layout in ReaderLayout.values)
                  CheckedPopupMenuItem<Object>(
                    value: layout,
                    checked: layout == _layout,
                    child: Text(labels[layout]!),
                  ),
                const PopupMenuDivider(),
                PopupMenuItem<Object>(
                  value: 'fonts',
                  child: Text(l10n.readerFonts),
                ),
              ];
            },
          ),
          IconButton(
            key: const ValueKey('translateToggle'),
            tooltip: _translateOn
                ? AppLocalizations.of(context).translationShowOriginal
                : AppLocalizations.of(context).translationTranslate,
            icon: _translationStarting
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                  )
                : Icon(
                    _translateOn ? Icons.g_translate : Icons.translate,
                    color: _translateOn
                        ? Theme.of(context).colorScheme.secondary
                        : Theme.of(context).colorScheme.tertiary,
                  ),
            onPressed: () => _setTranslation(!_translateOn),
          ),
          if (_tts != null) ...[
            IconButton(
              tooltip: _ttsState == TtsState.playing
                  ? AppLocalizations.of(context).pauseReadingAloud
                  : _ttsState == TtsState.paused
                      ? AppLocalizations.of(context).resumeReadingAloud
                      : AppLocalizations.of(context).resumeReadingAloud,
              icon: Icon(
                _ttsState == TtsState.playing
                    ? Icons.pause_circle
                    : _ttsState == TtsState.paused
                        ? Icons.play_circle
                        : Icons.volume_up,
                color: Theme.of(context).colorScheme.tertiary,
              ),
              onPressed: _toggleTts,
            ),
            if (_ttsState != TtsState.idle)
              IconButton(
                tooltip: AppLocalizations.of(context).stopReadingAloud,
                icon: Icon(Icons.stop_circle,
                    color: Theme.of(context).colorScheme.tertiary),
                onPressed: _stopTts,
              ),
            // Speech rate lives between start/stop so it is reachable
            // while listening without crowding the bar when idle.
            IconButton(
              tooltip: AppLocalizations.of(context).speechSpeed,
              icon: Text(
                _ttsRateLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: Theme.of(context).colorScheme.tertiary,
                ),
              ),
              onPressed: _cycleTtsRate,
            ),
          ],
          IconButton(
            tooltip: AppLocalizations.of(context).decreaseFontSize,
            icon: Icon(Icons.text_decrease,
                color: Theme.of(context).colorScheme.tertiary),
            onPressed: () => _changeFontSize(-_fontSizeStep),
          ),
          Text(
            _fontSize.round().toString(),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: Theme.of(context).colorScheme.tertiary,
            ),
          ),
          IconButton(
            tooltip: AppLocalizations.of(context).increaseFontSize,
            icon: Icon(Icons.text_increase,
                color: Theme.of(context).colorScheme.tertiary),
            onPressed: () => _changeFontSize(_fontSizeStep),
          ),
        ],
      ),
      endDrawer: Drawer(
        child: EpubViewTableOfContents(controller: _epubReaderController),
      ),
      // Use standard EpubView without interfering gestures first to ensure it works
      body: Column(
        children: [
          _buildTranslationStatus(context),
          Expanded(
            child: Stack(
              children: [
                // SelectionArea lets readers select and copy text from the book.
                // Buttons and links inside the Html still work: SelectionArea only
                // captures drags that start on text.
                SelectionArea(
                  child: Focus(
                    focusNode: _focusNode,
                    autofocus: true,
                    child: _layout.paged
                        ? _buildPaged(context, isDarkMode)
                        : positionAsync.when(
                            data: (savedCfi) {
                              return EpubView(
                                controller: _epubReaderController,
                                onDocumentLoaded: (document) {
                                  final languages = document
                                      .Schema?.Package?.Metadata?.Languages;
                                  _bookLanguage =
                                      (languages == null || languages.isEmpty)
                                          ? null
                                          : languages.first;
                                  // Restore position if available
                                  final jump = _pendingScrollIndex;
                                  if (jump != null) {
                                    _pendingScrollIndex = null;
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) =>
                                            _epubReaderController.jumpTo(
                                                index: jump));
                                  } else if (savedCfi != null &&
                                      savedCfi.isNotEmpty) {
                                    _epubReaderController.gotoEpubCfi(savedCfi);
                                  }
                                },
                                onChapterChanged: (value) {
                                  // Land the position on every chapter change: a
                                  // process kill mid-book then loses at most one
                                  // chapter, not the whole session.
                                  final cfi =
                                      _epubReaderController.generateEpubCfi();
                                  saveEpubState(widget.fileName, cfi, ref);
                                  // Reading aloud continues into the chapter the
                                  // reader just landed on - whether the user swiped
                                  // there or TTS advanced itself.
                                  if (_tts != null &&
                                      _ttsState != TtsState.idle &&
                                      value?.chapter?.HtmlContent != null) {
                                    _startTts();
                                  }
                                },
                                builders: _buildersFor(isDarkMode),
                              );
                            },
                            loading: () => Center(
                              child: CircularProgressIndicator(
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                            ),
                            error: (err, stack) =>
                                Center(child: Text("Error loading book: $err")),
                          ),
                  ),
                ),
                if (_showTutorial)
                  ReaderHelpOverlay(
                    isDesktop: PlatformUtils.isDesktop,
                    onDismiss: () => setState(() => _showTutorial = false),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
