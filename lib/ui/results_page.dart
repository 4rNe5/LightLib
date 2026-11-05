// Search results: by series (each series a card with the volumes the
// libraries have, a tap opening a volume's best file) or as the plain
// list of files; a catalog can be picked instead of the automatic order.
// Scrolling near the end loads the next page; a page that fails can be
// tried again.

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/annas_archieve.dart' show BookData;
import 'package:openlib/services/search_manager.dart' show SearchProviderId;
import 'package:openlib/services/search_results.dart';
import 'package:openlib/state/state.dart' as app_state;
import 'package:openlib/ui/book_info_page.dart';
import 'package:openlib/ui/components/book_card_widget.dart';
import 'package:openlib/ui/components/error_widget.dart';

// Custom extension for String to add the missing capitalizeFirst method
extension StringExtension on String {
  String get capitalizeFirst {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}

const _sources = <SearchProviderId?, String>{
  null: '',
  SearchProviderId.annasArchive: "Anna's Archive",
  SearchProviderId.libgen: 'LibGen',
  SearchProviderId.zlibrary: 'Z-Library',
  SearchProviderId.welib: 'WeLib',
};

/// Results for [searchQuery]; [source] null tries the enabled catalogs
/// in order.
class ResultPage extends StatefulWidget {
  const ResultPage({super.key, required this.searchQuery});
  final String searchQuery;

  @override
  State<ResultPage> createState() => _ResultPageShellState();
}

class _ResultPageShellState extends State<ResultPage> {
  SearchProviderId? _source;

  @override
  Widget build(BuildContext context) => _Results(
        key: ValueKey((widget.searchQuery, _source)),
        searchQuery: widget.searchQuery,
        source: _source,
        onSource: (s) => setState(() => _source = s),
      );
}

class _Results extends ConsumerStatefulWidget {
  const _Results({
    super.key,
    required this.searchQuery,
    required this.source,
    required this.onSource,
  });

  final String searchQuery;
  final SearchProviderId? source;
  final ValueChanged<SearchProviderId?> onSource;

  @override
  ConsumerState<_Results> createState() => _ResultsState();
}

/// Series or files, kept while the app runs.
bool _bySeries = true;

class _ResultsState extends ConsumerState<_Results> {
  final _scrollController = ScrollController();
  final List<BookData> _books = [];
  int _loadedPages = 0;
  bool _fetchingNextPage = false;
  bool _reachedEnd = false;
  Object? _pageError;

  app_state.SearchPageKey _key(int page) => app_state.SearchPageKey(
      widget.searchQuery, page,
      source: widget.source);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Page 1 may resolve before the first build; merge it the moment it
    // does. Once loaded, the pager owns accumulation from there.
    ref.listenManual(
      app_state.searchProvider(_key(1)),
      (previous, next) {
        final books = next.valueOrNull;
        if (books != null && _loadedPages == 0) {
          setState(() {
            _books.addAll(books);
            _loadedPages = 1;
            if (books.isEmpty) _reachedEnd = true;
          });
        }
      },
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_fetchingNextPage &&
        !_reachedEnd &&
        _pageError == null) {
      _loadNextPage();
    }
  }

