// The Gemini key between devices: a key typed here is announced (sync
// sends it on), one that came from another device is kept without being
// sent back, and a removal there removes it here.

// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';

// Project imports:
import 'package:openlib/services/storage/app_files.dart';
import 'package:openlib/services/storage/idb_app_files.dart';
import 'package:openlib/services/translation/gemini/gemini_settings.dart';

void main() {
  const path = '/support/gemini_api_key';
  final files = AppFiles.instance;
  final settings = GeminiSettings.instance;
  final keyPath = settings.keyPath;

  setUp(() {
    AppFiles.instance = IdbAppFiles(newIdbFactoryMemory());
    settings.keyPath = () async => path;
  });
  tearDown(() {
    AppFiles.instance = files;
    settings.keyPath = keyPath;
    GeminiSettings.onKeyChanged = null;
  });

  test('typed here: kept and announced', () async {
    var announced = 0;
    GeminiSettings.onKeyChanged = () => announced++;
    await settings.setKey('  key-1 ');
    expect(settings.apiKey, 'key-1');
    expect(await AppFiles.instance.readString(path), 'key-1');
    expect(announced, 1);
  });

  test('from another device: kept, not announced', () async {
    var announced = 0;
    await settings.setKey('key-1');
    GeminiSettings.onKeyChanged = () => announced++;

    await settings.applySynced('key-2');

    expect(settings.apiKey, 'key-2');
    expect(await AppFiles.instance.readString(path), 'key-2');
    expect(announced, 0);
  });

  test('removed on another device: removed here', () async {
    await settings.setKey('key-1');
    await settings.applySynced('');
    expect(settings.hasKey, isFalse);
    expect(await AppFiles.instance.exists(path), isFalse);
  });
}
