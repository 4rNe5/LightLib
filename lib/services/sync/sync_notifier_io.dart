// The phone: sync's progress and result as a system notification (the
// download notifications' plugin, a channel of its own).

// Package imports:
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Project imports:
import 'package:openlib/services/download_notification.dart';
import 'package:openlib/services/platform_utils.dart';
import 'package:openlib/services/sync/sync_notifier.dart';

SyncNotifier createSyncNotifier() =>
    PlatformUtils.isAndroid ? AndroidSyncNotifier() : SilentSyncNotifier();

class AndroidSyncNotifier implements SyncNotifier {
  static const _id = 7100;
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void> _ready() => DownloadNotificationService().initialize();

  @override
  void askPermission() {
    // Asked for at the app's start (with the download notifications).
  }

  @override
  Future<void> progress({
    required String title,
    required String text,
    required int done,
    required int total,
  }) async {
    try {
      await _ready();
      await _plugin.show(
        id: _id,
        title: title,
        body: text,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'sync_channel',
            'Sync',
            channelDescription: 'Sync with LightLib on the web: progress',
            importance: Importance.low,
            priority: Priority.low,
            showProgress: true,
            maxProgress: total > 0 ? total : 1,
            progress: total > 0 ? done.clamp(0, total) : 0,
            indeterminate: total <= 0,
            ongoing: true,
            autoCancel: false,
            onlyAlertOnce: true,
            playSound: false,
            enableVibration: false,
            icon: '@mipmap/launcher_icon',
          ),
        ),
      );
    } catch (_) {
      // No notifications (not allowed, not ready): the settings still show
      // how the run went.
    }
  }

  @override
  Future<void> finished({required String title, required String text}) async {
    try {
      await _ready();
      await _plugin.show(
        id: _id,
        title: title,
        body: text,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'sync_done_channel',
            'Sync finished',
            channelDescription: 'Sync with LightLib on the web: results',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            ongoing: false,
            autoCancel: true,
            playSound: false,
            enableVibration: false,
            icon: '@mipmap/launcher_icon',
            styleInformation:
                BigTextStyleInformation(text, contentTitle: title),
          ),
        ),
      );
    } catch (_) {}
  }

  @override
  Future<void> clear() async {
    try {
      await _plugin.cancel(id: _id);
    } catch (_) {}
  }
}
