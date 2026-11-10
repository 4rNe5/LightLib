// AppFiles in an IndexedDB store: one record per path. The browser build
// uses the real IndexedDB; tests run it on idb_shim's in-memory factory.

// Dart imports:
import 'dart:typed_data';

// Package imports:
import 'package:idb_shim/idb_client.dart';
import 'package:path/path.dart' as p;

// Project imports:
import 'package:openlib/services/storage/app_files.dart';

class IdbAppFiles extends AppFiles {
  IdbAppFiles(this._factory, {this.name = 'lightlib_files'});

  final IdbFactory _factory;
  final String name;
  static const _store = 'files';
  Future<Database>? _db;

  Future<Database> get _database => _db ??= _factory.open(name, version: 1,
          onUpgradeNeeded: (VersionChangeEvent e) {
        if (!e.database.objectStoreNames.contains(_store)) {
          e.database.createObjectStore(_store);
        }
      });

  static String _key(String path) => p.posix.normalize(path);

  @override
  Future<String> supportPath() async => '/support';

  @override
  Future<bool> exists(String path) async {
    final db = await _database;
    final tx = db.transaction(_store, idbModeReadOnly);
    final n = await tx.objectStore(_store).count(_key(path));
    await tx.completed;
    return n > 0;
  }

  @override
  Future<Uint8List?> readBytes(String path) async {
    final db = await _database;
    final tx = db.transaction(_store, idbModeReadOnly);
    final value = await tx.objectStore(_store).getObject(_key(path));
    await tx.completed;
    if (value == null) return null;
    if (value is Uint8List) return value;
    if (value is List) return Uint8List.fromList(value.cast<int>());
    return null;
  }

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    final db = await _database;
    final tx = db.transaction(_store, idbModeReadWrite);
    await tx.objectStore(_store).put(
        bytes is Uint8List ? bytes : Uint8List.fromList(bytes), _key(path));
    await tx.completed;
  }

  @override
  Future<void> delete(String path) async {
    final db = await _database;
    final tx = db.transaction(_store, idbModeReadWrite);
    await tx.objectStore(_store).delete(_key(path));
    await tx.completed;
  }

  @override
  Future<List<String>> list(String dir) async {
    final prefix = '${_key(dir)}/';
    final db = await _database;
    final tx = db.transaction(_store, idbModeReadOnly);
    // Every key from the prefix up to the next character after '/'.
    final keys = await tx
        .objectStore(_store)
        .getAllKeys(KeyRange.bound(prefix, '${_key(dir)}0', false, true));
    await tx.completed;
    return [
      for (final k in keys)
        if (!'$k'.substring(prefix.length).contains('/')) '$k',
    ];
  }
}
