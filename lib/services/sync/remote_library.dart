// The library as the owner's project lists it, kept between visits: the
// web shows it at once (titles, authors, small covers) and fetches a
// book's file only when the book is opened.

// Dart imports:
import 'dart:async';
import 'dart:convert';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:path/path.dart' as p;

// Project imports:
import 'package:openlib/services/storage/app_files.dart';
import 'package:openlib/services/sync/sync_engine.dart';

class RemoteLibraryStore extends ChangeNotifier {
  RemoteLibraryStore._();
  static final RemoteLibraryStore instance = RemoteLibraryStore._();

  RemoteLibrary _library = const RemoteLibrary();
  Future<void>? _loading;

  RemoteLibrary get library => _library;

  Future<String> _path() async =>
      p.join(await AppFiles.instance.supportPath(), 'remote_library.json');

  /// What the last visit knew.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final text = await AppFiles.instance.readString(await _path());
      if (text != null && _library.books.isEmpty) {
        _library = RemoteLibrary.fromJson(jsonDecode(text));
        notifyListeners();
      }
    } catch (_) {}
  }

  /// What a sync run just read.
  void update(RemoteLibrary library) {
    _library = library;
    notifyListeners();
    unawaited(_save());
  }

  Future<void> _save() async {
    try {
      await AppFiles.instance
          .writeString(await _path(), jsonEncode(_library.toJson()));
    } catch (_) {}
  }

  /// Signed out: nothing of the account stays listed.
  Future<void> clear() async {
    _library = const RemoteLibrary();
    notifyListeners();
    try {
      await AppFiles.instance.delete(await _path());
    } catch (_) {}
  }
}
