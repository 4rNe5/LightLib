// A page-turning reader: the book laid out into screen-sized pages that
// are turned by swiping or tapping the page edges, like an e-ink reader.

// Dart imports:
import 'dart:math' as math;
import 'dart:typed_data';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:epub_view/epub_view.dart' hide Image;
// ignore: implementation_imports
import 'package:epub_view/src/data/models/paragraph.dart';

// Project imports:
import 'package:openlib/services/translation/paragraph_text.dart';

/// How the reader presents the book.
enum ReaderLayout {
  /// One continuous column (the original reader).
  scroll,

  /// Pages turned right-to-left swipe, left edge = back (western books).
  pagesLtr,

  /// Pages turned left-to-right swipe, right edge = back (manga and
  /// Japanese books).
  pagesRtl;

  bool get paged => this != ReaderLayout.scroll;

  static ReaderLayout fromName(String? name) => ReaderLayout.values
      .firstWhere((l) => l.name == name, orElse: () => ReaderLayout.scroll);
}

/// One piece of a page: part of a paragraph's text, or an image.
@immutable
class PageSlice {
  final int paragraph;
  final String text;
  final bool heading;
  final bool endsParagraph;
  final Uint8List? image;

  const PageSlice({
    required this.paragraph,
    this.text = '',
    this.heading = false,
    this.endsParagraph = true,
    this.image,
  });
}

@immutable
class BookPage {
  final List<PageSlice> slices;
  const BookPage(this.slices);
  int get firstParagraph => slices.first.paragraph;
}

/// What a paragraph shows as: its text (the translation when there is one)
/// and whether it is a heading. Images are found by [PagedBookView].
typedef ParagraphDisplay = ({String text, bool heading});

