// Sync's notifications: how far a run is, and what it did. A system
// notification on the phone; on the web a browser notification when the
// tab is not in view (the page shows its own progress).

// Project imports:
import 'package:openlib/services/sync/sync_notifier_io.dart'
    if (dart.library.js_interop) 'package:openlib/services/sync/sync_notifier_web.dart'
    as impl;

abstract class SyncNotifier {
  /// This platform's; tests swap it.
  static SyncNotifier instance = impl.createSyncNotifier();

  /// Asks to be allowed to notify where that takes a tap (the web);
  /// call it from the tap itself.
  void askPermission();

  /// A run is moving things: [done] of [total] (0 total: not counted yet).
  Future<void> progress({
    required String title,
    required String text,
    required int done,
    required int total,
  });

  /// A run ended.
  Future<void> finished({required String title, required String text});

  /// Takes the progress notification away (a run that moved nothing).
  Future<void> clear();
}

/// Notifies nothing (tests, platforms without notifications).
class SilentSyncNotifier implements SyncNotifier {
  final List<String> shown = [];

  @override
  void askPermission() {}

  @override
  Future<void> progress({
    required String title,
    required String text,
    required int done,
    required int total,
  }) async =>
      shown.add('progress $done/$total $text');

  @override
  Future<void> finished({required String title, required String text}) async =>
      shown.add('finished $title: $text');

  @override
  Future<void> clear() async => shown.add('clear');
}
