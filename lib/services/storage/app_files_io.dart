// Devices: AppFiles over dart:io.

// Dart imports:
import 'dart:io';
import 'dart:typed_data';

// Package imports:
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// Project imports:
import 'package:openlib/services/storage/app_files.dart';

AppFiles createAppFiles() => IoAppFiles();

class IoAppFiles extends AppFiles {
  IoAppFiles({this.root});

  /// Where [supportPath] points (tests); the app support directory
  /// otherwise.
  final String? root;

  @override
  Future<String> supportPath() async =>
      root ?? (await getApplicationSupportDirectory()).path;

  @override
  Future<bool> exists(String path) => File(path).exists();

  @override
  Future<Uint8List?> readBytes(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final temp = File('$path.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(path);
  }

  @override
  Future<void> delete(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<List<String>> list(String dir) async {
    final d = Directory(dir);
    if (!await d.exists()) return const [];
    return [
      await for (final e in d.list())
        if (e is File && !e.path.endsWith('.tmp')) p.normalize(e.path),
    ];
  }
}
