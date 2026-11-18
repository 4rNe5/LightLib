// What the web pages ask the browser itself: files dropped on the window
// and how much this site stores. Nothing outside a browser (tests).

// Flutter imports:
import 'package:flutter/foundation.dart';

// Project imports:
import 'package:openlib/web/browser_stub.dart'
    if (dart.library.js_interop) 'package:openlib/web/browser_web.dart' as impl;

typedef DroppedFile = ({String name, Uint8List bytes});

class Browser {
  /// Whether files are being dragged over the window.
  static ValueListenable<bool> get dragging => impl.dragging;

  /// Starts listening for dropped files; the returned call stops it.
  static VoidCallback onFilesDropped(
          void Function(List<DroppedFile> files) onDrop) =>
      impl.onFilesDropped(onDrop);

  /// Bytes this site keeps in the browser (books, covers, translations),
  /// or null when the browser does not say.
  static Future<int?> storageUsed() => impl.storageUsed();
}
