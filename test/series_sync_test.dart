// Series between devices: the shared map (a book's MD5 → its series)
// and what a device does with it - the reader's changes written into
// it, what arrives applied to the books here, what only this device
// knew kept.

// Dart imports:
import 'dart:io';

// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/sync/library_sync_local.dart';
import 'package:openlib/services/sync/series_sync.dart';
import 'package:openlib/services/translation/claude/claude_settings.dart';
import 'package:openlib/services/translation/gemini/gemini_settings.dart';

class _FakePathProvider extends PathProviderPlatform {
  Future<String> _dir(String name) async {
    final dir = Directory('/tmp/openlib_series_sync_test/$name');
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

const a = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const b = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const c = 'cccccccccccccccccccccccccccccccc';
const elsewhere = 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';

MyBook _book(String md5, String title) => MyBook(
      id: md5,
      title: title,
      author: null,
      thumbnail: null,
      link: 'https://example.com/$md5',
      publisher: null,
      info: null,
      format: 'epub',
      description: null,
      fileName: '$md5.epub',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the map as text: the same whatever order it was made in', () {
    expect(encodeSeries({b: 'S', a: ''}), encodeSeries({a: '', b: 'S'}));
    expect(decodeSeries(encodeSeries({b: 'S', a: ''})), {a: '', b: 'S'});
    expect(encodeSeries({}), '');
    expect(decodeSeries('not json'), isEmpty);
    expect(decodeSeries(null), isEmpty);
    // For a list without rows of its own: the books that are in one.
    expect(sharedSeries(encodeSeries({b: 'S', a: ''})), {b: 'S'});
  });

  group('on a device', () {
    final db = MyLibraryDb.instance;
    late LibrarySyncLocal local;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      PathProviderPlatform.instance = _FakePathProvider();
      // (The keys are asked too: nothing is read for them.)
      GeminiSettings.instance.debugSet(useGemini: false, key: '');
      ClaudeSettings.instance.debugSet(useClaude: false, key: '');
    });

    setUp(() async {
      final database = await db.database;
      for (final t in ['mybooks', 'bookseries', 'syncstate']) {
        await database.delete(t);
      }
      await database.delete('preferences',
          where: 'name = ?', whereArgs: [seriesSharedPref]);
      await db.insert(_book(a, 'Tale 1'));
      await db.insert(_book(b, 'Tale 2'));
      local = LibrarySyncLocal(database: db);
    });

    Future<Map<String, String>> said() async =>
        decodeSeries(await local.setting(seriesSetting));

    test(
        'what the reader groups here goes into the map, and counts as '
        'changed now', () async {
      expect(await local.syncedSettings(), contains(seriesSetting));
      expect(await local.setting(seriesSetting), '');
      expect(await db.getSyncState('set:$seriesSetting'), isNull);

      await db.setSeries([a, b], 'Tale');
      await local.syncedSettings();
      expect(await said(), {a: 'Tale', b: 'Tale'});
      expect(await db.getSyncState('set:$seriesSetting'), isNotNull);
      // Told once: nothing is left marked.
      expect(await db.getSyncStates(MyLibraryDb.seriesChangeMark), isEmpty);
    });

    test(
        'what arrives is applied to the books here; a book that is not '
        'here stays in the map; what only this device knew stays too',
        () async {
      await db.setSeries([a], 'Mine');
      await local.syncedSettings();

      await local.applySetting(
          seriesSetting, encodeSeries({b: 'Theirs', elsewhere: 'Far'}));
      expect(await db.getSeriesForAll(), {a: 'Mine', b: 'Theirs'});
      expect(await said(), {a: 'Mine', b: 'Theirs', elsewhere: 'Far'});
      // What another device said is not the reader's change here.
      expect(await db.getSyncStates(MyLibraryDb.seriesChangeMark), isEmpty);

      // Theirs stands where both speak of a book.
      await local.applySetting(seriesSetting, encodeSeries({a: 'Theirs'}));
      expect((await db.getSeriesForAll())[a], 'Theirs');
    });

    test(
        'taken out here: said to the others as taken out, and taken out '
        'here when another device says so', () async {
      await local.applySetting(seriesSetting, encodeSeries({a: 'S', b: 'S'}));
      await db.setSeries([a], null);
      await local.syncedSettings();
      expect(await said(), {a: '', b: 'S'});

      await local.applySetting(seriesSetting, encodeSeries({a: '', b: ''}));
      expect(await db.getSeriesForAll(), isEmpty);
    });

    test(
        'a book that comes to this device later joins the series the '
        'account has it in', () async {
      await local.applySetting(seriesSetting, encodeSeries({c: 'Late'}));
      expect(await db.getSeriesForAll(), isEmpty);
      await db.insert(_book(c, 'Late 1'));
      await local.syncedSettings();
      expect(await db.getSeriesForAll(), {c: 'Late'});
      expect(await db.getSyncState('set:$seriesSetting'), isNull,
          reason: 'nothing of this device\'s own to tell');
    });

    test('grouped before the devices shared series: told at the first run',
        () async {
      await db.setSeries([a], 'Old', fromSync: true);
      await local.syncedSettings();
      expect(await said(), {a: 'Old'});
    });
  });
}
