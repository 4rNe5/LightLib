// Where the app keeps its own files: real files on devices, IndexedDB on
// the web (here on idb_shim's in-memory IndexedDB).

// Dart imports:
import 'dart:io';

// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';

// Project imports:
import 'package:openlib/services/storage/app_files.dart';
import 'package:openlib/services/storage/app_files_io.dart';
import 'package:openlib/services/storage/idb_app_files.dart';
import 'package:openlib/services/translation/translation_cache.dart';

void main() {
  group('IndexedDB (web)', () {
    late IdbAppFiles files;
    setUp(() => files = IdbAppFiles(newIdbFactoryMemory()));

    test('writes, reads, replaces and deletes by path', () async {
      expect(await files.exists('/books/a.epub'), isFalse);
      expect(await files.readBytes('/books/a.epub'), isNull);
      await files.writeBytes('/books/a.epub', [1, 2, 3]);
      expect(await files.exists('/books/a.epub'), isTrue);
      expect(await files.readBytes('/books/a.epub'), [1, 2, 3]);
      await files.writeString('/books/a.epub', '春');
      expect(await files.readString('/books/a.epub'), '春');
      await files.delete('/books/a.epub');
      expect(await files.exists('/books/a.epub'), isFalse);
    });

    test('lists one folder, not its subfolders or neighbours', () async {
      await files.writeString('/translations/x.json', '{}');
      await files.writeString('/translations/y.json', '{}');
      await files.writeString('/translations/old/z.json', '{}');
      await files.writeString('/translationsX/w.json', '{}');
      expect((await files.list('/translations'))..sort(),
          ['/translations/x.json', '/translations/y.json']);
    });
  });

  group('files (devices)', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('app_files'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('writes in one step and lists without temp files', () async {
      final files = IoAppFiles(root: dir.path);
      final path = '${dir.path}/deep/folder/a.json';
      await files.writeString(path, 'one');
      expect(await files.readString(path), 'one');
      expect(await files.list('${dir.path}/deep/folder'), [path]);
      expect(await files.supportPath(), dir.path);
    });
  });

  group('translation sets on the web store', () {
    final original = AppFiles.instance;
    tearDown(() {
      AppFiles.instance = original;
      TranslationCache.onChanged = null;
    });

    test('kept, reopened, and a write reported unless sync made it', () async {
      AppFiles.instance = IdbAppFiles(newIdbFactoryMemory(), name: 'tc');
      final changed = <String>[];
      TranslationCache.onChanged = changed.add;
      final dir = Directory('/web-test-translations');

      final cache = await TranslationCache.open(
          bookFileName: 'b.epub',
          targetLanguage: 'ko',
          modelId: 'shared',
          directory: dir);
      cache.store('一', 'one');
      await cache.flush();
      expect(changed, [cache.path]);

      expect(cache.absorb({'x': 'from elsewhere'}), 1);
      await cache.flush(quiet: true);
      expect(changed.length, 1);

      cache.forget();
      final again = await TranslationCache.open(
          bookFileName: 'b.epub',
          targetLanguage: 'ko',
          modelId: 'shared',
          directory: dir);
      expect(identical(again, cache), isFalse);
      expect(again.lookup('一'), 'one');
      expect(again.entries['x'], 'from elsewhere');
    });
  });
}