  Future<void> _loadNextPage() async {
    if (!mounted || _fetchingNextPage) return;
    setState(() {
      _fetchingNextPage = true;
      _pageError = null;
    });
    final page = _loadedPages + 1;
    try {
      final nextPage =
          await ref.read(app_state.searchProvider(_key(page)).future);
      if (!mounted) return;
      setState(() {
        if (nextPage.isEmpty) {
          _reachedEnd = true;
        } else {
          _books.addAll(nextPage);
          _loadedPages = page;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _pageError = e);
    } finally {
      if (mounted) setState(() => _fetchingNextPage = false);
    }
  }

  void _retryNextPage() {
    ref.invalidate(app_state.searchProvider(_key(_loadedPages + 1)));
    _loadNextPage();
  }

  void _open(BookData book) => Navigator.push(context,
      MaterialPageRoute(builder: (_) => BookInfoPage(url: book.link)));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final firstPage = ref.watch(app_state.searchProvider(_key(1)));
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.resultsFor(widget.searchQuery.capitalizeFirst),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        titleTextStyle: Theme.of(context)
            .textTheme
            .titleLarge
            ?.copyWith(fontWeight: FontWeight.bold),
        backgroundColor: Theme.of(context).colorScheme.surface,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: _SourceChips(source: widget.source, onSource: widget.onSource),
        ),
      ),
      body: firstPage.when(
        data: (_) {
          // Page 1 has arrived but the listener has not merged it yet:
          // still loading, not "no results".
          if (_loadedPages == 0) return _buildLoading(context);
          if (_books.isEmpty) return _noResults(context);
          return _list(context);
        },
        error: (error, stackTrace) => CustomErrorWidget(
          error: error,
          stackTrace: stackTrace,
          onRefresh: () {
            setState(() {
              _books.clear();
              _loadedPages = 0;
              _reachedEnd = false;
            });
            ref.invalidate(app_state.searchProvider(_key(1)));
          },
        ),
        loading: () => _buildLoading(context),
      ),
    );
  }

  Widget _list(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final language = ref.watch(app_state.selectedLanguageState);
    final format = ref.watch(app_state.selectedFileTypeState);
    final grouped = groupResults(
      _books,
      language: language == 'All' ? null : language,
      format: format == 'All' ? null : format.toUpperCase(),
    );
    final bySeries = _bySeries && grouped.hasSeries;
    final source = _books.first.source;

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          sliver: SliverToBoxAdapter(
            child: Row(children: [
              Expanded(
                child: Text(
                  [
                    l10n.resultFileCount(_books.length),
                    if (source != null && source.isNotEmpty) source,
                  ].join(' · '),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant),
                ),
              ),
              if (grouped.hasSeries)
                SegmentedButton<bool>(
                  key: const ValueKey('resultsView'),
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  segments: [
                    ButtonSegment(value: true, label: Text(l10n.viewSeries)),
                    ButtonSegment(value: false, label: Text(l10n.viewFiles)),
                  ],
                  selected: {bySeries},
                  onSelectionChanged: (v) =>
                      setState(() => _bySeries = v.first),
                ),
            ]),
          ),
        ),
        if (bySeries) ...[
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverList.builder(
              itemCount: grouped.series.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SeriesCard(
                  series: grouped.series[i],
                  language: language == 'All' ? null : language,
                  onOpen: _open,
                ),
              ),
            ),
          ),
          if (grouped.singles.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              sliver: SliverToBoxAdapter(
                child: Text(l10n.otherResults,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface)),
              ),
            ),
          _fileList(grouped.singles.map((f) => f.book).toList()),
        ] else
          _fileList(_books),
        if (_pageError != null)
          SliverToBoxAdapter(
            child: Padding(
              key: const ValueKey('paginationError'),
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
              child: Row(children: [
                Expanded(child: Text(l10n.nextPageFailed)),
                TextButton(
                    onPressed: _retryNextPage, child: Text(l10n.retry)),
              ]),
            ),
          )
        else if (_fetchingNextPage || !_reachedEnd)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _fileList(List<BookData> books) => SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        sliver: SliverList.builder(
          itemCount: books.length,
          itemBuilder: (context, index) {
            final i = books[index];
            return BookInfoCard(
              title: i.title,
              author: i.author ?? 'unknown',
              publisher: i.publisher ?? 'unknown',
              thumbnail: i.thumbnail ?? '',
              info: i.info ?? '',
              link: i.link,
              md5: i.md5,
              source: i.source,
              onClick: () => _open(i),
            );
          },
        ),
      );

  Widget _noResults(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SvgPicture.asset('assets/no_results.svg',
                  width: 180, height: 180, fit: BoxFit.contain),
              const SizedBox(height: 24),
              Text(
                AppLocalizations.of(context).noResultsFound,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (widget.source == null) ...[
                const SizedBox(height: 8),
                Text(AppLocalizations.of(context).noResultsHint,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13,
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ],
          ),
        ),
      );

  /// Spinner plus what the search is waiting on.
  Widget _buildLoading(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final progress = ref.watch(app_state.searchProgressProvider(_key(1)));
    final status = progress == null
        ? l10n.searchingSources
        : progress.previousSource == null
            ? l10n.searchingSource(progress.source)
            : l10n.tryingNextSourceNamed(
                progress.previousSource!, progress.source);
    return Column(
      key: const ValueKey('resultsLoading'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Text(
            status,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: SizedBox(
              width: 25,
              height: 25,
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.secondary,
                strokeWidth: 3.0,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SourceChips extends StatelessWidget {
  const _SourceChips({required this.source, required this.onSource});
  final SearchProviderId? source;
  final ValueChanged<SearchProviderId?> onSource;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 48,
      child: ListView(
        key: const ValueKey('searchSource'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        children: [
          for (final MapEntry(key: id, value: name) in _sources.entries)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                key: ValueKey('source-${id?.name ?? 'auto'}'),
                label: Text(id == null ? l10n.automaticSource : name),
                selected: source == id,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => onSource(id),
              ),
            ),
        ],
      ),
    );
  }
}

/// A series: its cover, name and author, and a chip for each volume the
/// libraries have - a tap opens the volume's best file, a long press
/// lists all of its files.
class SeriesCard extends StatelessWidget {
  const SeriesCard({
    super.key,
    required this.series,
    required this.onOpen,
    this.language,
  });

  final SeriesGroup series;
  final String? language;
  final ValueChanged<BookData> onOpen;

  void _files(BuildContext context, String title, List<ResultFile> files) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (context) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.95,
          builder: (context, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              for (final f in files)
                BookInfoCard(
                  title: f.book.title,
                  author: f.book.author ?? 'unknown',
                  publisher: f.book.publisher ?? 'unknown',
                  thumbnail: f.book.thumbnail ?? '',
                  info: f.book.info ?? '',
                  link: f.book.link,
                  md5: f.book.md5,
                  source: f.book.source,
                  onClick: () {
                    Navigator.pop(context);
                    onOpen(f.book);
                  },
                ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final s = series;
    final formats = {
      for (final v in s.volumes)
        if (v.best.facts.format != null) v.best.facts.format!,
    };
    final cover = s.cover;
    return Material(
      key: ValueKey('series-${s.series}'),
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 66,
                height: 94,
                child: cover == null
                    ? ColoredBox(
                        color: scheme.secondaryContainer,
                        child: Icon(Icons.auto_stories_outlined,
                            color: scheme.onSecondaryContainer))
                    : CachedNetworkImage(
                        imageUrl: cover,
                        fit: BoxFit.cover,
                        httpHeaders: coverHeadersFor(cover),
                        errorWidget: (_, __, ___) => ColoredBox(
                            color: scheme.secondaryContainer,
                            child: const Icon(Icons.auto_stories_outlined)),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.series,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (s.author != null && s.author!.isNotEmpty) s.author!,
                      l10n.seriesVolumes(s.volumes.length),
                      if (formats.isNotEmpty) formats.join('/'),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final v in s.volumes)
                        _VolumeChip(
                          key: ValueKey('volume-${s.series}-${v.volume.display}'),
                          label: v.volume.display,
                          strong: language == null ||
                              v.best.facts.language == language,
                          multiple: v.files.length > 1,
                          onTap: () => onOpen(v.best.book),
                          onLongPress: () => _files(context,
                              '${s.series} · ${l10n.volumeNumber(v.volume.display)}', v.files),
                        ),
                      if (s.others.isNotEmpty)
                        _VolumeChip(
                          label: l10n.seriesOthers(s.others.length),
                          strong: false,
                          multiple: false,
                          onTap: () => _files(context, s.series, s.others),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VolumeChip extends StatelessWidget {
  const _VolumeChip({
    super.key,
    required this.label,
    required this.strong,
    required this.multiple,
    required this.onTap,
    this.onLongPress,
  });

  final String label;

  /// The best file is in the language asked for.
  final bool strong;

  /// More than one file: a long press lists them.
  final bool multiple;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: strong ? scheme.secondaryContainer : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          constraints: const BoxConstraints(minWidth: 38),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: strong
                        ? scheme.onSecondaryContainer
                        : scheme.onSurfaceVariant)),
            if (multiple) ...[
              const SizedBox(width: 3),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                    color: scheme.secondary, shape: BoxShape.circle),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
