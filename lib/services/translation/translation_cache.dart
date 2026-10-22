// Translations already made, kept per book, target language and model.

// Dart imports:
import 'dart:async';
import 'dart:convert';
import 'dart:io';

// Package imports:
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A JSON file of source-text hash → translation. Keyed by the text, not
/// the paragraph index, so a re-paginated book or a repeated line reuses
/// what was already translated. Writes are batched.
class TranslationCache {
  TranslationCache._(this._file, this._entries);

  final File _file;
  final Map<String, String> _entries;
  Timer? _saveTimer;
  bool _dirty = false;

  static String keyFor(String text) =>
      sha1.convert(utf8.encode(text)).toString();

  /// Opens (or creates) the cache for one book in [directory], defaulting
  /// to the app's support directory.
  static Future<TranslationCache> open({
    required String bookFileName,
    required String targetLanguage,
    required String modelId,
    Directory? directory,
  }) async {
    final base = directory ??
        Directory(p.join(
            (await getApplicationSupportDirectory()).path, 'translations'));
    if (!await base.exists()) await base.create(recursive: true);
    final id = sha1
        .convert(utf8.encode('$bookFileName|$targetLanguage|$modelId'))
        .toString()
        .substring(0, 20);
    final file = File(p.join(base.path, '$id.json'));
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
    }
    return TranslationCache._(file, entries);
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
    _entries.clear();
    _dirty = false;
    _saveTimer?.cancel();
    _saveTimer = null;
    if (await _file.exists()) await _file.delete();
  }
}
