// A name set right in the glossary, and what was already translated with
// the wrong one: those paragraphs are marked and count as not translated
// until they are made again; the rest of the book's translations stay.

// Dart imports:
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// Package imports:
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/services/translation/paragraph_text.dart';
import 'package:openlib/services/translation/translation_cache.dart';
import 'package:openlib/services/translation/translation_repair.dart';

Uint8List _epub(List<String> paragraphs) {
  final archive = Archive();
  void add(String name, String text) {
    final bytes = utf8.encode(text);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add('mimetype', 'application/epub+zip');
  add('META-INF/container.xml',
      '<?xml version="1.0"?><container><rootfiles><rootfile full-path="OEBPS/book.opf"/></rootfiles></container>');
  add('OEBPS/book.opf',
      '<?xml version="1.0"?><package><metadata><dc:title>テスト</dc:title></metadata>'
      '<manifest><item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/></manifest>'
      '<spine><itemref idref="c1"/></spine></package>');
  add('OEBPS/c1.xhtml',
      '<?xml version="1.0" encoding="UTF-8"?><html xmlns="http://www.w3.org/1999/xhtml"><body>'
      '${paragraphs.map((p) => '<p>$p</p>').join()}</body></html>');
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  late Directory dir;
  late String book;
  const witch = '花の魔女は笑った。';
  const blue = '青の魔女が来た。';
  const other = '今日はいい天気だった。';

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('redo');
    book = '${dir.path}/book.epub';
    File(book).writeAsBytesSync(_epub([witch, blue, other]));
    final paragraphs = epubReaderParagraphs(File(book).readAsBytesSync())!;
    expect(paragraphs, [witch, blue, other]);
    final cache = await TranslationCache.open(
        bookFileName: 'book.epub',
        targetLanguage: 'Korean',
        modelId: TranslationCache.sharedModelId(lightNovel: true),
        directory: dir);
    cache
      ..store(witch, '꽃의 푸른마녀는 웃었다.')
      ..store(blue, '푸른 마녀가 왔다.')
      ..store(other, '오늘은 날씨가 좋았다.');
    await cache.flush();
  });

  tearDown(() {
    for (final path in [
      for (final f in dir.listSync())
        if (f.path.endsWith('.json')) f.path,
    ]) {
      TranslationCache.isOpen(path);
    }
    dir.deleteSync(recursive: true);
  });

  Future<TranslationCache> open() => TranslationCache.open(
      bookFileName: 'book.epub',
      targetLanguage: 'Korean',
      modelId: TranslationCache.sharedModelId(lightNovel: true),
      directory: dir);

  test('written the old way: made again; the others stay', () async {
    var told = 0;
    onTranslationsToRedo = () => told++;
    addTearDown(() => onTranslationsToRedo = null);
    final marked = await redoTranslationsWith(
        bookFile: 'book.epub',
        bookPath: book,
        source: '魔女',
        written: '푸른마녀',
        directory: dir);
    expect(marked, 1);
    expect(told, 1);
    final cache = await open();
    expect(cache.lookup(witch), isNull, reason: 'counts as not translated');
    expect(cache.saved(witch), '꽃의 푸른마녀는 웃었다.');
    expect(cache.lookup(blue), '푸른 마녀가 왔다.');
    expect(cache.lookup(other), isNotNull);
    expect(cache.toRedo, 1);
    // What sync sends is unchanged: nothing was removed.
    expect(cache.entries, hasLength(3));

    // Translated again: the mark is gone.
    cache.store(witch, '꽃의 마녀는 웃었다.');
    await cache.flush();
    expect(cache.lookup(witch), '꽃의 마녀는 웃었다.');
    expect(cache.toRedo, 0);
    expect(File('${cache.path}.redo').existsSync(), isFalse);
  });

  test('every paragraph with the word, when the reader asks; kept across '
      'a restart', () async {
    final marked = await redoTranslationsWith(
        bookFile: 'book.epub', bookPath: book, source: '魔女', directory: dir);
    expect(marked, 2);
    final cache = await open();
    expect(File('${cache.path}.redo').existsSync(), isTrue);
    // (As after the app was closed.)
    cache.forget();
    final again = await open();
    expect(again.lookup(witch), isNull);
    expect(again.lookup(blue), isNull);
    expect(again.lookup(other), isNotNull);
    // Asked twice: nothing new to mark.
    expect(
        await redoTranslationsWith(
            bookFile: 'book.epub',
            bookPath: book,
            source: '魔女',
            directory: dir),
        0);
  });

  test('a word the book does not have, or a form nothing was written '
      'with: nothing is marked', () async {
    expect(
        await redoTranslationsWith(
            bookFile: 'book.epub', bookPath: book, source: '勇者', directory: dir),
        0);
    expect(
        await redoTranslationsWith(
            bookFile: 'book.epub',
            bookPath: book,
            source: '魔女',
            written: '위치',
            directory: dir),
        0);
    expect((await open()).toRedo, 0);
  });
}
