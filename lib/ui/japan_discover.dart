// The home page for Japanese books: what sells on BOOK☆WALKER now (light
// novels, web novels in print, manga - a series at a time) and its
// genres. A book opens a library search for its series.

// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/bookwalker.dart';
import 'package:openlib/services/local_book_import.dart'
    show isLocalImagePath, localImageFilePath;
import 'package:openlib/state/state.dart'
    show
        enableFiltersState,
        japanCategoryProvider,
        japanGenreProvider,
        japanPopularProvider;
import 'package:openlib/ui/components/error_widget.dart';
import 'package:openlib/ui/components/motion.dart';
import 'package:openlib/ui/results_page.dart';

String categoryLabel(AppLocalizations l10n, BookWalkerCategory c) =>
    switch (c) {
      BookWalkerCategory.lightNovel => l10n.japanLightNovels,
      BookWalkerCategory.newLiterature => l10n.japanNewLiterature,
      BookWalkerCategory.manga => l10n.japanManga,
    };

/// Light novels, web novels in print, manga.
class JapanCategoryChips extends ConsumerWidget {
  const JapanCategoryChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final selected = ref.watch(japanCategoryProvider);
    // Full width, so a Column does not center the row.
    return SizedBox(
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            for (final c in BookWalkerCategory.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _SoftChip(
                  key: ValueKey('japanCategory-${c.name}'),
                  label: categoryLabel(l10n, c),
                  selected: c == selected,
                  onTap: () =>
                      ref.read(japanCategoryProvider.notifier).state = c,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A filled pill, no outline: the chosen one in the accent colour.
class _SoftChip extends StatelessWidget {
  const _SoftChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected
            ? scheme.secondary
            : scheme.onSurface.withValues(alpha: 0.08),
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Text(
              label,
              style: (theme.textTheme.labelLarge ?? const TextStyle()).copyWith(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected
                    ? Colors.white
                    : scheme.onSurface.withValues(alpha: 0.75),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void _openSearch(BuildContext context, WidgetRef ref, BookWalkerBook book) {
  ref.read(enableFiltersState.notifier).state = false;
  Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => ResultPage(searchQuery: book.searchQuery)));
}

/// A store's cover: fetched and kept, or a picture file (the pictures
/// of the app's screens are drawn without a network).
class _StoreCover extends StatelessWidget {
  const _StoreCover(this.url);

  final String url;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget empty([Widget? child]) => ColoredBox(
        color: scheme.onSurface.withValues(alpha: 0.08),
        child: Center(child: child));
    if (isLocalImagePath(url)) {
      return Image.file(File(localImageFilePath(url)),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, __, ___) => empty());
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      placeholder: (_, __) => empty(),
      errorWidget: (_, __, ___) => empty(Icon(Icons.image_rounded,
          color: scheme.onSurface.withValues(alpha: 0.3))),
    );
  }
}

/// A list of the store's books as covers, each opening a search for its
/// series: three columns on a phone, more on a wider screen. [ranked]:
/// the list is in the order they sell - the first one large, with the
/// next few beside it, and a number on the first ten.
class BookWalkerGrid extends ConsumerWidget {
  const BookWalkerGrid(
      {super.key, required this.books, this.onRefresh, this.ranked = false});

  final List<BookWalkerBook> books;
  final Future<void> Function()? onRefresh;
  final bool ranked;

  static const _gap = 12.0;
  static const _rowGap = 14.0;
  static const _caption = 42.0;

  /// A cover with its series' name under it.
  Widget _tile(BuildContext context, WidgetRef ref, int i) {
    final book = books[i];
    final scheme = Theme.of(context).colorScheme;
    return Pressable(
      key: ValueKey('bookwalker-$i'),
      onTap: () => _openSearch(context, ref, book),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withAlpha(40),
                      blurRadius: 10,
                      offset: const Offset(0, 4)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _StoreCover(book.cover),
                    if (ranked && i < 10)
                      Positioned(top: 6, left: 6, child: _Rank(i + 1)),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            height: _caption,
            child: Padding(
              padding: const EdgeInsets.only(top: 6, left: 2, right: 2),
              child: Text(
                book.searchQuery,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The one that sells most: its cover large, its name over it.
  Widget _first(BuildContext context, WidgetRef ref) {
    final book = books.first;
    return Pressable(
      key: const ValueKey('bookwalker-0'),
      scale: 0.975,
      onTap: () => _openSearch(context, ref, book),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withAlpha(60),
                blurRadius: 16,
                offset: const Offset(0, 8)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _StoreCover(book.cover),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xD9000000)],
                    stops: [0.5, 1],
                  ),
                ),
              ),
              const Positioned(top: 10, left: 10, child: _Rank(1, large: true)),
              Positioned(
                left: 14,
                right: 14,
                bottom: 12,
                child: Text(
                  book.searchQuery,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 16,
                      height: 1.25,
                      fontWeight: FontWeight.w800,
                      color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = LayoutBuilder(builder: (context, constraints) {
      const side = 12.0;
      final width = constraints.maxWidth - side * 2;
      // Three columns on a phone, as many as fit a cover of about 120
      // on a wider screen.
      final columns = width < 520 ? 3 : (width / 128).floor().clamp(4, 8);
      final tileWidth = (width - _gap * (columns - 1)) / columns;
      final tileHeight = tileWidth / 0.7 + _caption;
      // The first book takes two columns and two rows; the ones after
      // it fill the rest of those rows.
      final lead = ranked && books.length > 2 * (columns - 2);
      final beside = lead ? 2 * (columns - 2) : 0;
      final rest = lead ? 1 + beside : 0;
      final fresh = _GridAge.of(context);
      Widget shown(int i, Widget child) =>
          fresh ? Appear.staggered(i, child: child) : child;
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (lead)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(side, 10, side, _rowGap),
              sliver: SliverToBoxAdapter(
                child: SizedBox(
                  height: tileHeight * 2 + _rowGap,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: tileWidth * 2 + _gap,
                        child: Padding(
                          // (As tall as the covers beside it, not their
                          // captions.)
                          padding: const EdgeInsets.only(bottom: _caption),
                          child: shown(0, _first(context, ref)),
                        ),
                      ),
                      const SizedBox(width: _gap),
                      Expanded(
                        child: Column(
                          children: [
                            for (var row = 0; row < 2; row++) ...[
                              if (row > 0) const SizedBox(height: _rowGap),
                              Expanded(
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    for (var c = 0; c < columns - 2; c++) ...[
                                      if (c > 0) const SizedBox(width: _gap),
                                      Expanded(
                                        child: shown(
                                            1 + row * (columns - 2) + c,
                                            _tile(context, ref,
                                                1 + row * (columns - 2) + c)),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(side, lead ? 0 : 10, side, 24),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: _gap,
                mainAxisSpacing: _rowGap,
                mainAxisExtent: tileHeight,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) =>
                    shown(rest + i, _tile(context, ref, rest + i)),
                childCount: books.length - rest,
              ),
            ),
          ),
        ],
      );
    });
    final grid = _GridAge(child: view);
    return onRefresh == null
        ? grid
        : RefreshIndicator(onRefresh: onRefresh!, child: grid);
  }
}

/// Whether the grid under it has only just come up: covers built in its
/// first moments rise into place one after the other, those scrolled to
/// later are simply there.
class _GridAge extends StatefulWidget {
  const _GridAge({required this.child});

  final Widget child;

  static bool of(BuildContext context) {
    final state = context.findAncestorStateOfType<_GridAgeState>();
    return state != null &&
        DateTime.now().difference(state._since) <
            const Duration(milliseconds: 700);
  }

  @override
  State<_GridAge> createState() => _GridAgeState();
}

class _GridAgeState extends State<_GridAge> {
  final DateTime _since = DateTime.now();

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Where a book stands in the list of what sells.
class _Rank extends StatelessWidget {
  const _Rank(this.rank, {this.large = false});

  final int rank;
  final bool large;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFFF6B9D);
    final size = large ? 34.0 : 22.0;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: rank <= 3 ? accent : const Color(0xB3000000),
        boxShadow: const [
          BoxShadow(color: Color(0x40000000), blurRadius: 6),
        ],
      ),
      child: Text('$rank',
          style: TextStyle(
              fontSize: large ? 17 : 11.5,
              height: 1,
              fontWeight: FontWeight.w900,
              color: Colors.white)),
    );
  }
}

Widget _loading(BuildContext context) => Center(
      child: SizedBox(
        width: 25,
        height: 25,
        child: CircularProgressIndicator(
          color: Theme.of(context).colorScheme.secondary,
          strokeCap: StrokeCap.round,
        ),
      ),
    );

/// What sells now, in the chosen category.
class JapanTrendingView extends ConsumerWidget {
  const JapanTrendingView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final category = ref.watch(japanCategoryProvider);
    final books = ref.watch(japanPopularProvider(category));
    Future<void> refresh() async {
      BookWalker.instance.forget();
      return ref.refresh(japanPopularProvider(category).future).then((_) {});
    }

    return Column(
      children: [
        const SizedBox(height: 10),
        const JapanCategoryChips(),
        const SizedBox(height: 4),
        Expanded(
          child: books.when(
            skipLoadingOnRefresh: false,
            data: (data) => data.isEmpty
                ? CustomErrorWidget(
                    error: Exception('Nothing found on BOOK☆WALKER'),
                    stackTrace: StackTrace.empty,
                    onRefresh: refresh)
                : BookWalkerGrid(
                    books: data, onRefresh: refresh, ranked: true),
            error: (error, _) => CustomErrorWidget(
                error: error, stackTrace: StackTrace.empty, onRefresh: refresh),
            loading: () => _loading(context),
          ),
        ),
      ],
    );
  }
}

/// The genres. (No covers on the tiles: one page per genre is about
/// 700 KB, fourteen of them to show a list of names.)
class JapanGenresView extends ConsumerWidget {
  const JapanGenresView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 260,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: 96,
      ),
      itemCount: bookWalkerGenres.length,
      itemBuilder: (context, i) => _GenreTile(genre: bookWalkerGenres[i]),
    );
  }
}

