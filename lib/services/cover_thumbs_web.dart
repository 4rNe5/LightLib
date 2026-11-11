// The web: the browser decodes and scales (its own code, off the page's
// thread) - the Dart decoder would hold the page for a second a cover.

// Dart imports:
import 'dart:js_interop';
import 'dart:typed_data';

// Package imports:
import 'package:web/web.dart' as web;

Future<Uint8List?> coverJpeg(Uint8List image, int width) async {
  try {
    final full =
        await web.window.createImageBitmap(web.Blob([image.toJS].toJS)).toDart;
    final w = full.width > width ? width : full.width;
    final h = (full.height * w / full.width).round();
    final canvas = web.OffscreenCanvas(w, h);
    final context =
        canvas.getContext('2d') as web.OffscreenCanvasRenderingContext2D;
    context.imageSmoothingQuality = 'high';
    context.drawImage(full, 0, 0, w, h);
    full.close();
    final blob = await canvas
        .convertToBlob(
            web.ImageEncodeOptions(type: 'image/jpeg', quality: 0.82))
        .toDart;
    return (await blob.arrayBuffer().toDart).toDart.asUint8List();
  } catch (_) {
    return null;
  }
}