/// Splits paragraphs [from]..[to) into pages of [size], measuring with
/// the same text style and scaler the pages are drawn with. Public for
/// tests.
List<BookPage> paginate({
  required List<int> paragraphs,
  required ParagraphDisplay? Function(int index) display,
  required Uint8List? Function(int index) imageAt,
  required Size size,
  required TextStyle style,
  required TextStyle Function(String text, bool heading) styleFor,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  final pages = <BookPage>[];
  var current = <PageSlice>[];
  var used = 0.0;
  final spacing = (style.fontSize ?? 16) * 0.7;

  void flush() {
    if (current.isNotEmpty) pages.add(BookPage(current));
    current = <PageSlice>[];
    used = 0;
  }

  for (final index in paragraphs) {
    final image = imageAt(index);
    if (image != null) {
      flush();
      pages.add(BookPage([PageSlice(paragraph: index, image: image)]));
      continue;
    }
    final shown = display(index);
    if (shown == null || shown.text.trim().isEmpty) continue;
    final text = shown.text;
    final textStyle = styleFor(text, shown.heading);
    final painter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout(maxWidth: size.width);
    final lines = painter.computeLineMetrics();
    if (lines.isEmpty) continue;

    // Character range of each line.
    final ranges = <TextRange>[];
    for (final line in lines) {
      final pos = painter
          .getPositionForOffset(Offset(1, line.baseline - line.ascent / 2));
      ranges.add(painter.getLineBoundary(pos));
    }

    var lineIndex = 0;
    var sliceStart = 0;
    while (lineIndex < lines.length) {
      var fit = 0;
      var height = 0.0;
      while (lineIndex + fit < lines.length &&
          used + height + lines[lineIndex + fit].height <= size.height) {
        height += lines[lineIndex + fit].height;
        fit++;
      }
      if (fit == 0) {
        if (current.isNotEmpty) {
          flush();
          continue;
        }
        // A line taller than the page (huge font): it gets a page alone.
        fit = 1;
        height = lines[lineIndex].height;
      }
      final last = lineIndex + fit - 1;
      final end = last == lines.length - 1
          ? text.length
          : math.max(ranges[last].end, sliceStart);
      final slice = text.substring(sliceStart, end).trimLeft();
      final ends = last == lines.length - 1;
      if (slice.isNotEmpty) {
        current.add(PageSlice(
          paragraph: index,
          text: slice,
          heading: shown.heading,
          endsParagraph: ends,
        ));
      }
      used += height;
      sliceStart = end;
      lineIndex = last + 1;
      if (!ends) flush();
    }
    used += spacing;
    if (used >= size.height) flush();
  }
  flush();
  return pages;
}

/// The page-turning view.
class PagedBookView extends StatefulWidget {
  const PagedBookView({
    super.key,
    required this.book,
    required this.paragraphs,
    required this.layout,
    required this.textStyle,
    required this.styleFor,
    required this.initialParagraph,
    required this.onParagraphChanged,
    required this.translationOf,
    this.onPageShown,
    this.revision = 0,
  });

  final EpubBook book;
  final List<Paragraph> paragraphs;
  final ReaderLayout layout;
  final TextStyle textStyle;

  /// The style for a piece of text (font per script).
  final TextStyle Function(String text, bool heading) styleFor;
  final int initialParagraph;
  final ValueChanged<int> onParagraphChanged;

  /// The translation to show for paragraph [index], or null for the
  /// original.
  final String? Function(int index) translationOf;

  /// Called with the paragraphs on screen, so their translation can be
  /// requested first.
  final void Function(int firstParagraph, int lastParagraph)? onPageShown;

  /// Bump to re-lay-out (new translations, font change).
  final int revision;

  @override
  State<PagedBookView> createState() => PagedBookViewState();
}

class PagedBookViewState extends State<PagedBookView> {
  static const _padding = EdgeInsets.fromLTRB(22, 18, 22, 22);

  late List<({int start, int end})> _chapters = _chapterRanges();
  int _chapter = 0;
  List<BookPage> _pages = const [];
  PageController? _controller;
  int _anchorParagraph = 0;
  Size? _laidOutFor;
  int _laidOutRevision = -1;
  double _laidOutFont = 0;

  bool get _hasPrev => _chapter > 0;
  bool get _hasNext => _chapter < _chapters.length - 1;
  int get _offset => _hasPrev ? 1 : 0;

  List<({int start, int end})> _chapterRanges() {
    final ranges = <({int start, int end})>[];
    final ps = widget.paragraphs;
    var start = 0;
    for (var i = 1; i <= ps.length; i++) {
      if (i == ps.length || ps[i].chapterIndex != ps[start].chapterIndex) {
        ranges.add((start: start, end: i));
        start = i;
      }
    }
    return ranges.isEmpty ? [(start: 0, end: 0)] : ranges;
  }

  int _chapterOf(int paragraph) {
    for (var c = 0; c < _chapters.length; c++) {
      if (paragraph < _chapters[c].end) return c;
    }
    return _chapters.length - 1;
  }

  @override
  void initState() {
    super.initState();
    _anchorParagraph = widget.initialParagraph
        .clamp(0, math.max(0, widget.paragraphs.length - 1));
    _chapter = _chapterOf(_anchorParagraph);
  }

  @override
  void didUpdateWidget(covariant PagedBookView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.paragraphs, widget.paragraphs)) {
      _chapters = _chapterRanges();
      _laidOutFor = null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Uint8List? _imageAt(int index) {
    final element = widget.paragraphs[index].element;
    if (!containsImage(element)) return null;
    final img = element.localName == 'img'
        ? element
        : element.querySelector('img, image');
    final src = (img?.attributes['src'] ??
            img?.attributes['xlink:href'] ??
            img?.attributes['href'] ??
            '')
        .replaceAll('../', '');
    final bytes = widget.book.Content?.Images?[src]?.Content;
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  ParagraphDisplay? _display(int index) {
    final element = widget.paragraphs[index].element;
    final tag = element.localName?.toLowerCase() ?? '';
    final heading = RegExp(r'^h[1-6]$').hasMatch(tag);
    final translation = widget.translationOf(index);
    final text = translation ?? paragraphText(element);
    if (text.isEmpty) return null;
    return (text: text, heading: heading);
  }

  void _layout(Size size) {
    final range = _chapters[_chapter];
    _pages = paginate(
      paragraphs: [for (var i = range.start; i < range.end; i++) i],
      display: _display,
      imageAt: _imageAt,
      size: Size(
          size.width - _padding.horizontal, size.height - _padding.vertical),
      style: widget.textStyle,
      styleFor: widget.styleFor,
      textScaler: MediaQuery.textScalerOf(context),
    );
    if (_pages.isEmpty) {
      _pages = [
        BookPage([PageSlice(paragraph: range.start)])
      ];
    }
    _laidOutFor = size;
    _laidOutRevision = widget.revision;
    _laidOutFont = widget.textStyle.fontSize ?? 0;

    var page =
        _pages.lastIndexWhere((p) => p.firstParagraph <= _anchorParagraph);
    if (page < 0) page = 0;
    _controller?.dispose();
    _controller = PageController(initialPage: page + _offset);
    WidgetsBinding.instance.addPostFrameCallback((_) => _report(page));
  }

  void _report(int page) {
    if (page < 0 || page >= _pages.length) return;
    final p = _pages[page];
    widget.onParagraphChanged(p.firstParagraph);
    widget.onPageShown?.call(p.firstParagraph, p.slices.last.paragraph);
  }

  void _onPageChanged(int index) {
    if (_hasPrev && index == 0) {
      setState(() {
        _chapter--;
        _anchorParagraph = _chapters[_chapter].end - 1;
        _laidOutFor = null;
      });
      return;
    }
    final page = index - _offset;
    if (_hasNext && page == _pages.length) {
      setState(() {
        _chapter++;
        _anchorParagraph = _chapters[_chapter].start;
        _laidOutFor = null;
      });
      return;
    }
    _anchorParagraph = _pages[page].firstParagraph;
    _report(page);
  }

  void turn(int delta) {
    final c = _controller;
    if (c == null || !c.hasClients) return;
    final target = (c.page ?? c.initialPage.toDouble()).round() + delta;
    c.animateToPage(target,
        duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
  }

  Widget _buildPage(BuildContext context, BookPage page) {
    final first = page.slices.first;
    if (first.image != null) {
      return Padding(
        padding: _padding,
        child: Center(child: Image.memory(first.image!, fit: BoxFit.contain)),
      );
    }
    final spacing = (widget.textStyle.fontSize ?? 16) * 0.7;
    return Padding(
      padding: _padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final slice in page.slices) ...[
            Text(
              slice.text,
              style: widget.styleFor(slice.text, slice.heading),
              textDirection: TextDirection.ltr,
            ),
            if (slice.endsParagraph) SizedBox(height: spacing),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rtl = widget.layout == ReaderLayout.pagesRtl;
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      if (_laidOutFor != size ||
          _laidOutRevision != widget.revision ||
          _laidOutFont != (widget.textStyle.fontSize ?? 0)) {
        _layout(size);
      }
      final count = _pages.length + _offset + (_hasNext ? 1 : 0);
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapUp: (details) {
          final x = details.localPosition.dx / size.width;
          if (x < 0.3) turn(rtl ? 1 : -1);
          if (x > 0.7) turn(rtl ? -1 : 1);
        },
        child: PageView.builder(
          key: ValueKey('pages-$_chapter-${widget.layout.name}'),
          controller: _controller,
          reverse: rtl,
          itemCount: count,
          onPageChanged: _onPageChanged,
          itemBuilder: (context, index) {
            final page = index - _offset;
            if (page < 0 || page >= _pages.length) {
              // Edge of a chapter: the next one loads as this settles.
              return const Center(child: CircularProgressIndicator());
            }
            return _buildPage(context, _pages[page]);
          },
        ),
      );
    });
  }
}
