// Covers read out of EPUB files: each way a book names its cover, kept at
// full quality, re-encoded only when huge.

// Dart imports:
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// Package imports:
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

// Project imports:
import 'package:openlib/services/book_covers.dart';

Uint8List _jpeg(int w, int h) =>
    Uint8List.fromList(img.encodeJpg(img.Image(width: w, height: h)));

Uint8List _epub(Map<String, Object> files) {
  final archive = Archive();
  files.forEach((name, content) {
    final bytes =
        content is String ? utf8.encode(content) : content as List<int>;
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

const _container = '<?xml version="1.0"?><container version="1.0" '
    'xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles>'
    '<rootfile full-path="OEBPS/content.opf" '
    'media-type="application/oebps-package+xml"/></rootfiles></container>';

String _opf({String manifest = '', String meta = '', String spine = ''}) =>
    '<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" '
    'version="3.0"><metadata>$meta</metadata><manifest>$manifest</manifest>'
    '<spine>$spine</spine></package>';

void main() {
  test('EPUB 3 cover-image is kept byte for byte', () {
    final cover = _jpeg(1434, 2048);
    final book = _epub({
      'META-INF/container.xml': _container,
      'OEBPS/content.opf': _opf(
        manifest: '<item id="a" href="Images/a.jpg" media-type="image/jpeg"/>'
            '<item id="c" href="Images/embed0016_HD.jpg" '
            'properties="cover-image" media-type="image/jpeg"/>',
      ),
      'OEBPS/Images/a.jpg': _jpeg(10, 10),
      'OEBPS/Images/embed0016_HD.jpg': cover,
    });
    final found = epubCover(book)!;
    expect(found.extension, 'jpg');
    expect(found.bytes, cover);
  });

  test('EPUB 2 cover meta', () {
    final cover = _jpeg(600, 900);
    final book = _epub({
      'META-INF/container.xml': _container,
      'OEBPS/content.opf': _opf(
        meta: '<meta name="cover" content="img1"/>',
        manifest:
            '<item id="img1" href="cov%20er.jpg" media-type="image/jpeg"/>',
      ),
      'OEBPS/cov er.jpg': cover,
    });
    expect(epubCover(book)!.bytes, cover);
  });

  test('the first page picture, an SVG <image> in a cover page', () {
    final cover = _jpeg(500, 700);
    final book = _epub({
      'META-INF/container.xml': _container,
      'OEBPS/content.opf': _opf(
        manifest: '<item id="p" href="Text/p-cover.xhtml" '
            'media-type="application/xhtml+xml"/>'
            '<item id="i" href="Images/x.jpg" media-type="image/jpeg"/>',
        spine: '<itemref idref="p"/>',
      ),
      'OEBPS/Text/p-cover.xhtml': '<html><body><svg><image width="1" '
          'height="1" xlink:href="../Images/x.jpg"/></svg></body></html>',
      'OEBPS/Images/x.jpg': cover,
    });
    expect(epubCover(book)!.bytes, cover);
  });

  test('a huge cover is scaled down once, a book without one has none', () {
    final book = _epub({
      'META-INF/container.xml': _container,
      'OEBPS/content.opf': _opf(
        manifest: '<item id="c" href="c.jpg" properties="cover-image" '
            'media-type="image/jpeg"/>',
      ),
      'OEBPS/c.jpg': _jpeg(3000, 4500),
    });
    final found = epubCover(book)!;
    final decoded = img.decodeJpg(found.bytes)!;
    expect(decoded.height, maxCoverSide);
    expect(decoded.width, 1600);

    expect(
        epubCover(_epub({
          'META-INF/container.xml': _container,
          'OEBPS/content.opf': _opf(),
        })),
        isNull);
    expect(epubCover(Uint8List.fromList([1, 2, 3])), isNull);
  });

  test('a real light novel (local file, when present)', () {
    final path = Platform.environment['COVER_EPUB'];
    if (path == null) return;
    final found = epubCover(File(path).readAsBytesSync())!;
    final decoded = img.decodeImage(found.bytes)!;
    // ignore: avoid_print
    print('cover ${found.extension} ${decoded.width}x${decoded.height} '
        '${found.bytes.length} bytes');
    expect(decoded.height, greaterThanOrEqualTo(1500));
  });
}
