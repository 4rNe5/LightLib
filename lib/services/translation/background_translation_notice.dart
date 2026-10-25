// The Android side of background library translation: an ongoing
// notification with a progress bar (a foreground service that keeps the
// app running), and the battery and temperature readings that pace it.

// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What the phone can spare right now.
@immutable
class DeviceLoad {
  const DeviceLoad({
    this.thermal = 0,
    this.powerSave = false,
    this.battery = 100,
    this.charging = false,
    this.headroom,
  });

  /// Android's thermal status: 0 none, 1 light, 2 moderate, 3 severe...
  final int thermal;
  final bool powerSave;

  /// Battery percent.
  final int battery;
  final bool charging;

  /// Android's thermal headroom 10 s ahead (1.0: severe throttling), or
  /// null where the phone does not report it.
  final double? headroom;

  /// How hot, from 0 (cool) to 1 (severe throttling) and above: the
  /// headroom where there is one, never less than the status step says.
  double get heat {
    final fromStatus = switch (thermal) {
      <= 0 => 0.0,
      1 => 0.6,
      2 => 0.85,
      _ => 1.0 + (thermal - 3) * 0.1,
    };
    final h = headroom;
    return h != null && h > fromStatus ? h : fromStatus;
  }

  static const nominal = DeviceLoad();

  factory DeviceLoad.fromMap(Map<Object?, Object?> map) => DeviceLoad(
        thermal: (map['thermal'] as num?)?.toInt() ?? 0,
        powerSave: map['powerSave'] == true,
        battery: (map['battery'] as num?)?.toInt() ?? 100,
        charging: map['charging'] == true,
        headroom: switch (map['headroom']) {
          final num h when h >= 0 && h.isFinite => h.toDouble(),
          _ => null,
        },
      );
}

/// The notification and device readings, over a method channel to
/// `MainActivity`. Everything is a no-op off Android.
class BackgroundTranslationNotice {
  BackgroundTranslationNotice._();
  static final BackgroundTranslationNotice instance =
      BackgroundTranslationNotice._();

  static const _channel = MethodChannel('lightlib/background_translation');

  /// The stop button in the notification.
  VoidCallback? onStopRequested;

  /// Android ended the service (its daily time limit).
  VoidCallback? onTimedOut;

  bool _listening = false;
  bool _showing = false;

  @visibleForTesting
  static bool? supportedOverride;

  bool get supported => supportedOverride ?? Platform.isAndroid;

  /// Whether the notification (and so the service) is up.
  bool get showing => _showing;

  void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'pauseRequested':
          onStopRequested?.call();
        case 'timedOut':
          _showing = false;
          onTimedOut?.call();
      }
      return null;
    });
  }

  /// Shows or updates the notification. False when Android did not allow
  /// the service to start (the app is already in the background).
  Future<bool> show({
    required String channelName,
    required String title,
    required String text,
    String? subText,
    required int progress,
    required int max,
    bool indeterminate = false,
    String? stopLabel,
  }) async {
    if (!supported) return false;
    _listen();
    try {
      final ok =
          await _channel.invokeMethod<bool>(_showing ? 'update' : 'start', {
        'channelName': channelName,
        'title': title,
        'text': text,
        'subText': subText,
        'progress': progress,
        'max': max,
        'indeterminate': indeterminate,
        'pauseLabel': stopLabel,
      });
      _showing = ok == true;
    } on PlatformException {
      _showing = false;
    } on MissingPluginException {
      _showing = false;
    }
    return _showing;
  }

  /// Removes the notification; [doneTitle] leaves a "finished" notice.
  Future<void> hide({String? doneTitle, String? doneText}) async {
    if (!supported || !_showing) return;
    _showing = false;
    try {
      await _channel.invokeMethod<void>(
          'stop', {'doneTitle': doneTitle, 'doneText': doneText});
    } on PlatformException {
      // Already gone.
    } on MissingPluginException {
      // Not on this platform.
    }
  }

  Future<DeviceLoad> deviceLoad() async {
    if (!supported) return DeviceLoad.nominal;
    try {
      final map =
          await _channel.invokeMethod<Map<Object?, Object?>>('deviceState');
      return map == null ? DeviceLoad.nominal : DeviceLoad.fromMap(map);
    } on PlatformException {
      return DeviceLoad.nominal;
    } on MissingPluginException {
      return DeviceLoad.nominal;
    }
  }
}
