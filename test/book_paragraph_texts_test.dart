// A book's paragraphs read for the library's translator: off the UI
// thread, from the file (a real isolate here, as on a device).

// Dart imports:
import 'dart:convert';
import 'dart:io';

// Package imports:
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/services/translation/book_translation_service.dart';

List<int> _epub() {
  final a = Archive()
    ..add(ArchiveFile.bytes('mimetype', ascii.encode('application/epub+zip')))
    ..add(ArchiveFile.string('META-INF/container.xml',
        '<?xml version="1.0"?><container><rootfiles><rootfile full-path="OEBPS/book.opf"/></rootfiles></container>'))
    ..add(ArchiveFile.string(
        'OEBPS/book.opf',
        '<?xml version="1.0"?><package><metadata><dc:title>t</dc:title>'
            '<dc:language>ja</dc:language></metadata>'
            '<manifest><item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/></manifest>'
            '<spine><itemref idref="c1"/></spine></package>'))
    ..add(ArchiveFile.string(
        'OEBPS/c1.xhtml',
        '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>t</title></head><body>'
            '<p>一つ目の段落。</p><p>＊＊＊</p>'
            '<p>いいのかな<img class="gaiji" src="g.png" alt="!!?"/></p>'
            '<p><img src="i.png" alt=""/></p></body></html>'));
  return ZipEncoder().encodeBytes(a);
}

void main() {
  test('read in an isolate from the file, split as the reader splits', () async {
    final dir = Directory.systemTemp.createTempSync('paragraphs');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/book.epub';
    File(path).writeAsBytesSync(_epub());
    expect(await epubParagraphTexts(path), ['一つ目の段落。', 'いいのかな!!?']);
    // A file that is not there: the caller hears of it.
    expect(epubParagraphTexts('${dir.path}/none.epub'), throwsA(anything));
  });
}
