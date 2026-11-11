// Devices: the picture is decoded and scaled off the UI thread.

// Dart imports:
import 'dart:isolate';
import 'dart:typed_data';

// Package imports:
import 'package:image/image.dart' as img;

Future<Uint8List?> coverJpeg(Uint8List image, int width) =>
    Isolate.run(() => scaledJpeg(image, width));

Uint8List? scaledJpeg(Uint8List image, int width) {
  try {
    final decoded = img.decodeImage(image);
    if (decoded == null) return null;
    final small = decoded.width > width
        ? img.copyResize(decoded,
            width: width, interpolation: img.Interpolation.average)
        : decoded;
    return Uint8List.fromList(img.encodeJpg(small, quality: 82));
  } catch (_) {
    return null;
  }
}
