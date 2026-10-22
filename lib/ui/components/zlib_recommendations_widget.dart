// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:cached_network_image/cached_network_image.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/annas_archieve.dart' show BookData;
import 'package:openlib/services/search_manager.dart';

/// Number of mosaic columns for [width]: the site lays the mosaic out in
/// five columns on desktop; narrow screens get fewer, never below three.
@visibleForTesting
int recommendationColumns(double width) =>
    (width / 110).floor().clamp(3, 5).toInt();

/// How many of [count] books the mosaic shows: like the site's
/// `buildMosaic()`, an incomplete last row is held back while more pages
/// can still fill it. The final page shows everything.
@visibleForTesting
int visibleRecommendationCount(int count, int columns, bool hasMore) {
  if (!hasMore || count <= columns) return count;
  return count - count % columns;
}

/// Z-Library's "You may be interested in" section under a book page:
/// a cover-only masonry mosaic with a "Load more" button, as on the site.
class ZlibRecommendationsWidget extends StatefulWidget {
  const ZlibRecommendationsWidget({
    super.key,
    required this.initial,
    required this.onOpen,
    this.provider,
  });

  final ZlibraryRecommendations initial;

  /// Opens a recommended book (its Z-Library book page).
  final void Function(BookData book) onOpen;

  /// Injected in tests; defaults to a fresh [ZlibraryProvider].
  final ZlibraryProvider? provider;

  @override
  State<ZlibRecommendationsWidget> createState() =>
      _ZlibRecommendationsWidgetState();
}

class _ZlibRecommendationsWidgetState extends State<ZlibRecommendationsWidget> {
  late ZlibraryRecommendations _data = widget.initial;
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _autoLoadIfEmpty();
  }

  /// A page that rendered no mosaic items but carries the API cursor gets
  /// its first page straight from the API, so the section is not blank.
  void _autoLoadIfEmpty() {
    if (_data.books.isEmpty && _data.hasMore) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadMore();
      });
    }
  }

  @override
  void didUpdateWidget(covariant ZlibRecommendationsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.initial, widget.initial)) {
      _data = widget.initial;
      _loading = false;
      _failed = false;
      _autoLoadIfEmpty();
    }
  }

  Future<void> _loadMore() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final next = await (widget.provider ?? ZlibraryProvider())
          .loadMoreRecommendations(_data);
      if (!mounted) return;
      setState(() {
        _data = next;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tertiary = Theme.of(context).colorScheme.tertiary;

    // Nothing to show and nothing left to fetch: no empty section.
    if (_data.books.isEmpty && !_data.hasMore && !_loading && !_failed) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.zlibRecommendationsTitle,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: tertiary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          if (_data.books.isEmpty && _loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: tertiary),
                ),
              ),
            ),
          LayoutBuilder(builder: (context, constraints) {
            final columns = recommendationColumns(constraints.maxWidth);
            final count = visibleRecommendationCount(
                _data.books.length, columns, _data.hasMore);
            return _Mosaic(
              books: _data.books.take(count).toList(),
              columns: columns,
              onOpen: widget.onOpen,
            );
          }),
          if ((_data.hasMore && _data.books.isNotEmpty) || _failed)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Center(
                child: Column(
                  children: [
                    if (_failed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          l10n.zlibRecommendationsLoadFailed,
                          style: TextStyle(
                              fontSize: 12, color: tertiary.withAlpha(170)),
                        ),
                      ),
                    OutlinedButton(
                      key: const ValueKey('zlibRecommendationsLoadMore'),
                      onPressed: _loading ? null : _loadMore,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: tertiary,
                        side: BorderSide(color: tertiary.withAlpha(120)),
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 22, vertical: 10),
                      ),
                      child: _loading
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: tertiary,
                              ),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_failed
                                    ? l10n.retry
                                    : l10n.zlibRecommendationsLoadMore),
                                const SizedBox(width: 6),
                                const Icon(Icons.keyboard_arrow_down, size: 18),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Column masonry: books go round-robin into [columns] columns and each
/// cover keeps its own aspect ratio, so columns end at different heights
/// as on the site.
class _Mosaic extends StatelessWidget {
  const _Mosaic({
    required this.books,
    required this.columns,
    required this.onOpen,
  });

  final List<BookData> books;
  final int columns;
  final void Function(BookData book) onOpen;

  static const double _gap = 10;

  @override
  Widget build(BuildContext context) {
    final perColumn = List.generate(columns, (_) => <BookData>[]);
    for (var i = 0; i < books.length; i++) {
      perColumn[i % columns].add(books[i]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var c = 0; c < columns; c++) ...[
          if (c > 0) const SizedBox(width: _gap),
          Expanded(
            child: Column(
              children: [
                for (final book in perColumn[c])
                  Padding(
                    padding: const EdgeInsets.only(bottom: _gap),
                    child: _Cover(book: book, onTap: () => onOpen(book)),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.book, required this.onTap});

  final BookData book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(8);
    Widget fallback({bool showTitle = false}) => AspectRatio(
          aspectRatio: 2 / 3,
          child: Container(
            color: Colors.grey.withAlpha(90),
            padding: const EdgeInsets.all(6),
            alignment: Alignment.center,
            child: showTitle
                ? Text(
                    book.title,
                    textAlign: TextAlign.center,
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 10, fontWeight: FontWeight.bold),
                  )
                : null,
          ),
        );

    final thumbnail = book.thumbnail;
    return Tooltip(
      message: '${book.title}\n${book.author ?? ''}'.trim(),
      waitDuration: const Duration(milliseconds: 600),
      child: Semantics(
        button: true,
        label: book.title,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(40),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Stack(
              children: [
                thumbnail == null
                    ? fallback(showTitle: true)
                    : CachedNetworkImage(
                        imageUrl: thumbnail,
                        width: double.infinity,
                        fit: BoxFit.fitWidth,
                        placeholder: (context, url) => fallback(),
                        errorWidget: (context, url, error) =>
                            fallback(showTitle: true),
                      ),
                // Above the cover so the ripple is visible on it.
                Positioned.fill(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(onTap: onTap),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
