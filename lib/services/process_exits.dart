// How the app's earlier runs ended, from Android (11+). A crash inside a
// native library - the translation engine - kills the process before
// anything reaches the app's log, which is kept in memory; Android keeps
// the reason, and for a native crash its abort message and backtrace.

// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter/services.dart';

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/logger.dart';

class ProcessExit {
  const ProcessExit({
    required this.timestamp,
    required this.reason,
    this.description,
    this.trace,
    this.beforeUpdate = false,
    this.metadata = const {},
  });

  factory ProcessExit.fromMap(Map<Object?, Object?> m) => ProcessExit(
        timestamp: DateTime.fromMillisecondsSinceEpoch(
            (m['timestamp'] as num?)?.toInt() ?? 0),
        reason: m['reason'] as String? ?? 'unknown',
        description: m['description'] as String?,
        trace: m['trace'] as String?,
        beforeUpdate: m['beforeUpdate'] == true,
        metadata: {
          for (final key in ['status', 'importance', 'pssKb', 'rssKb'])
            if (m[key] != null) key: m[key],
        },
      );

  final DateTime timestamp;

  /// Android's reason: crash_native, low_memory, signaled, anr,
  /// user_requested, ...
  final String reason;
  final String? description;
  final String? trace;

  /// Ended in a version of the app older than the one installed now.
  final bool beforeUpdate;
  final Map<String, Object?> metadata;

  /// Ended by the user (swiped away, force-stopped) rather than by a
  /// failure.
  bool get byUser =>
      reason == 'user_requested' ||
      reason == 'user_stopped' ||
      reason == 'exit_self';

  /// Ended by a failure of the app itself: a crash, or killed while on
  /// screen (memory, a signal). Reclaimed while in the background is
  /// ordinary on Android.
  bool get likelyCrash {
    if (reason == 'crash_native' || reason == 'crash' || reason == 'anr') {
      return true;
    }
    if (byUser) return false;
    final importance = metadata['importance'];
    // 100 foreground, 125 foreground service, 200 visible.
    return importance is num && importance <= 200;
  }
}

class ProcessExits {
  ProcessExits._();

  static const _channel = MethodChannel('lightlib/background_translation');
  static const _loggedPref = 'processExitLoggedAt';

  static Future<List<ProcessExit>>? _exits;

  /// The last few exits, newest first (empty off Android or before 11).
  static Future<List<ProcessExit>> recent() => _exits ??= _read();

  static Future<List<ProcessExit>> _read() async {
    if (!Platform.isAndroid) return const [];
    try {
      final raw = await _channel.invokeListMethod<Object?>('lastExits');
      return [
        for (final m in raw ?? const [])
          if (m is Map) ProcessExit.fromMap(m),
      ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    } catch (_) {
      return const [];
    }
  }

  /// How the previous run ended, or null when unknown.
  static Future<ProcessExit?> previous() async {
    final exits = await recent();
    return exits.isEmpty ? null : exits.first;
  }

  /// Logs the exits not logged before, so an exported log shows why the
  /// app closed last time.
  static Future<void> logNew() async {
    final exits = await recent();
    if (exits.isEmpty) return;
    final db = MyLibraryDb.instance;
    final seen = await db.getPreference(_loggedPref).catchError((_) => null);
    final since = seen is num ? seen.toInt() : int.tryParse('$seen') ?? 0;
    final logger = AppLogger();
    for (final e in exits.reversed) {
      if (e.timestamp.millisecondsSinceEpoch <= since) continue;
      final failed = !e.byUser;
      final metadata = <String, dynamic>{
        'at': e.timestamp.toIso8601String(),
        'reason': e.reason,
        if (e.beforeUpdate) 'beforeUpdate': true,
        if (e.description != null) 'description': e.description,
        ...e.metadata,
        if (e.trace != null && e.trace!.isNotEmpty) 'trace': e.trace,
      };
      if (failed) {
        logger.warning('Previous run ended: ${e.reason}',
            tag: 'App', metadata: metadata);
      } else {
        logger.info('Previous run ended: ${e.reason}',
            tag: 'App', metadata: metadata);
      }
    }
    await db
        .savePreference(
            _loggedPref, '${exits.first.timestamp.millisecondsSinceEpoch}')
        .catchError((_) {});
  }
}
