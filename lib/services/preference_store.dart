// Project imports:
import 'package:openlib/services/database.dart';

/// The little bit of key/value storage the mirror layer needs.
///
/// Pulling this behind an interface keeps [InstanceManager] and the
/// open-slum.org catalogue free of the app's sqlite singleton: the app
/// uses [DbPreferenceStore], tests use [MemoryPreferenceStore], and the
/// mirror rules can be exercised without a database at all.
abstract class PreferenceStore {
  Future<Object?> read(String key);
  Future<void> write(String key, Object? value);
}

/// Production store: the app's preferences table.
class DbPreferenceStore implements PreferenceStore {
  DbPreferenceStore({MyLibraryDb? database})
      : _database = database ?? MyLibraryDb.instance;

  final MyLibraryDb _database;

  @override
  Future<Object?> read(String key) async {
    try {
      return await _database.getPreference(key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, Object? value) async {
    try {
      await _database.savePreference(key, value);
    } catch (_) {
      // Preferences are best-effort; losing one must not break a search.
    }
  }
}

/// In-memory store for tests and for a first run before the database is
/// ready.
class MemoryPreferenceStore implements PreferenceStore {
  final Map<String, Object?> _values = {};

  @override
  Future<Object?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, Object? value) async {
    _values[key] = value;
  }

  /// Test helper: what does the store currently hold?
  Map<String, Object?> get snapshot => Map.unmodifiable(_values);
}
