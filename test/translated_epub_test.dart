// The translated copy of an EPUB: paragraphs replaced from the cache,
// the rest kept, still a valid EPUB in the target language, horizontal.

// Dart imports:
import 'dart:convert';
import 'dart:typed_data';

// Package imports:
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/services/epub_package.dart';
import 'package:openlib/services/translation/paragraph_text.dart';
import 'package:openlib/services/translation/translated_epub.dart';
import 'package:openlib/services/translation/translation_cache.dart';

Uint8List _epub() {
  final a = Archive()
    ..add(ArchiveFile.bytes('mimetype', ascii.encode('application/epub+zip')))
    ..add(ArchiveFile.string('META-INF/container.xml',
        '<?xml version="1.0"?><container><rootfiles><rootfile full-path="OEBPS/book.opf"/></rootfiles></container>'))
    ..add(ArchiveFile.string(
        'OEBPS/book.opf',
        '<?xml version="1.0"?><package><metadata><dc:title>テスト</dc:title>'
            '<dc:language>ja</dc:language><meta name="primary-writing-mode" content="vertical-rl"/></metadata>'
            '<manifest><item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/></manifest>'
            '<spine page-progression-direction="rtl"><itemref idref="c1"/></spine></package>'))
    ..add(ArchiveFile.string(
        'OEBPS/c1.xhtml',
        '<?xml version="1.0" encoding="UTF-8"?>\r\n<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="ja">\r\n'
            '<head><title>t</title><script src="x.js"/></head>\r\n<body>\r\n'
            '<p class="a">　<ruby>和希<rt>かずき</rt></ruby>は言った。</p>\r\n'
            '<p>「行こう」</p>\r\n<p><img src="i.png"/></p>\r\n<p>未訳の段落。</p>\r\n'
            '</body></html>'))
    ..add(ArchiveFile.string('OEBPS/i.png', 'png'));
  return ZipEncoder().encodeBytes(a);
}

void main() {
  test('paragraphs replaced, the rest kept, the book marked and laid out '
      'for the translation', () {
    final bytes = _epub();
    final paragraphs = epubReaderParagraphs(bytes)!;
    expect(paragraphs.length, 3);
    final translations = {
      TranslationCache.keyFor(paragraphs[0]): '카즈키는 말했다. <A&B>',
      TranslationCache.keyFor(paragraphs[1]): '“가자”\n“응”',
    };
    final out = buildTranslatedEpub(bytes, translations,
        languageCode: 'ko', titleSuffix: ' (한국어)')!;
    expect(out.translated, 2);
    expect(out.total, 3);

    final zip = ZipDecoder().decodeBytes(out.bytes);
    expect(zip.files.first.name, 'mimetype');
    expect(zip.files.first.compression, CompressionType.none);
    expect(zip.files.length, 5);

    final book = EpubPackage.open(out.bytes)!;
    final xhtml = book.text('OEBPS/c1.xhtml')!;
    expect(xhtml, contains('<p class="a">카즈키는 말했다. &lt;A&amp;B&gt;</p>'));
    expect(xhtml, contains('<p>“가자”<br/>“응”</p>'));
    expect(xhtml, contains('<p>未訳の段落。</p>'));
    expect(xhtml, contains('<img src="i.png"/>'));
    expect(xhtml, contains('xml:lang="ko"'));
    expect(xhtml, contains('writing-mode: horizontal-tb'));
    expect(book.opf, contains('<dc:title>テスト (한국어)</dc:title>'));
    expect(book.opf, contains('<dc:language>ko</dc:language>'));
    expect(book.opf, contains('page-progression-direction="ltr"'));
    expect(book.opf, contains('content="horizontal-lr"'));

    // Read again, the translated paragraphs are what the reader finds.
    expect(epubReaderParagraphs(out.bytes),
        ['카즈키는 말했다. <A&B>', '“가자”\n“응”', '未訳の段落。']);
  });

  test('not an EPUB: nothing', () {
    expect(
        buildTranslatedEpub(Uint8List.fromList([1, 2, 3]), const {},
            languageCode: 'ko'),
        isNull);
  });
}
