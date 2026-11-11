// The small cover another device's library shows of a book.

// Dart imports:
import 'dart:typed_data';

// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:image/image.dart' as img;

// Project imports:
import 'package:openlib/services/cover_thumbs.dart';
import 'package:openlib/services/cover_thumbs_io.dart';
import 'package:openlib/services/storage/app_files.dart';
import 'package:openlib/services/storage/idb_app_files.dart';

void main() {
  Uint8List png(int width, int height) {
    final picture = img.Image(width: width, height: height);
    img.fill(picture, color: img.ColorRgb8(200, 40, 90));
    return Uint8List.fromList(img.encodePng(picture));
  }

  test('a large cover becomes a JPEG of the library\'s width', () {
    final small = scaledJpeg(png(1200, 1700), coverThumbWidth)!;
    expect(small.sublist(0, 3), [0xFF, 0xD8, 0xFF]);
    final decoded = img.decodeJpg(small)!;
    expect(decoded.width, coverThumbWidth);
    expect(decoded.height, 850);
    expect(small.length, lessThan(60 * 1024));
  });

  test('a small cover is not blown up', () {
    final decoded = img.decodeJpg(scaledJpeg(png(300, 420), coverThumbWidth)!)!;
    expect(decoded.width, 300);
    expect(decoded.height, 420);
  });

  test('what is not a picture gives nothing', () {
    expect(scaledJpeg(Uint8List.fromList([1, 2, 3, 4]), 600), isNull);
  });

  test('made off the UI thread, the same', () async {
    final small = await CoverThumbs.jpeg(png(900, 1200));
    expect(img.decodeJpg(small!)!.width, coverThumbWidth);
  });

  test('kept by the book\'s MD5, told apart from a full cover', () async {
    final files = AppFiles.instance;
    AppFiles.instance = IdbAppFiles(newIdbFactoryMemory());
    addTearDown(() => AppFiles.instance = files);
    const md5 = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    expect(await CoverThumbs.read(md5), isNull);
    await CoverThumbs.write(md5, Uint8List.fromList([9, 9]));
    expect(await CoverThumbs.read(md5), [9, 9]);
    expect(CoverThumbs.isThumb(await CoverThumbs.path(md5)), isTrue);
    expect(CoverThumbs.isThumb('/support/covers/local_$md5.jpg'), isFalse);
    await CoverThumbs.remove(md5);
    expect(await CoverThumbs.read(md5), isNull);
  });
}
