// The home page for Japanese books: what sells on BOOK☆WALKER now (light
// novels, web novels in print, manga - a series at a time) and its
// genres. A book opens a library search for its series.

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/bookwalker.dart';
import 'package:openlib/state/state.dart'
    show
        enableFiltersState,
        japanCategoryProvider,
        japanGenreProvider,
        japanPopularProvider;
import 'package:openlib/ui/components/error_widget.dart';
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          for (final c in BookWalkerCategory.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                key: ValueKey('japanCategory-${c.name}'),
                label: Text(categoryLabel(l10n, c)),
                selected: c == selected,
                showCheckmark: false,
                onSelected: (_) =>
                    ref.read(japanCategoryProvider.notifier).state = c,
              ),
            ),
        ],
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

/// Covers in three columns, each opening a search for its series.
class BookWalkerGrid extends ConsumerWidget {
  const BookWalkerGrid({super.key, required this.books, this.onRefresh});

  final List<BookWalkerBook> books;
  final Future<void> Function()? onRefresh;

  static const double _coverHeight = 145;
  static const double _coverWidth = 105;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final grid = GridView.builder(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 13,
        mainAxisExtent: 205,
      ),
      itemCount: books.length,
      itemBuilder: (context, i) {
        final book = books[i];
        return InkWell(
          key: ValueKey('bookwalker-$i'),
          borderRadius: BorderRadius.circular(6),
          onTap: () => _openSearch(context, ref, book),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: CachedNetworkImage(
                  imageUrl: book.cover,
                  height: _coverHeight,
                  width: _coverWidth,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                      height: _coverHeight,
                      width: _coverWidth,
                      color: scheme.surfaceContainerHighest),
                  errorWidget: (_, __, ___) => Container(
                    height: _coverHeight,
                    width: _coverWidth,
                    color: scheme.surfaceContainerHighest,
                    child: const Icon(Icons.image_rounded),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: SizedBox(
                    width: _coverWidth,
                    child: Text(
                      book.searchQuery,
                      style: Theme.of(context).textTheme.displayMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    return onRefresh == null
        ? grid
        : RefreshIndicator(onRefresh: onRefresh!, child: grid);
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
        const SizedBox(height: 6),
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
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
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
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => JapanGenrePage(genre: genre))),
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
                child: Icon(_genreIcons[genre.tag] ?? Icons.auto_stories_rounded,
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
