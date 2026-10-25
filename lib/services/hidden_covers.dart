// Library books whose cover the reader chose to hide: everywhere the app
// shows a library book's cover (the library, its cards, the book's page,
// the home-screen widgets) shows a plain placeholder with the title.

// Dart imports:
import 'dart:convert';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Project imports:
import 'package:openlib/services/database.dart';

class HiddenCovers extends ChangeNotifier {
  HiddenCovers._();
  static final HiddenCovers instance = HiddenCovers._();

  /// Preference: the ids of the books with a hidden cover, as a JSON list.
  static const pref = 'hiddenCoverBooks';

  final Set<String> _ids = {};
  Future<void>? _loading;

  /// Reads the list once; later calls wait for the same read.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final saved = await MyLibraryDb.instance
        .getPreference(pref)
        .catchError((_) => null);
    _ids
      ..clear()
      ..addAll(decode(saved));
    notifyListeners();
  }

  /// The ids in a saved value; nothing for anything unreadable.
  static Set<String> decode(Object? saved) {
    if (saved is! String || saved.isEmpty) return {};
    try {
      final list = jsonDecode(saved);
      return list is List ? {for (final id in list) id.toString()} : {};
    } catch (_) {
      return {};
    }
  }

  bool isHidden(String bookId) => _ids.contains(bookId);

  Future<void> setHidden(String bookId, bool hidden) async {
    final changed = hidden ? _ids.add(bookId) : _ids.remove(bookId);
    if (!changed) return;
    notifyListeners();
    await MyLibraryDb.instance
        .savePreference(pref, jsonEncode(_ids.toList()..sort()))
        .catchError((_) {});
  }

  /// For tests: the books with a hidden cover, without the database.
  @visibleForTesting
  void debugSet(Set<String> ids) {
    _ids
      ..clear()
      ..addAll(ids);
    _loading = Future.value();
    notifyListeners();
  }
}
