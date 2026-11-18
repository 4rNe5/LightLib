// The web: sync's result as a browser notification while the tab is out
// of view (in view, the page shows progress and the result itself).

// Dart imports:
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

// Package imports:
import 'package:web/web.dart' as web;

// Project imports:
import 'package:openlib/services/sync/sync_notifier.dart';

SyncNotifier createSyncNotifier() => WebSyncNotifier();

class WebSyncNotifier implements SyncNotifier {
  static bool get _available => globalContext.has('Notification');

  @override
  void askPermission() {
    try {
      if (_available && web.Notification.permission == 'default') {
        web.Notification.requestPermission();
      }
    } catch (_) {}
  }

  @override
  Future<void> progress({
    required String title,
    required String text,
    required int done,
    required int total,
  }) async {}

  @override
  Future<void> finished({required String title, required String text}) async {
    try {
      if (!_available ||
          web.Notification.permission != 'granted' ||
          !web.document.hidden) {
        return;
      }
      web.Notification(
        title,
        web.NotificationOptions(
            body: text, icon: 'icons/Icon-192.png', tag: 'lightlib-sync'),
      );
    } catch (_) {
      // Some mobile browsers only notify from a service worker.
    }
  }

  @override
  Future<void> clear() async {}
}