const _genreIcons = <int, IconData>{
  1995: Icons.public_rounded,
  146: Icons.auto_fix_high_rounded,
  99: Icons.favorite_border_rounded,
  97: Icons.favorite_rounded,
  1559: Icons.sports_martial_arts_rounded,
  77: Icons.search_rounded,
  55: Icons.rocket_launch_rounded,
  79: Icons.nights_stay_rounded,
  26: Icons.account_balance_rounded,
  82: Icons.sports_soccer_rounded,
  72: Icons.movie_rounded,
  42: Icons.done_all_rounded,
  2: Icons.male_rounded,
  3: Icons.female_rounded,
};

class _GenreTile extends ConsumerWidget {
  const _GenreTile({required this.genre});

  final BookWalkerGenre genre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final language = Localizations.localeOf(context).languageCode;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('japanGenre-${genre.tag}'),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => JapanGenrePage(genre: genre))),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(genre.name(language),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    if (language != 'ja')
                      Text(genre.japanese,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                    _genreIcons[genre.tag] ?? Icons.auto_stories_rounded,
                    color: scheme.onPrimaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One genre's most popular series, in the chosen category.
class JapanGenrePage extends ConsumerWidget {
  const JapanGenrePage({super.key, required this.genre});

  final BookWalkerGenre genre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final category = ref.watch(japanCategoryProvider);
    final books = ref.watch(japanGenreProvider((category, genre)));
    final language = Localizations.localeOf(context).languageCode;
    Future<void> refresh() async {
      BookWalker.instance.forget();
      return ref
          .refresh(japanGenreProvider((category, genre)).future)
          .then((_) {});
    }

    return Scaffold(
      appBar: AppBar(title: Text(genre.name(language))),
      body: Column(
        children: [
          const JapanCategoryChips(),
          Expanded(
            child: books.when(
              skipLoadingOnRefresh: false,
              data: (data) => data.isEmpty
                  ? CustomErrorWidget(
                      error: Exception('Nothing found on BOOK☆WALKER'),
                      stackTrace: StackTrace.empty,
                      onRefresh: refresh)
                  : BookWalkerGrid(books: data, onRefresh: refresh),
              error: (error, _) => CustomErrorWidget(
                  error: error,
                  stackTrace: StackTrace.empty,
                  onRefresh: refresh),
              loading: () => _loading(context),
            ),
          ),
        ],
      ),
    );
  }
}
