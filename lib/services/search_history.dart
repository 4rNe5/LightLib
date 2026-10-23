// Search history: the queries typed into the search page, newest first,
// kept on the device (and in backups). Saving can be turned off in
// Settings; turning it off keeps what is there until it is cleared.

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Project imports:
import 'package:openlib/services/database.dart';

const searchHistoryEnabledPref = 'saveSearchHistory';

/// Whether new searches are saved. Loads the preference on first use;
/// on by default.
class SearchHistoryEnabled extends StateNotifier<bool> {
  SearchHistoryEnabled(this._db) : super(true) {
    _load();
  }

  final MyLibraryDb _db;

  Future<void> _load() async {
    final saved =
        await _db.getPreference(searchHistoryEnabledPref).catchError((_) => 1);
    if (mounted) state = saved != 0 && saved != '0';
  }

  Future<void> set(bool enabled) async {
    state = enabled;
    await _db
        .savePreference(searchHistoryEnabledPref, enabled ? 1 : 0)
        .catchError((_) {});
  }
}

final searchHistoryEnabledProvider =
    StateNotifierProvider<SearchHistoryEnabled, bool>(
        (ref) => SearchHistoryEnabled(MyLibraryDb.instance));

/// Saved searches, newest first.
final searchHistoryProvider = FutureProvider<List<String>>((ref) {
  return MyLibraryDb.instance.getSearchHistory().catchError((_) => <String>[]);
});

/// Saves [query] unless history is off, then refreshes the list.
Future<void> recordSearch(WidgetRef ref, String query) async {
  if (!ref.read(searchHistoryEnabledProvider)) return;
  await MyLibraryDb.instance.addSearchHistory(query).catchError((_) {});
  ref.invalidate(searchHistoryProvider);
}

Future<void> removeSearch(WidgetRef ref, String query) async {
  await MyLibraryDb.instance.deleteSearchHistory(query).catchError((_) {});
  ref.invalidate(searchHistoryProvider);
}

Future<void> clearSearches(WidgetRef ref) async {
  await MyLibraryDb.instance.clearSearchHistory().catchError((_) {});
  ref.invalidate(searchHistoryProvider);
}

/// Saved queries that contain what is being typed, for the suggestion
/// list. The query itself is left out.
List<String> matchingHistory(List<String> history, String typed,
    {int limit = 3}) {
  final needle = typed.trim().toLowerCase();
  if (needle.isEmpty) return const [];
  return history
      .where(
          (q) => q.toLowerCase() != needle && q.toLowerCase().contains(needle))
      .take(limit)
      .toList();
}
