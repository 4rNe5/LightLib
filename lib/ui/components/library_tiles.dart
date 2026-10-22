// Library building blocks: book covers, the cover grid tile and the
// bento "continue reading" panel at the top of the library.

// Dart imports:
import 'dart:io';
import 'dart:ui' as ui;

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:cached_network_image/cached_network_image.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/library_organization.dart';
import 'package:openlib/services/local_book_import.dart'
    show isLocalImagePath, localImageFilePath;
import 'package:openlib/ui/components/book_card_widget.dart'
    show coverHeadersFor;
import 'package:openlib/ui/components/marquee_text.dart';

String genreLabel(AppLocalizations l10n, BookGenre genre) {
  switch (genre) {
    case BookGenre.lightNovel:
      return l10n.genreLightNovel;
    case BookGenre.comic:
      return l10n.genreComic;
    case BookGenre.novel:
      return l10n.genreNovel;
    case BookGenre.englishNovel:
      return l10n.genreEnglishNovel;
    case BookGenre.essay:
      return l10n.genreEssay;
    case BookGenre.science:
      return l10n.genreScience;
    case BookGenre.humanities:
      return l10n.genreHumanities;
    case BookGenre.business:
      return l10n.genreBusiness;
    case BookGenre.paper:
      return l10n.genrePaper;
    case BookGenre.textbook:
      return l10n.genreTextbook;
    case BookGenre.other:
      return l10n.genreOther;
  }
}

/// The app theme's colour scheme sets primary to white, which leaves
/// Material 3 components (chips, segmented buttons, tonal containers)
/// white-on-white or in raw red. The library and the reader sheet use a
/// tonal scheme grown from the app's accent instead, on neutral surfaces.
ThemeData modernSurfaceTheme(ThemeData base) {
  final dark = base.brightness == Brightness.dark;
  final tonal = ColorScheme.fromSeed(
    seedColor: const Color(0xFFFB0101),
    brightness: base.brightness,
  );
  final neutral = ColorScheme.fromSeed(
    seedColor: const Color(0xFFFB0101),
    brightness: base.brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.neutral,
  );
  final scheme = tonal.copyWith(
    surface: neutral.surface,
    surfaceContainerLowest: neutral.surfaceContainerLowest,
    surfaceContainerLow: neutral.surfaceContainerLow,
    surfaceContainer: neutral.surfaceContainer,
    surfaceContainerHigh: neutral.surfaceContainerHigh,
    surfaceContainerHighest: neutral.surfaceContainerHighest,
    outlineVariant: neutral.outlineVariant,
    onSurface: dark ? const Color(0xFFF2F2F2) : const Color(0xFF16181A),
    onSurfaceVariant: neutral.onSurfaceVariant,
  );
  return base.copyWith(
    colorScheme: scheme,
    chipTheme: base.chipTheme.copyWith(
      side: BorderSide(color: scheme.outlineVariant),
      backgroundColor: scheme.surfaceContainerLow,
      selectedColor: scheme.primaryContainer,
      labelStyle: TextStyle(color: scheme.onSurface),
      iconTheme: IconThemeData(color: scheme.primary, size: 15),
      shape: const StadiumBorder(),
    ),
  );
}

IconData genreIcon(BookGenre genre) {
  switch (genre) {
    case BookGenre.lightNovel:
      return Icons.auto_awesome;
    case BookGenre.comic:
      return Icons.collections_bookmark_outlined;
    case BookGenre.novel:
      return Icons.menu_book_outlined;
    case BookGenre.englishNovel:
      return Icons.abc;
    case BookGenre.essay:
      return Icons.edit_note;
    case BookGenre.science:
      return Icons.science_outlined;
    case BookGenre.humanities:
      return Icons.account_balance_outlined;
    case BookGenre.business:
      return Icons.trending_up;
    case BookGenre.paper:
      return Icons.article_outlined;
    case BookGenre.textbook:
      return Icons.school_outlined;
    case BookGenre.other:
      return Icons.more_horiz;
  }
}

/// A soft colour derived from the title, shown while a cover loads or
/// when a book has none.
Color _placeholderColor(String seed) {
  const colors = [
    Color(0xFFE8DCCB),
    Color(0xFFD6E4E5),
    Color(0xFFE5D4E8),
    Color(0xFFD9E5D2),
    Color(0xFFF0D9C9),
    Color(0xFFD5DCEF),
  ];
  return colors[seed.hashCode.abs() % colors.length];
}

/// A book's cover filling its box: a local file for imported books, a
/// cached network image otherwise, a titled placeholder without one.
class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.book, this.fit = BoxFit.cover});

  final LibraryBook book;
  final BoxFit fit;

  Widget _placeholder() => Container(
        color: _placeholderColor(book.title),
        padding: const EdgeInsets.all(10),
        alignment: Alignment.center,
        child: Text(
          book.title,
          textAlign: TextAlign.center,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF4A4036),
              height: 1.25),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final url = book.book.thumbnail;
    if (isLocalImagePath(url)) {
      return Image.file(
        File(localImageFilePath(url!)),
        fit: fit,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }
    if (url == null || url.isEmpty) return _placeholder();
    return CachedNetworkImage(
      imageUrl: url,
      httpHeaders: coverHeadersFor(url),
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      placeholder: (_, __) => Container(color: _placeholderColor(book.title)),
      errorWidget: (_, __, ___) => _placeholder(),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.child, this.color});
  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            color: color ?? Colors.black.withAlpha(110),
            child: DefaultTextStyle(
              style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.2),
              child: IconTheme(
                data: const IconThemeData(size: 11, color: Colors.white),
                child: child,
              ),
            ),
          ),
        ),
      );
}

