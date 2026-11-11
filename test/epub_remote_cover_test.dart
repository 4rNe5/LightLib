// A book's cover read out of its EPUB where the file is kept (the
// account's storage) by fetching only the parts that hold it.

// Dart imports:
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

// Package imports:
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

// Project imports:
import 'package:openlib/services/epub_remote_cover.dart';

Uint8List jpeg(int width, int height, int shade) {
  final picture = img.Image(width: width, height: height);
  img.fill(picture, color: img.ColorRgb8(shade, 80, 160));
  return Uint8List.fromList(img.encodeJpg(picture, quality: 90));
}

const container = '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>''';

String opf({String manifest = '', String meta = '', String guide = ''}) => '''
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:title>春の駅</dc:title><dc:creator>水無月 蒼</dc:creator>
<dc:publisher>テスト文庫</dc:publisher>
<dc:description>&lt;p&gt;静かな町の &amp;amp; 小さな奇跡。&lt;/p&gt;</dc:description>
$meta
</metadata>
<manifest>
<item id="c1" href="text/c1.xhtml" media-type="application/xhtml+xml"/>
<item id="c2" href="text/c2.xhtml" media-type="application/xhtml+xml"/>
$manifest
</manifest>
<spine><itemref idref="c1"/><itemref idref="c2"/></spine>
$guide
</package>''';

/// An EPUB whose text and pictures are far larger than its cover.
Uint8List epub(String opf, Map<String, List<int>> extra, {int padding = 600}) {
  final random = Random(3);
  final archive = Archive()
    ..addFile(ArchiveFile.noCompress(
        'mimetype', 20, utf8.encode('application/epub+zip')))
    ..addFile(ArchiveFile.string('META-INF/container.xml', container))
    ..addFile(ArchiveFile.string('OEBPS/content.opf', opf))
    ..addFile(ArchiveFile.string('OEBPS/text/c2.xhtml',
        '<html><body>${'<p>本文。</p>' * 4000}</body></html>'));
  // Pictures in the book that are not its cover (stored, as zips keep them).
  final noise = Uint8List.fromList(
      List.generate(padding * 1024, (_) => random.nextInt(256)));
  archive.addFile(ArchiveFile.noCompress(
      'OEBPS/images/illustration.bin', noise.length, noise));
  extra.forEach((name, bytes) => archive.addFile(name.endsWith('.jpg')
      ? ArchiveFile.noCompress(name, bytes.length, bytes)
      : ArchiveFile.bytes(name, bytes)));
  if (!extra.containsKey('OEBPS/text/c1.xhtml')) {
    archive.addFile(ArchiveFile.string(
        'OEBPS/text/c1.xhtml', '<html><body><p>第一章</p></body></html>'));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  final cover = jpeg(600, 850, 200);

  /// Reads [file]'s card, counting what was fetched.
  Future<(RemoteEpubCard?, RemoteZip, int)> read(Uint8List file) async {
    var calls = 0;
    final zip = RemoteZip(file.length, (start, end) async {
      calls++;
      return Uint8List.sublistView(file, start, end);
    });
    return (await readEpubCard(zip), zip, calls);
  }

  test('EPUB 3: the cover-image, and a fraction of the file fetched', () async {
    final file = epub(
        opf(
            manifest:
                '<item id="cv" href="images/cover.jpg" media-type="image/jpeg" properties="cover-image"/>'),
        {'OEBPS/images/cover.jpg': cover});
    final (card, zip, calls) = await read(file);
    expect(card!.cover!.bytes, cover);
    expect(card.cover!.extension, 'jpg');
    expect(card.publisher, 'テスト文庫');
    expect(card.description, '静かな町の & 小さな奇跡。');
    // The directory, the package, the first page, the picture - not the
    // book.
    expect(zip.fetched, lessThan(file.length ~/ 5));
    expect(calls, lessThanOrEqualTo(6));
  });

  test('EPUB 2: the cover named in the metadata', () async {
    final file = epub(
        opf(
            meta: '<meta name="cover" content="cv"/>',
            manifest:
                '<item id="cv" href="images/front.jpg" media-type="image/jpeg"/>'),
        {'OEBPS/images/front.jpg': cover});
    expect((await read(file)).$1!.cover!.bytes, cover);
  });

  test('no hint in the package: the guide\'s cover page', () async {
    final file = epub(
        opf(
            manifest:
                '<item id="t" href="text/title.xhtml" media-type="application/xhtml+xml"/>'
                '<item id="i" href="images/p000.jpg" media-type="image/jpeg"/>',
            guide:
                '<guide><reference type="cover" href="text/title.xhtml"/></guide>'),
        {
          'OEBPS/text/title.xhtml': utf8.encode(
              '<html><body><img src="../images/p000.jpg"/></body></html>'),
          'OEBPS/images/p000.jpg': cover,
        });
    expect((await read(file)).$1!.cover!.bytes, cover);
  });

  test('no hint at all: the first page\'s picture', () async {
    final file = epub(
        opf(
            manifest:
                '<item id="i" href="images/p001.jpg" media-type="image/jpeg"/>'),
        {
          'OEBPS/text/c1.xhtml': utf8.encode(
              '<html><body><svg><image xlink:href="../images/p001.jpg"/></svg></body></html>'),
          'OEBPS/images/p001.jpg': cover,
        });
    expect((await read(file)).$1!.cover!.bytes, cover);
  });

  test('a book without a cover: its words still', () async {
    final (card, _, _) = await read(epub(opf(), {}));
    expect(card!.cover, isNull);
    expect(card.publisher, 'テスト文庫');
  });

  test('a directory larger than the first piece fetched', () async {
    final many = {
      for (var i = 0; i < 2500; i++)
        'OEBPS/images/page_${'$i'.padLeft(5, '0')}_of_the_book.txt': [i % 251],
      'OEBPS/images/cover.jpg': cover,
    };
    final file = epub(
        opf(
            manifest:
                '<item id="cv" href="images/cover.jpg" media-type="image/jpeg" properties="cover-image"/>'),
        many,
        padding: 50);
    final (card, zip, _) = await read(file);
    expect(card!.cover!.bytes, cover);
    expect((await zip.names()).length, greaterThan(2500));
  });

  test('not a zip, or a server that sends something else: an error', () async {
    final junk = Uint8List.fromList(List.filled(5000, 7));
    await expectLater(read(junk), throwsFormatException);

    final file = epub(opf(), {});
    final short = RemoteZip(
        file.length, (start, end) async => Uint8List.sublistView(file, 0, 10));
    await expectLater(readEpubCard(short), throwsStateError);
  });

  test('not an EPUB inside: nothing', () async {
    final archive = Archive()..addFile(ArchiveFile.string('readme.txt', 'hi'));
    final zip = Uint8List.fromList(ZipEncoder().encode(archive));
    expect((await read(zip)).$1, isNull);
  });
}
