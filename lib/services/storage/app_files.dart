// Files the app keeps for itself - imported books, saved translations,
// glossaries, the Gemini key: real files on devices, IndexedDB records
// under the same paths on the web (the browser has no file system).

// Dart imports:
import 'dart:convert';
import 'dart:typed_data';

// Project imports:
import 'package:openlib/services/storage/app_files_io.dart'
    if (dart.library.js_interop) 'package:openlib/services/storage/app_files_web.dart'
    as impl;

abstract class AppFiles {
  /// The store this platform uses; tests swap it.
  static AppFiles instance = impl.createAppFiles();

  /// The folder the app keeps its own files in (the app support
  /// directory on devices).
  Future<String> supportPath();

  Future<bool> exists(String path);

  /// The bytes at [path], or null when nothing is there.
  Future<Uint8List?> readBytes(String path);

  /// Replaces whatever is at [path] in one step (no half-written file).
  Future<void> writeBytes(String path, List<int> bytes);

  Future<void> delete(String path);

  /// Paths directly under the folder [dir].
  Future<List<String>> list(String dir);

  Future<String?> readString(String path) async {
    final bytes = await readBytes(path);
    return bytes == null ? null : utf8.decode(bytes, allowMalformed: true);
  }

  Future<void> writeString(String path, String text) =>
      writeBytes(path, utf8.encode(text));
}
