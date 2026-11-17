// The small cover a device sends of a book: a book downloaded in the app
// keeps a web address for its cover (the catalog's), and nothing was sent
// for it - the owner's phone sent 8 covers of 22 books. The picture is
// the book's own, read out of its file.

// Dart imports:
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// Package imports:
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/sync/library_sync_local.dart';
import 'package:openlib/services/sync/sync_engine.dart';

late Directory _root;

class _FakePathProvider extends PathProviderPlatform {
  Future<String> _dir(String name) async {
    final dir = Directory('${_root.path}/$name');
    await dir.create(recursive: true);
    return dir.path;
  }

  @override
  Future<String?> getApplicationSupportPath() => _dir('support');
  @override
  Future<String?> getApplicationDocumentsPath() => _dir('documents');
  @override
  Future<String?> getTemporaryPath() => _dir('temp');
}

Uint8List _picture(int width, int height, int shade) {
  final picture = img.Image(width: width, height: height);
  img.fill(picture, color: img.ColorRgb8(shade, 80, 160));
  return Uint8List.fromList(img.encodeJpg(picture, quality: 90));
}

Uint8List _epub({Uint8List? cover}) {
  final archive = Archive()
    ..addFile(ArchiveFile.noCompress(
        'mimetype', 20, utf8.encode('application/epub+zip')))
    ..addFile(ArchiveFile.string('META-INF/container.xml', '''
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
<rootfiles><rootfile full-path="item/standard.opf" media-type="application/oebps-package+xml"/></rootfiles></container>'''))
    ..addFile(ArchiveFile.string('item/standard.opf', '''
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>春の駅</dc:title></metadata>
<manifest>
<item id="p1" href="xhtml/p-001.xhtml" media-type="application/xhtml+xml"/>
${cover == null ? '' : '<item id="cover" href="image/cover.jpg" media-type="image/jpeg" properties="cover-image"/>'}
</manifest>
<spine><itemref idref="p1"/></spine>
</package>'''))
    ..addFile(ArchiveFile.string(
        'item/xhtml/p-001.xhtml', '<html><body><p>本文。</p></body></html>'));
  if (cover != null) {
    archive.addFile(
        ArchiveFile.noCompress('item/image/cover.jpg', cover.length, cover));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory storage;
  final db = MyLibraryDb.instance;

  setUpAll(() async {
    _root = await Directory.systemTemp.createTemp('lsynccover');
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    PathProviderPlatform.instance = _FakePathProvider();
    storage = Directory('${_root.path}/books')..createSync();
    await db.savePreference('bookStorageDirectory', storage.path);
  });

  tearDownAll(() async => _root.delete(recursive: true));

  Future<LocalBook> add(String id, Uint8List file, String thumbnail) async {
    final fileName = '$id.epub';
    File('${storage.path}/$fileName').writeAsBytesSync(file);
    await db.insert(MyBook(
        id: id,
        title: '春の駅',
        author: '水無月 蒼',
        thumbnail: thumbnail,
        link: '',
        publisher: null,
        info: null,
        format: 'epub',
        description: null,
        fileName: fileName));
    return LocalBook(id: id, fileName: fileName, title: '春の駅', format: 'epub');
  }

  test('a web address for a cover: the book\'s own cover is sent', () async {
    final book = await add('a' * 32, _epub(cover: _picture(900, 1280, 200)),
        'https://catalog.example/covers/1.jpg');
    final jpeg = await LibrarySyncLocal().coverThumbnail(book);
    expect(jpeg, isNotNull);
    final small = img.decodeJpg(jpeg!)!;
    expect(small.width, 600);
    expect(small.height, closeTo(853, 1));
    final centre = small.getPixel(300, 400);
    expect(centre.r, closeTo(200, 6));
  });

  test('no cover saved at all: the same', () async {
    final book = await add('b' * 32, _epub(cover: _picture(400, 560, 90)), '');
    final jpeg = await LibrarySyncLocal().coverThumbnail(book);
    expect(img.decodeJpg(jpeg!)!.width, 400);
  });

  test('a cover saved on the device is the one sent', () async {
    final saved = File('${_root.path}/saved.jpg')
      ..writeAsBytesSync(_picture(300, 420, 30));
    final book = await add(
        'c' * 32, _epub(cover: _picture(900, 1280, 200)), saved.path);
    final small = img.decodeJpg((await LibrarySyncLocal().coverThumbnail(book))!)!;
    expect(small.width, 300);
    expect(small.getPixel(150, 200).r, closeTo(30, 6));
  });

  test('a file without a cover is opened for it once', () async {
    final book = await add('d' * 32, _epub(), 'https://catalog.example/2.jpg');
    final local = LibrarySyncLocal();
    expect(await local.coverThumbnail(book), isNull);
    expect(await db.getSyncState('nocover:${book.fileName}'), '1');
    // A cover the file gains later would not be looked for: the mark says
    // the file was read.
    File('${storage.path}/${book.fileName}')
        .writeAsBytesSync(_epub(cover: _picture(300, 420, 30)));
    expect(await local.coverThumbnail(book), isNull);
  });
}
