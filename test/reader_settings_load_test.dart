// A reader setting changed while the saved settings are still loading
// must survive the load (it used to be overwritten by the older value).

// Dart imports:
import 'dart:convert';
import 'dart:io';

// Flutter imports:
import 'package:flutter_test/flutter_test.dart';

// Package imports:
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/reader_settings.dart';
import 'package:openlib/ui/components/paged_book_view.dart' show ReaderLayout;

class _FakePathProvider extends PathProviderPlatform {
  Future<String> _dir(String name) async {
    final dir = Directory('/tmp/openlib_reader_settings_load_test/$name');
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
  setUpAll(() {
    final stale = Directory('/tmp/openlib_reader_settings_load_test');
    if (stale.existsSync()) stale.deleteSync(recursive: true);
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    PathProviderPlatform.instance = _FakePathProvider();
  });

  test('a change during loading is kept', () async {
    final db = MyLibraryDb.instance;
    await db.savePreference(ReaderSettings.pref,
        jsonEncode(const ReaderSettingsData(fontSize: 20).toJson()));
    final settings = ReaderSettings(database: db);
    final loading = settings.load();
    await settings
        .update(settings.value.copyWith(layout: ReaderLayout.pagesLtr));
    await loading;
    expect(settings.loaded, isTrue);
    expect(settings.value.layout, ReaderLayout.pagesLtr);
  });

  test('without a change, the saved settings load', () async {
    final db = MyLibraryDb.instance;
    await db.savePreference(ReaderSettings.pref,
        jsonEncode(const ReaderSettingsData(fontSize: 22).toJson()));
    final settings = ReaderSettings(database: db);
    await settings.load();
    expect(settings.value.fontSize, 22);
  });
}
