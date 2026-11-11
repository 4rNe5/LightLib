// Not in a browser: nothing is dropped, nothing is known.

// Flutter imports:
import 'package:flutter/foundation.dart';

// Project imports:
import 'package:openlib/web/browser.dart';

final ValueNotifier<bool> dragging = ValueNotifier(false);

VoidCallback onFilesDropped(void Function(List<DroppedFile> files) onDrop) =>
    () {};

Future<int?> storageUsed() async => null;
