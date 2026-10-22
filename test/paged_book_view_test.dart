// Pagination: pages never overflow, nothing is lost or duplicated, images
// get pages of their own; and the page view turns pages.

// Dart imports:
import 'dart:typed_data';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/services/reader_fonts.dart';
import 'package:openlib/ui/components/paged_book_view.dart';

void main() {
  const style = TextStyle(fontSize: 16, height: 1.5);
  final texts = [
    for (var i = 0; i < 30; i++)
      List.filled(8 + (i % 5) * 6, 'word$i').join(' '),
  ];

  List<BookPage> run(Size size, {Set<int> images = const {}}) => paginate(
        paragraphs: [for (var i = 0; i < texts.length; i++) i],
        display: (i) =>
            images.contains(i) ? null : (text: texts[i], heading: false),
        imageAt: (i) => images.contains(i) ? Uint8List(4) : null,
        size: size,
        style: style,
        styleFor: (_, __) => style,
      );

  testWidgets('every word lands on exactly one page, in order', (tester) async {
    final pages = run(const Size(300, 400));
    expect(pages.length, greaterThan(3));
    final joined = <String>[];
    for (final page in pages) {
      for (final slice in page.slices) {
        joined.addAll(
            slice.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty));
      }
    }
    final expected = texts.expand((t) => t.split(' ')).toList();
    expect(joined, expected);
  });

  testWidgets('no page is taller than the page', (tester) async {
    const size = Size(280, 360);
    for (final page in run(size)) {
      var height = 0.0;
      for (final slice in page.slices) {
        final painter = TextPainter(
          text: TextSpan(text: slice.text, style: style),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: size.width);
        height += painter.height;
      }
      expect(height, lessThanOrEqualTo(size.height + 0.5));
    }
  });

  testWidgets('images get their own page', (tester) async {
    final pages = run(const Size(300, 400), images: {5});
    final imagePages =
        pages.where((p) => p.slices.first.image != null).toList();
    expect(imagePages.length, 1);
    expect(imagePages.single.slices.length, 1);
    expect(imagePages.single.firstParagraph, 5);
  });

  test('layout names round-trip', () {
    for (final layout in ReaderLayout.values) {
      expect(ReaderLayout.fromName(layout.name), layout);
    }
    expect(ReaderLayout.fromName(null), ReaderLayout.scroll);
    expect(ReaderLayout.pagesRtl.paged, isTrue);
  });

  test('scripts are told apart for font choice', () {
    expect(scriptOf('그날, 모든 게'), FontScript.korean);
    expect(scriptOf('その日、全てが'), FontScript.japanese);
    expect(scriptOf('第一章'), FontScript.japanese);
    expect(scriptOf('第一章', hanAs: FontScript.korean), FontScript.korean);
    expect(scriptOf('Chapter 1'), FontScript.latin);
    expect(ReaderFonts.scriptForLanguage('ja-JP'), FontScript.japanese);
    expect(ReaderFonts.scriptForLanguage('kor'), FontScript.korean);
    expect(ReaderFonts.scriptForLanguage(null), FontScript.latin);
  });
}
