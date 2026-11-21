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
import 'package:openlib/services/book_covers.dart';
import 'package:openlib/services/hidden_covers.dart';
import 'package:openlib/services/library_organization.dart';
import 'package:openlib/services/local_book_import.dart'
    show isLocalImagePath, localImageFilePath;
import 'package:openlib/ui/components/book_card_widget.dart'
    show coverHeadersFor;
import 'package:openlib/ui/components/marquee_text.dart';
import 'package:openlib/ui/components/motion.dart';

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
    seedColor: const Color(0xFFFF6B9D),
    brightness: base.brightness,
  );
  final neutral = ColorScheme.fromSeed(
    seedColor: const Color(0xFFFF6B9D),
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
      // (The app's own font, as everywhere else.)
      labelStyle: (base.textTheme.labelLarge ?? const TextStyle())
          .copyWith(color: scheme.onSurface),
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

/// The width a cover is decoded at to be shown [pixels] wide: the next of
/// a few steps, not the very width. A cover that flies from a tile to a
/// page changes its width every frame of the way, and a width of its own
/// each frame was a decode each frame - the flight stuttered and the
/// picture blinked.
int coverDecodeWidth(double pixels) {
  const steps = [160, 320, 480, 720, 1080, 1600];
  for (final step in steps) {
    if (pixels <= step) return step;
  }
  return steps.last;
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
  Widget build(BuildContext context) => ListenableBuilder(
        listenable:
            Listenable.merge([BookCovers.instance, HiddenCovers.instance]),
        builder: (context, _) => HiddenCovers.instance.isHidden(book.book.id)
            ? HiddenCover(title: book.title)
            : _cover(context),
      );

  Widget _cover(BuildContext context) {
    // The cover read from the book file first (full quality), then the
    // saved thumbnail.
    final url =
        BookCovers.instance.coverFor(book.book.id) ?? book.book.thumbnail;
    if (isLocalImagePath(url)) {
      // Decoded at the size it is shown, sharp on dense screens without
      // holding every full-size picture in memory.
      return LayoutBuilder(builder: (context, constraints) {
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final w = constraints.maxWidth;
        final cacheWidth =
            w.isFinite && w > 0 ? coverDecodeWidth(w * dpr) : null;
        return Image.file(
          File(localImageFilePath(url!)),
          fit: fit,
          width: double.infinity,
          height: double.infinity,
          cacheWidth: cacheWidth,
          filterQuality: FilterQuality.medium,
          // (While a larger copy is read - a cover on its way to a
          // larger place - the one there is stays.)
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _placeholder(),
        );
      });
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

/// A book's cover as the light of the room behind something: out of
/// focus, filling its box. A copy of the picture 48 pixels wide is
/// blurred once, into a picture of its own, and that is stretched over
/// the box: nothing is blurred while frames are drawn. (A blur as a
/// layer was worked out again every frame anything moved in front of it
/// or the layer itself faded - over a whole unfolded screen, while a book
/// was opening.) Nothing where the book has no cover or its cover is
/// hidden.
class BookCoverBackdrop extends StatefulWidget {
  const BookCoverBackdrop({super.key, required this.book, this.opacity = 1});

  final LibraryBook book;
  final double opacity;

  @override
  State<BookCoverBackdrop> createState() => _BookCoverBackdropState();
}

class _BookCoverBackdropState extends State<BookCoverBackdrop> {
  // The blurred pictures by where the cover is: a few bytes each, kept so
  // that a backdrop seen before is there in its first frame.
  static final Map<String, ui.Image> _blurred = {};
  static const _width = 48;

  String? _source;
  ui.Image? _image;
  ImageStream? _stream;
  late final ImageStreamListener _listener =
      ImageStreamListener(_arrived, onError: (_, __) {});

  @override
  void initState() {
    super.initState();
    BookCovers.instance.addListener(_resolve);
    HiddenCovers.instance.addListener(_resolve);
    _resolve(first: true);
  }

  @override
  void didUpdateWidget(BookCoverBackdrop old) {
    super.didUpdateWidget(old);
    if (old.book.book.id != widget.book.book.id ||
        old.book.book.thumbnail != widget.book.book.thumbnail) {
      _resolve();
    }
  }

  @override
  void dispose() {
    BookCovers.instance.removeListener(_resolve);
    HiddenCovers.instance.removeListener(_resolve);
    _stream?.removeListener(_listener);
    super.dispose();
  }

  void _resolve({bool first = false}) {
    final book = widget.book.book;
    final url = HiddenCovers.instance.isHidden(book.id)
        ? null
        : BookCovers.instance.coverFor(book.id) ?? book.thumbnail;
    final source = url == null || url.isEmpty ? null : url;
    if (source == _source) return;
    _stream?.removeListener(_listener);
    _stream = null;
    _source = source;
    final known = source == null ? null : _blurred[source];
    if (first) {
      _image = known;
    } else if (mounted) {
      setState(() => _image = known);
    }
    if (source == null || known != null) return;
    final ImageProvider picture = isLocalImagePath(source)
        ? FileImage(File(localImageFilePath(source)))
        : CachedNetworkImageProvider(source,
            headers: coverHeadersFor(source)) as ImageProvider;
    _stream = ResizeImage(picture, width: _width)
        .resolve(ImageConfiguration.empty)
      ..addListener(_listener);
  }

  void _arrived(ImageInfo info, bool _) {
    final source = _source;
    _stream?.removeListener(_listener);
    _stream = null;
    if (source == null) {
      info.dispose();
      return;
    }
    final blurred = _blur(info.image);
    info.dispose();
    if (_blurred.length >= 48) _blurred.remove(_blurred.keys.first);
    _blurred[source] = blurred;
    if (mounted) setState(() => _image = blurred);
  }

  /// [small], out of focus, the same size.
  static ui.Image _blur(ui.Image small) {
    final w = small.width.toDouble();
    final h = small.height.toDouble();
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImageRect(
      small,
      Rect.fromLTWH(0, 0, w, h),
      // (A little larger than its box: the blur's soft edge falls
      // outside.)
      Rect.fromLTWH(-w * 0.125, -h * 0.125, w * 1.25, h * 1.25),
      Paint()
        ..filterQuality = FilterQuality.medium
        ..imageFilter = ui.ImageFilter.blur(
            sigmaX: 3, sigmaY: 3, tileMode: TileMode.clamp),
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(small.width, small.height);
    picture.dispose();
    return image;
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    // (Comes in softly where it was not known in the first frame.)
    return AnimatedOpacity(
      opacity: image == null ? 0 : 1,
      duration: AppMotion.reduced(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      child: image == null
          ? const SizedBox.expand()
          : RawImage(
              image: image,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              filterQuality: FilterQuality.medium,
              opacity: AlwaysStoppedAnimation(widget.opacity),
            ),
    );
  }
}

/// In place of a cover the reader chose to hide: a plain card with the
/// title and a crossed-out eye.
class HiddenCover extends StatelessWidget {
  const HiddenCover({super.key, required this.title, this.radius = 0});

  final String title;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('hiddenCover'),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
            scheme.onSurface.withValues(alpha: 0.08), scheme.surface),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.08)),
      ),
      padding: const EdgeInsets.all(10),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.visibility_off_outlined,
              size: 20, color: scheme.onSurface.withValues(alpha: 0.45)),
          const SizedBox(height: 8),
          Flexible(
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                  color: scheme.onSurface.withValues(alpha: 0.75)),
            ),
          ),
        ],
      ),
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
            child: DefaultTextStyle.merge(
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

/// How far a book was read, in one line under its cover: a bar and the
/// percent while it is being read, a check once it is finished. Nothing
/// for a book not opened yet.
class ReadingLine extends StatelessWidget {
  const ReadingLine({super.key, required this.book, this.onDark = false});

  final LibraryBook book;

  /// Over a picture: white on dark.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final accent = onDark ? Colors.white : scheme.primary;
    final style = TextStyle(
        fontSize: 10.5,
        height: 1.1,
        fontWeight: FontWeight.w800,
        color: accent,
        fontFeatures: const [ui.FontFeature.tabularFigures()]);
    switch (book.status) {
      case ReadingStatus.unread:
        return const SizedBox.shrink();
      case ReadingStatus.completed:
        return Row(
          key: ValueKey('readingLine-${book.id}'),
          children: [
            Icon(Icons.check_circle_rounded, size: 12, color: accent),
            const SizedBox(width: 3),
            Flexible(
              child: Text(l10n.statusCompleted,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
            ),
          ],
        );
      case ReadingStatus.inProgress:
        final percent = book.percent;
        // (How far is not known - a viewer that does not say: the word,
        // no bar.)
        if (percent == null) {
          return Align(
            key: ValueKey('readingLine-${book.id}'),
            alignment: AlignmentDirectional.centerStart,
            child: Text(l10n.statusInProgress,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
          );
        }
        return Row(
          key: ValueKey('readingLine-${book.id}'),
          children: [
            Expanded(
              child: ProgressBar(
                value: book.fraction,
                height: 3.5,
                color: accent,
                trackColor: onDark
                    ? Colors.white.withValues(alpha: 0.28)
                    : scheme.onSurface.withValues(alpha: 0.14),
              ),
            ),
            const SizedBox(width: 6),
            Text('$percent%', style: style),
          ],
        );
    }
  }
}

/// A cover in the library grid with its title running underneath.
class LibraryGridTile extends StatelessWidget {
  const LibraryGridTile({
    super.key,
    required this.book,
    required this.onTap,
    this.onLongPress,
    this.selected,
    this.shown = false,
    this.heroTag,
  });

  /// Height of the title and the line under it.
  static const captionHeight = 46.0;

  final LibraryBook book;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// While books are being chosen: whether this one is. Null otherwise.
  final bool? selected;

  /// The pane beside the shelf shows this book: a ring round its cover.
  final bool shown;

  /// The cover flies to the book's page under this tag.
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final format = (book.book.format ?? '').toUpperCase();
    Widget cover = ClipRRect(
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
        ],
      ),
    );
    if (heroTag != null) cover = Hero(tag: heroTag!, child: cover);
    return Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: AnimatedContainer(
              duration: AppMotion.reduced(context)
                  ? Duration.zero
                  : AppMotion.standard,
              curve: AppMotion.enter,
              // The ring of the book the pane shows, a hair off the cover.
              padding: EdgeInsets.all(shown ? 3 : 0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(shown ? 13 : 10),
                border: Border.all(
                    color: shown ? scheme.primary : Colors.transparent,
                    width: 2,
                    strokeAlign: BorderSide.strokeAlignOutside),
              ),
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
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    cover,
                    if (book.genre != null)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: _Pill(
                          child: Text(genreLabel(l10n, book.genre!)),
                        ),
                      ),
                    if (book.status == ReadingStatus.completed &&
                        selected == null)
                      const Positioned(
                        top: 6,
                        right: 6,
                        child: _Pill(
                          color: Color(0xCC2E7D32),
                          child: Icon(Icons.check),
                        ),
                      ),
                    if (format == 'PDF')
                      const Positioned(
                        bottom: 7,
                        right: 6,
                        child: _Pill(child: Text('PDF')),
                      ),
                    // Being chosen: the ones not chosen step back, the
                    // chosen ones carry a mark.
                    if (selected == false)
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color(0x66000000),
                          borderRadius: BorderRadius.all(Radius.circular(10)),
                        ),
                      ),
                    if (selected != null)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          key: ValueKey('librarySelect-${book.id}'),
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: selected!
                                ? scheme.primary
                                : const Color(0x99000000),
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          child: selected!
                              ? Icon(Icons.check,
                                  size: 16, color: scheme.onPrimary)
                              : null,
                        ),
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
                  // Once the book is opened, how far it was read stands
                  // where its author did.
                  if (book.status == ReadingStatus.unread)
                    Text(
                      book.author.isEmpty ? ' ' : book.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant),
                    )
                  else
                    SizedBox(height: 15, child: ReadingLine(book: book)),
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
    this.onContinue,
    this.heroTags = false,
  });

  /// The whole library, newest first.
  final List<LibraryBook> books;
  final ValueChanged<LibraryBook> onOpen;
  final ValueChanged<LibraryBook>? onLongPress;

  /// Straight on with the book in the large card (its round button).
  final ValueChanged<LibraryBook>? onContinue;

  /// The covers fly to the book's page (off where a tap changes a pane
  /// of this same screen).
  final bool heroTags;

  /// The cover's tag in the large card and in the small one.
  static Object heroTagOf(LibraryBook book) => 'bentoCover:${book.id}';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // The book read last comes first.
    final reading = continueReading(books);
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
                heroTag: heroTags ? heroTagOf(hero) : null,
                label: continuing
                    ? l10n.libraryContinueReading
                    : l10n.libraryRecentlyAdded,
                onTap: () => onOpen(hero),
                onLongPress:
                    onLongPress == null ? null : () => onLongPress!(hero),
                onContinue:
                    onContinue == null ? null : () => onContinue!(hero),
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
                            big: books.length,
                            caption: l10n.libraryAllBooks,
                          )
                        : _SmallCoverCard(
                            book: second,
                            heroTag: heroTags ? heroTagOf(second) : null,
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
                            big: finished,
                            caption: l10n.statusCompleted,
                            tonal: true,
                          )
                        : _StatCard(
                            icon: Icons.local_library_outlined,
                            big: books.length,
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
    this.onContinue,
    this.heroTag,
  });

  final LibraryBook book;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onContinue;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    Widget cover = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: BookCover(book: book),
    );
    if (heroTag != null) cover = Hero(tag: heroTag!, child: cover);
    return Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      scale: 0.975,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The cover, out of focus, as the card's backdrop.
            ColoredBox(
              color: const Color(0xFF2A2527),
              child: BookCoverBackdrop(book: book),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x33000000), Color(0xC2000000)],
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
                          child: cover,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Pill(
                              color: Colors.white.withAlpha(50),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.play_arrow_rounded),
                                  const SizedBox(width: 2),
                                  Flexible(
                                    child: Text(label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                  ),
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
                      if (onContinue != null) ...[
                        const SizedBox(width: 8),
                        _PlayButton(
                            key: const ValueKey('bentoContinue'),
                            onTap: onContinue!),
                      ],
                    ],
                  ),
                  if (book.status != ReadingStatus.unread) ...[
                    const SizedBox(height: 9),
                    SizedBox(
                        height: 13,
                        child: ReadingLine(book: book, onDark: true)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Straight on with the book: the round button on its card.
class _PlayButton extends StatelessWidget {
  const _PlayButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFFF6B9D);
    return Semantics(
      button: true,
      label: AppLocalizations.of(context).libraryContinueReading,
      child: Pressable(
        onTap: onTap,
        scale: 0.9,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(accent, Colors.white, 0.06)!,
                Color.lerp(accent, Colors.black, 0.18)!,
              ],
            ),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x59000000),
                  blurRadius: 10,
                  offset: Offset(0, 4)),
            ],
          ),
          child: const Icon(Icons.play_arrow_rounded,
              color: Colors.white, size: 26),
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
    this.heroTag,
  });

  final LibraryBook book;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    Widget cover = BookCover(book: book);
    if (heroTag != null) {
      cover = Hero(
          tag: heroTag!,
          child: ClipRRect(
              borderRadius: BorderRadius.circular(18), child: cover));
    }
    return Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            cover,
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0xD9000000)],
                  stops: [0.4, 1],
                ),
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 9,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  MarqueeText(
                    book.title,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                  ),
                  if (book.status != ReadingStatus.unread) ...[
                    const SizedBox(height: 5),
                    SizedBox(
                        height: 12,
                        child: ReadingLine(book: book, onDark: true)),
                  ],
                ],
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
  final int big;
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
            child: CountUp(big,
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
