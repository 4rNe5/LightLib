// What the book reader's web view is served, and how its saved positions
// are told apart from the older reader's.

// Dart imports:
import 'dart:convert';
import 'dart:io';

// Flutter imports:
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/ui/book_reader_page.dart';

class _Bundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key == 'assets/reader/index.html') {
      return ByteData.sublistView(utf8.encode('<html></html>'));
    }
    if (key == 'assets/reader/reader.js') {
      return ByteData.sublistView(utf8.encode('export {}'));
    }
    throw StateError('missing $key');
  }
}

void main() {
  late Directory dir;
  late ReaderResources resources;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('reader_res');
    File('${dir.path}/book.epub').writeAsBytesSync([80, 75, 3, 4]);
    File('${dir.path}/MyFont.ttf').writeAsBytesSync([0, 1, 0, 0]);
    resources =
        ReaderResources(bookPath: '${dir.path}/book.epub', bundle: _Bundle());
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('serves the page, the book and registered fonts', () async {
    const base = 'https://appassets.androidplatform.net/reader';
    final page = await resources.resolve(Uri.parse('$base/index.html'));
    expect(page!.contentType, 'text/html');
    final script = await resources.resolve(Uri.parse('$base/reader.js'));
    expect(script!.contentType, 'text/javascript');

    final book = await resources.resolve(Uri.parse('$base/book'));
    expect(book!.contentType, 'application/epub+zip');
    expect(book.bytes, [80, 75, 3, 4]);

    final url = resources.addFont(File('${dir.path}/MyFont.ttf'));
    expect(url, endsWith('.ttf'));
    final font = await resources.resolve(Uri.parse(url));
    expect(font!.contentType, 'font/ttf');
    expect(font.bytes, [0, 1, 0, 0]);

    // The Apple custom scheme has no /reader prefix.
    final apple = await resources.resolve(Uri.parse('lightlib://reader/book'));
    expect(apple!.bytes, [80, 75, 3, 4]);

    // Nothing else, and no paths outside what it registered.
    expect(await resources.resolve(Uri.parse('$base/../secret')), isNull);
    expect(await resources.resolve(Uri.parse('$base/fonts/f9.ttf')), isNull);
    expect(await resources.resolve(Uri.parse('$base/other.js')), isNull);
  });

  test('a missing book file is not served', () async {
    final missing =
        ReaderResources(bookPath: '${dir.path}/nope.epub', bundle: _Bundle());
    expect(
        await missing.resolve(
            Uri.parse('https://appassets.androidplatform.net/reader/book')),
        isNull);
  });

  test('saved positions: only this reader\'s CFIs are resumed', () {
    expect(bookReaderCfi('foliate:epubcfi(/6/20!/4/2)'), 'epubcfi(/6/20!/4/2)');
    expect(bookReaderCfi('epubcfi(/6/4[chap01]!/4/2/1:0)'), isNull);
    expect(bookReaderCfi(''), isNull);
    expect(bookReaderCfi(null), isNull);
  });
}
