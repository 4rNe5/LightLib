// In the browser: drag-and-drop on the document, navigator.storage.

// Dart imports:
import 'dart:async';
import 'dart:js_interop';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:web/web.dart' as web;

// Project imports:
import 'package:openlib/web/browser.dart';

final ValueNotifier<bool> dragging = ValueNotifier(false);

bool _hasFiles(web.DragEvent e) {
  final types = e.dataTransfer?.types;
  return types != null && types.toDart.any((t) => t.toDart == 'Files');
}

VoidCallback onFilesDropped(void Function(List<DroppedFile> files) onDrop) {
  Timer? leaving;
  final over = ((web.DragEvent e) {
    if (!_hasFiles(e)) return;
    e.preventDefault();
    leaving?.cancel();
    dragging.value = true;
  }).toJS;
  // "leave" fires between elements too: gone only when no "over" follows.
  final leave = ((web.DragEvent e) {
    leaving?.cancel();
    leaving =
        Timer(const Duration(milliseconds: 120), () => dragging.value = false);
  }).toJS;
  final drop = ((web.DragEvent e) {
    if (!_hasFiles(e)) return;
    e.preventDefault();
    leaving?.cancel();
    dragging.value = false;
    final list = e.dataTransfer?.files;
    if (list == null) return;
    final files = <web.File>[
      for (var i = 0; i < list.length; i++)
        if (list.item(i) case final file?) file,
    ];
    unawaited(() async {
      final out = <DroppedFile>[];
      for (final file in files) {
        try {
          final buffer = await file.arrayBuffer().toDart;
          out.add((name: file.name, bytes: buffer.toDart.asUint8List()));
        } catch (_) {}
      }
      if (out.isNotEmpty) onDrop(out);
    }());
  }).toJS;
  web.document.addEventListener('dragover', over);
  web.document.addEventListener('dragleave', leave);
  web.document.addEventListener('drop', drop);
  return () {
    leaving?.cancel();
    dragging.value = false;
    web.document.removeEventListener('dragover', over);
    web.document.removeEventListener('dragleave', leave);
    web.document.removeEventListener('drop', drop);
  };
}

Future<int?> storageUsed() async {
  try {
    final estimate = await web.window.navigator.storage.estimate().toDart;
    return estimate.usage;
  } catch (_) {
    return null;
  }
}
