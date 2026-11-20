// Translations already made, kept per book, target language and style -
// one set whichever engine made each paragraph (the phone's model or
// Gemini), so switching engines carries on where the other left off.

// Dart imports:
import 'dart:async';
import 'dart:convert';
import 'dart:io';

// Flutter imports:
import 'package:flutter/foundation.dart' show kIsWeb;

// Package imports:
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/storage/app_files.dart';
import 'package:openlib/services/translation/translation_models.dart';

/// A JSON file of source-text hash → translation. Keyed by the text, not
/// the paragraph index, so a re-paginated book or a repeated line reuses
/// what was already translated. Writes are batched.
class TranslationCache {
  TranslationCache._(this._path, this._entries, [Set<String>? redo])
      : _redo = redo ?? {};

  /// Where this set is kept (a file; an IndexedDB record on the web).
  final String _path;
  static AppFiles get _files => AppFiles.instance;
  final Map<String, String> _entries;
  Timer? _saveTimer;
  bool _dirty = false;

  /// Saved translations that are to be made again (by [keyFor]): the
  /// reader changed the name they were written with. They count as not
  /// translated until a new one is stored; kept beside the set
  /// (`<set>.redo`), on this device only.
  final Set<String> _redo;
  bool _redoDirty = false;
  String get _redoPath => '$_path.redo';

  static final Map<String, TranslationCache> _open = {};

  /// Called with a set's path after it is written (sync sends it on).
  static void Function(String path)? onChanged;

  /// Every language a set can be kept for.
  static const languages = [
    'ko', 'en', 'ja', 'zh', 'zh-TW', 'es', 'fr', 'de', 'ru', 'pt', 'it', //
    'vi', 'th', 'id',
  ];

  /// Where this set is kept.
  String get path => _path;

  /// Whether the set at [path] is open (the reader or the library has it).
  static bool isOpen(String path) => _open.containsKey(path);

  /// Lets the set go once written (sync opened it only to merge).
  void forget() {
    if (identical(_open[_path], this)) _open.remove(_path);
  }

