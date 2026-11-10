// Dart imports:
import 'dart:io' show Platform;

// Flutter imports:
import 'package:flutter/foundation.dart' show kIsWeb;

/// What the app runs on. Every check answers false on the web first:
/// `Platform` throws there.
class PlatformUtils {
  /// Running in a browser (the web build).
  static bool get isWeb => kIsWeb;

  // Check if running on a mobile platform (Android or iOS)
  static bool get isMobile =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  // Check if running on a desktop platform (Linux, Windows, or macOS)
  static bool get isDesktop =>
      !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

  // Check if WebView is supported on the current platform
  static bool get isWebViewSupported =>
      !kIsWeb &&
      (Platform.isAndroid ||
          Platform.isIOS ||
          Platform.isMacOS ||
          Platform.isWindows);

  // Check if in-app PDF viewing is supported
  static bool get isPdfViewerSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  // Check if notifications are fully supported
  static bool get isNotificationSupported => !kIsWeb && Platform.isAndroid;

  // Check if running on Linux (no WebView support)
  static bool get isLinux => !kIsWeb && Platform.isLinux;

  // Check if running on Windows
  static bool get isWindows => !kIsWeb && Platform.isWindows;

  // Check if running on Android
  static bool get isAndroid => !kIsWeb && Platform.isAndroid;

  // Check if running on iOS
  static bool get isIOS => !kIsWeb && Platform.isIOS;

  // Check if running on macOS
  static bool get isMacOS => !kIsWeb && Platform.isMacOS;
}
