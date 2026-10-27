// Translations already made, kept per book, target language and style -
// one set whichever engine made each paragraph (the phone's model or
// Gemini), so switching engines carries on where the other left off.

// Dart imports:
import 'dart:async';
import 'dart:convert';
import 'dart:io';

// Package imports:
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/translation/translation_models.dart';

/// A JSON file of source-text hash → translation. Keyed by the text, not
/// the paragraph index, so a re-paginated book or a repeated line reuses
/// what was already translated. Writes are batched.
class TranslationCache {
  TranslationCache._(this._file, this._entries);

  final File _file;
  final Map<String, String> _entries;
  Timer? _saveTimer;
  bool _dirty = false;

  static final Map<String, TranslationCache> _open = {};

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
    final base = directory ?? await bookFolderDirectory();
    if (!await base.exists()) await base.create(recursive: true);
    final id = fileIdFor(bookFileName, targetLanguage, modelId);
    final path = p.join(base.path, '$id.json');
    // One instance per file: the reader and the background translator
    // write the same book, and two instances would overwrite each other.
    final existing = _open[path];
    if (existing != null) return existing;
    final file = File(path);
    var entries = <String, String>{};
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
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
        final f = File(p.join(
            base.path, '${fileIdFor(bookFileName, targetLanguage, old)}.json'));
        if (!await f.exists()) continue;
        try {
          final decoded = jsonDecode(await f.readAsString());
          if (decoded is Map) {
            decoded.forEach((k, v) => entries.putIfAbsent('$k', () => '$v'));
          }
        } catch (_) {}
      }
    }
    final cache = _open[path] ??= TranslationCache._(file, entries);
    if (!await file.exists() && entries.isNotEmpty) {
      cache._dirty = true;
      await cache.flush();
    }
    return cache;
  }

  /// Deletes every saved translation of [bookFileName] (all languages and
  /// models), e.g. when the book is removed from the library.
  static Future<void> deleteForBook(String bookFileName,
      {Directory? directory}) async {
    final base = directory ?? await bookFolderDirectory();
    for (final language in const [
      'ko',
      'en',
      'ja',
      'zh',
      'zh-TW',
      'es',
      'fr',
      'de',
      'ru',
      'pt',
      'it',
      'vi',
      'th',
      'id'
    ]) {
      for (final model in [
        sharedModelId(lightNovel: true),
        sharedModelId(lightNovel: false),
        ...translationModelPresets.map((m) => m.fileName),
      ]) {
        final path = p.join(
            base.path, '${fileIdFor(bookFileName, language, model)}.json');
        _open.remove(path);
        final f = File(path);
        if (await f.exists()) await f.delete();
      }
    }
  }

  int get length => _entries.length;

  String? lookup(String text) => _entries[keyFor(text)];

  void store(String text, String translation) {
    _entries[keyFor(text)] = translation;
    _dirty = true;
    _saveTimer ??= Timer(const Duration(seconds: 3), () {
      _saveTimer = null;
      flush();
    });
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (!_dirty) return;
    _dirty = false;
    final temp = File('${_file.path}.tmp');
    await temp.writeAsString(jsonEncode(_entries));
    await temp.rename(_file.path);
  }

  /// Removes every cached translation for this book.
  Future<void> clear() async {
    _open.remove(_file.path);
    _entries.clear();
    _dirty = false;
    _saveTimer?.cancel();
    _saveTimer = null;
    if (await _file.exists()) await _file.delete();
  }
}
