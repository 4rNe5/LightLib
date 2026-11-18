// Heavy work (parsing a whole EPUB) off the UI thread where the platform
// allows: a short-lived isolate on devices, in place on the web (no
// isolates there).

// Dart imports:
import 'dart:async';
import 'dart:isolate';

// Flutter imports:
import 'package:flutter/foundation.dart' show kIsWeb;

Future<R> runHeavy<R>(FutureOr<R> Function() work) =>
    kIsWeb ? Future<R>.sync(work) : Isolate.run(work);
