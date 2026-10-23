// The Android manifest declares the system libraries LiteRT-LM's GPU
// backend loads; without them it silently runs on a slow fallback.

// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('declares the OpenCL driver for the GPU translation engine', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final application = manifest.substring(manifest.indexOf('<application'),
        manifest.indexOf('</application>'));
    for (final lib in ['libOpenCL.so', 'libvndksupport.so']) {
      expect(
          application,
          contains('<uses-native-library android:name="$lib" '
              'android:required="false"/>'));
    }
  });
}