  /// Where translations are kept: a hidden folder next to the books, so a
  /// book's translation travels with the book folder (backups, a moved
  /// storage folder). Library sync only looks at book files, so it never
  /// mistakes these for books.
  static Future<Directory> bookFolderDirectory() async {
    final storage =
        (await MyLibraryDb.instance.getPreference('bookStorageDirectory'))
            .toString();
    final dir = Directory(p.join(storage, '.translations'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// The folder translations are kept in: next to the books on devices,
  /// a fixed place on the web.
  static Future<String> folderPath({Directory? directory}) async {
    if (directory != null) return directory.path;
    if (kIsWeb) return '/translations';
    return (await bookFolderDirectory()).path;
  }

  static String fileIdFor(
          String bookFileName, String targetLanguage, String modelId) =>
      sha1
          .convert(utf8.encode('$bookFileName|$targetLanguage|$modelId'))
          .toString()
          .substring(0, 20);

  /// The id of the one set of translations for a style.
  static String sharedModelId({required bool lightNovel}) =>
      lightNovel ? 'shared' : 'shared+plain';

  static String keyFor(String text) =>
      sha1.convert(utf8.encode(text)).toString();

  /// Opens (or creates) the cache for one book in [directory], defaulting
  /// to the app's support directory.
  static Future<TranslationCache> open({
    required String bookFileName,
    required String targetLanguage,
    required String modelId,
    Directory? directory,
    List<String> mergeFrom = const [],
  }) async {
    final base = await folderPath(directory: directory);
    final id = fileIdFor(bookFileName, targetLanguage, modelId);
    final path = p.join(base, '$id.json');
    // One instance per file: the reader and the background translator
    // write the same book, and two instances would overwrite each other.
    final existing = _open[path];
    if (existing != null) return existing;
    var entries = <String, String>{};
    final saved = await _files.readString(path);
    if (saved != null) {
      try {
        final decoded = jsonDecode(saved);
        if (decoded is Map) {
          entries = decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
        }
      } catch (_) {
        // A corrupt cache is only lost work; start over.
      }
    } else if (mergeFrom.isNotEmpty) {
      // First opened: what earlier versions kept per model comes along
      // (the first listed wins where two translated the same text).
      for (final old in mergeFrom) {
        final text = await _files.readString(p.join(
            base, '${fileIdFor(bookFileName, targetLanguage, old)}.json'));
        if (text == null) continue;
        try {
          final decoded = jsonDecode(text);
          if (decoded is Map) {
            decoded.forEach((k, v) => entries.putIfAbsent('$k', () => '$v'));
          }
        } catch (_) {}
      }
    }
    var redo = <String>{};
    try {
      final marks = await _files.readString('$path.redo');
      if (marks != null) {
        redo = {for (final k in jsonDecode(marks) as List) '$k'};
      }
    } catch (_) {}
    final cache = _open[path] ??= TranslationCache._(path, entries, redo);
    if (saved == null && entries.isNotEmpty) {
      cache._dirty = true;
      await cache.flush();
    }
    return cache;
  }

  /// Deletes every saved translation of [bookFileName] (all languages and
  /// models), e.g. when the book is removed from the library.
  static Future<void> deleteForBook(String bookFileName,
      {Directory? directory}) async {
    final base = await folderPath(directory: directory);
    for (final language in languages) {
      for (final model in [
        sharedModelId(lightNovel: true),
        sharedModelId(lightNovel: false),
        ...translationModelPresets.map((m) => m.fileName),
      ]) {
        final path =
            p.join(base, '${fileIdFor(bookFileName, language, model)}.json');
        _open.remove(path);
        await _files.delete(path);
        await _files.delete('$path.redo');
      }
    }
  }

  int get length => _entries.length;

  /// Every translation, by [keyFor] of its source text.
  Map<String, String> get entries => Map.unmodifiable(_entries);

  /// The translation of [text]; none while it is to be made again
  /// ([redo]).
  String? lookup(String text) {
    final key = keyFor(text);
    return _redo.contains(key) ? null : _entries[key];
  }

  /// What is saved for [text], also when it is to be made again.
  String? saved(String text) => _entries[keyFor(text)];

  /// How many saved translations wait to be made again.
  int get toRedo => _redo.length;

  /// Has the saved translations of [texts] made again: until then they
  /// count as not translated here and in the reader. How many were
  /// marked now.
  int redo(Iterable<String> texts) {
    var marked = 0;
    for (final text in texts) {
      final key = keyFor(text);
      if (_entries.containsKey(key) && _redo.add(key)) marked++;
    }
    if (marked > 0) {
      _redoDirty = true;
      _saveTimer ??= Timer(const Duration(seconds: 3), () {
        _saveTimer = null;
        flush();
      });
    }
    return marked;
  }

  void store(String text, String translation) {
    final key = keyFor(text);
    _entries[key] = translation;
    if (_redo.remove(key)) _redoDirty = true;
    _dirty = true;
    _saveTimer ??= Timer(const Duration(seconds: 3), () {
      _saveTimer = null;
      flush();
    });
  }

  /// Writes what changed; [quiet] when sync wrote it (not a change to
  /// send back).
  Future<void> flush({bool quiet = false}) async {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (_redoDirty) {
      _redoDirty = false;
      try {
        if (_redo.isEmpty) {
          await _files.delete(_redoPath);
        } else {
          await _files.writeString(_redoPath, jsonEncode(_redo.toList()));
        }
      } catch (_) {}
    }
    if (!_dirty) return;
    _dirty = false;
    await _files.writeString(_path, jsonEncode(_entries));
    if (!quiet) onChanged?.call(_path);
  }

  /// Adds translations made elsewhere (sync); what is here already stays
  /// unless [overwrite]. Returns how many were new.
  int absorb(Map<String, String> other, {bool overwrite = false}) {
    var added = 0;
    other.forEach((k, v) {
      if (overwrite || !_entries.containsKey(k)) {
        if (_entries[k] != v) added++;
        _entries[k] = v;
      }
    });
    if (added > 0) {
      _dirty = true;
      _saveTimer ??= Timer(const Duration(seconds: 3), () {
        _saveTimer = null;
        flush();
      });
    }
    return added;
  }

  /// Removes every cached translation for this book.
  Future<void> clear() async {
    _open.remove(_path);
    _entries.clear();
    _redo.clear();
    _redoDirty = false;
    await _files.delete(_redoPath).catchError((_) {});
    _dirty = false;
    _saveTimer?.cancel();
    _saveTimer = null;
    await _files.delete(_path);
  }
}