/// A cover in the library grid with its title running underneath.
class LibraryGridTile extends StatelessWidget {
  const LibraryGridTile({
    super.key,
    required this.book,
    required this.onTap,
    this.onLongPress,
  });

  /// Height of the title and author under the cover.
  static const captionHeight = 46.0;

  final LibraryBook book;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final format = (book.book.format ?? '').toUpperCase();
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(45),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    BookCover(book: book),
                    // Spine shading, like a printed book.
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0x33000000), Color(0x00000000)],
                          stops: [0, 0.08],
                        ),
                      ),
                    ),
                    if (book.genre != null)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: _Pill(
                          child: Text(genreLabel(l10n, book.genre!)),
                        ),
                      ),
                    if (book.status == ReadingStatus.completed)
                      const Positioned(
                        top: 6,
                        right: 6,
                        child: _Pill(
                          color: Color(0xCC2E7D32),
                          child: Icon(Icons.check),
                        ),
                      )
                    else if (book.status == ReadingStatus.inProgress)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(height: 3, color: scheme.primary),
                      ),
                    if (format == 'PDF')
                      const Positioned(
                        bottom: 7,
                        right: 6,
                        child: _Pill(child: Text('PDF')),
                      ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            height: captionHeight,
            child: Padding(
              padding: const EdgeInsets.only(top: 7, left: 2, right: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MarqueeText(
                    book.title,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    book.author.isEmpty ? ' ' : book.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11, color: scheme.onSurfaceVariant),
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

/// The bento panel: one large card for the book being read (or the
/// newest one), a smaller card for the next, and a stats card.
class LibraryBentoPanel extends StatelessWidget {
  const LibraryBentoPanel({
    super.key,
    required this.books,
    required this.onOpen,
    this.onLongPress,
  });

  /// The whole library, newest first.
  final List<LibraryBook> books;
  final ValueChanged<LibraryBook> onOpen;
  final ValueChanged<LibraryBook>? onLongPress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reading =
        books.where((b) => b.status == ReadingStatus.inProgress).toList();
    final continuing = reading.isNotEmpty;
    final featured = continuing ? reading : books;
    if (featured.isEmpty) return const SizedBox.shrink();
    final hero = featured.first;
    final second = featured.length > 1 ? featured[1] : null;
    final finished =
        books.where((b) => b.status == ReadingStatus.completed).length;

    return LayoutBuilder(builder: (context, constraints) {
      const gap = 10.0;
      final unit = (constraints.maxWidth - 2 * gap) / 3;
      final small = unit * 1.3;
      final tall = small * 2 + gap;
      return SizedBox(
        height: tall,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: unit * 2 + gap,
              child: _HeroCard(
                key: const ValueKey('bentoHero'),
                book: hero,
                label: continuing
                    ? l10n.libraryContinueReading
                    : l10n.libraryRecentlyAdded,
                onTap: () => onOpen(hero),
                onLongPress:
                    onLongPress == null ? null : () => onLongPress!(hero),
              ),
            ),
            const SizedBox(width: gap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: second == null
                        ? _StatCard(
                            icon: Icons.local_library_outlined,
                            big: '${books.length}',
                            caption: l10n.libraryAllBooks,
                          )
                        : _SmallCoverCard(
                            book: second,
                            onTap: () => onOpen(second),
                            onLongPress: onLongPress == null
                                ? null
                                : () => onLongPress!(second),
                          ),
                  ),
                  const SizedBox(height: gap),
                  Expanded(
                    child: second == null
                        ? _StatCard(
                            icon: Icons.task_alt,
                            big: '$finished',
                            caption: l10n.statusCompleted,
                            tonal: true,
                          )
                        : _StatCard(
                            icon: Icons.local_library_outlined,
                            big: '${books.length}',
                            caption: l10n.libraryFinishedCount(finished),
                            tonal: true,
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    super.key,
    required this.book,
    required this.label,
    required this.onTap,
    this.onLongPress,
  });

  final LibraryBook book;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The cover, blurred, as the card's backdrop.
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 26, sigmaY: 26),
              child: Transform.scale(scale: 1.3, child: BookCover(book: book)),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x22000000), Color(0xB3000000)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 2 / 3,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: const [
                              BoxShadow(
                                  color: Color(0x66000000),
                                  blurRadius: 16,
                                  offset: Offset(0, 6)),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: BookCover(book: book),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _Pill(
                    color: Colors.white.withAlpha(50),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.play_arrow_rounded),
                        const SizedBox(width: 2),
                        Text(label),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  MarqueeText(
                    book.title,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                  ),
                  if (book.author.isNotEmpty)
                    Text(
                      book.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xCCFFFFFF)),
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

class _SmallCoverCard extends StatelessWidget {
  const _SmallCoverCard({
    required this.book,
    required this.onTap,
    this.onLongPress,
  });

  final LibraryBook book;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            BookCover(book: book),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0xCC000000)],
                  stops: [0.45, 1],
                ),
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 9,
              child: MarqueeText(
                book.title,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.big,
    required this.caption,
    this.tonal = false,
  });

  final IconData icon;
  final String big;
  final String caption;
  final bool tonal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = tonal ? scheme.surfaceContainerHigh : scheme.primaryContainer;
    final fg = tonal ? scheme.onSurface : scheme.onPrimaryContainer;
    final accent = tonal ? scheme.primary : fg;
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: accent),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(big,
                style: TextStyle(
                    fontSize: 30,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    color: fg)),
          ),
          const SizedBox(height: 4),
          Text(caption,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }
}
