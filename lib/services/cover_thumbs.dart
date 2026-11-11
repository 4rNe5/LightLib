// Small covers: what a library that does not have a book's file shows of
// it (the web lists the whole library this way), and what the web draws
// instead of decoding every full-size cover.

// Dart imports:
import 'dart:typed_data';

// Package imports:
import 'package:path/path.dart' as p;

// Project imports:
import 'package:openlib/services/cover_thumbs_io.dart'
    if (dart.library.js_interop) 'package:openlib/services/cover_thumbs_web.dart'
    as impl;
import 'package:openlib/services/storage/app_files.dart';

/// Width of a small cover: a library tile on a dense screen, the book's
/// card at twice its size.
const coverThumbWidth = 600;

class CoverThumbs {
  /// [image] as a JPEG no wider than [width]; null when it is not a
  /// picture this platform reads.
  static Future<Uint8List?> jpeg(Uint8List image,
          {int width = coverThumbWidth}) =>
      impl.coverJpeg(image, width);

  /// Where the small cover of the book [md5] is kept.
  static Future<String> path(String md5) async => p.join(
      await AppFiles.instance.supportPath(), 'covers', 'thumbs', '$md5.jpg');

  /// Whether [path] is one of these small covers.
  static bool isThumb(String path) =>
      p.basename(p.dirname(path)) == 'thumbs' &&
      p.basename(p.dirname(p.dirname(path))) == 'covers';

  /// The small cover kept here for the book [md5], or null.
  static Future<Uint8List?> read(String md5) async =>
      AppFiles.instance.readBytes(await path(md5));

  static Future<void> write(String md5, Uint8List jpeg) async =>
      AppFiles.instance.writeBytes(await path(md5), jpeg);

  static Future<void> remove(String md5) async =>
      AppFiles.instance.delete(await path(md5));
}
