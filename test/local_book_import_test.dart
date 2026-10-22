// Importing EPUB/PDF files from the device into the library.

// Dart imports:
import 'dart:io';

// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/local_book_import.dart';

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
  @override
  Future<String?> getLibraryPath() => _dir('library');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory storage;
  const epub = 'third_party/epubx/test/res/alicesAdventuresUnderGround.epub';

  setUpAll(() async {
    _root = await Directory.systemTemp.createTemp('limport');
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    PathProviderPlatform.instance = _FakePathProvider();
    storage = Directory('${_root.path}/books')..createSync();
    await MyLibraryDb.instance
        .savePreference('bookStorageDirectory', storage.path);
  });

  tearDownAll(() async => _root.delete(recursive: true));

  test('reads EPUB title, author and a cover', () async {
    final meta = await readEpubMetadataOfFile(epub);
    expect(meta.title, isNotNull);
    expect(meta.title!.toLowerCase(), contains('alice'));
    expect(meta.author, isNotNull);
  });

  test('imports an EPUB once, copies it and records it', () async {
    final importer = LocalBookImporter();
    final first = await importer.importOne(epub);
    expect(first.outcome, LocalImportOutcome.imported);

    final books = await MyLibraryDb.instance.getAll();
    final book = books.single;
    expect(book.id, startsWith(localBookIdPrefix));
    expect(book.format, 'epub');
    expect(book.link, isEmpty);
    expect(File('${storage.path}/${book.fileName}').existsSync(), isTrue);
    expect(File('${storage.path}/${book.fileName}').lengthSync(),
        File(epub).lengthSync());
    if (book.thumbnail!.isNotEmpty) {
      expect(isLocalImagePath(book.thumbnail), isTrue);
      expect(File(book.thumbnail!).existsSync(), isTrue);
    }

    final again = await importer.importOne(epub);
    expect(again.outcome, LocalImportOutcome.alreadyInLibrary);
    expect((await MyLibraryDb.instance.getAll()).length, 1);
  });

  test('refuses other file types', () async {
    final txt = File('${_root.path}/notes.txt')..writeAsStringSync('x');
    final result = await LocalBookImporter().importOne(txt.path);
    expect(result.outcome, LocalImportOutcome.failed);
  });

  test('isLocalImagePath tells files from URLs', () {
    expect(isLocalImagePath('/data/user/0/x/covers/a.png'), isTrue);
    expect(isLocalImagePath('file:///a.png'), isTrue);
    expect(isLocalImagePath('https://example.com/a.png'), isFalse);
    expect(isLocalImagePath(''), isFalse);
    expect(isLocalImagePath(null), isFalse);
  });
}
