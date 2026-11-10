// Sync with the owner's Supabase project, for the app and the web build:
// Google sign-in, when runs happen (start, coming back to the app, opening
// and leaving a book, while reading, by hand), how far a run is (in the
// settings and as a notification) and what the last one did.

// Dart imports:
import 'dart:async';
import 'dart:ui' show Locale, PlatformDispatcher;

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/database.dart';
import 'package:openlib/services/logger.dart';
import 'package:openlib/services/sync/library_sync_local.dart';
import 'package:openlib/services/sync/supabase_remote.dart';
import 'package:openlib/services/sync/sync_engine.dart';
import 'package:openlib/services/sync/sync_notifier.dart';
import 'package:openlib/services/translation/glossary_service.dart';
import 'package:openlib/services/translation/translation_cache.dart';

/// The owner's project (the publishable key is meant for apps; the tables
/// only answer the owner - supabase/migrations/).
class SyncConfig {
  static const url = 'https://ggagbhdqdrmomrednwfx.supabase.co';
  static const publishableKey =
      'sb_publishable_7KVy0_UhuKc4YscNOk9XuA_UvUELu2P';

  /// Where the browser returns after Google sign-in on the phone
  /// (AndroidManifest.xml).
  static const androidRedirect = 'dev.arne5.lightlib://login-callback';
}

/// Preference: sync on its own (1, the default) or only by hand (0).
const syncAutoPref = 'syncAuto';

/// What a run says on screen and in its notification.
String syncProgressText(AppLocalizations l10n, SyncProgress progress) {
  final step = switch (progress.stage) {
    SyncStage.checking => l10n.syncStageChecking,
    SyncStage.uploading =>
      l10n.syncStageUploading(progress.done, progress.total),
    SyncStage.downloading =>
      l10n.syncStageDownloading(progress.done, progress.total),
    SyncStage.translations =>
      l10n.syncStageTranslations(progress.done, progress.total),
  };
  final title = progress.title;
  return title == null || title.isEmpty ? step : '$step · $title';
}

String syncSummaryText(AppLocalizations l10n, SyncReport report) =>
    report.changedAnything
        ? l10n.syncSummary(
            report.uploaded,
            report.downloaded,
            report.positionsSent,
            report.positionsReceived,
            report.translationsSent,
            report.translationsReceived,
            report.glossariesSent,
            report.glossariesReceived,
          )
        : l10n.syncUpToDate;

class SyncService extends ChangeNotifier {
  SyncService._();
  static final SyncService instance = SyncService._();

  final AppLogger _logger = AppLogger();
  bool _ready = false;
  bool _auto = true;
  bool _running = false;
  bool _again = false;
  bool _againFull = false;
  DateTime? lastRun;
  SyncReport? lastReport;
  String? lastError;
  SyncProgress? _progress;
  Timer? _positionTimer;
  StreamSubscription<AuthState>? _auth;
  final StreamController<SyncReport> _finished =
      StreamController<SyncReport>.broadcast();

  /// Called when a book came or went here, and after a run that changed
  /// something here (the library refreshes).
  VoidCallback? onLocalChanges;

  /// Counts runs that brought translations or glossaries (an open book
  /// shows them).
  final ValueNotifier<int> arrived = ValueNotifier(0);

  /// Notifications; tests swap it.
  @visibleForTesting
  SyncNotifier get notifier => _notifier ?? SyncNotifier.instance;
  set notifier(SyncNotifier value) => _notifier = value;
  SyncNotifier? _notifier;

  bool get ready => _ready;
  bool get running => _running;
  bool get auto => _auto;

  /// Where the run under way is; null when none runs.
  SyncProgress? get progress => _running ? _progress : null;

  /// Each full run's report as it ends.
  Stream<SyncReport> get finished => _finished.stream;
  User? get user => _ready ? Supabase.instance.client.auth.currentUser : null;
  bool get signedIn => user != null;

  Future<void>? _initializing;

  /// Sets up the client and the hooks; safe to call more than once.
  Future<void> init() => _initializing ??= _init();

  Future<void> _init() async {
    try {
      await Supabase.initialize(
        url: SyncConfig.url,
        publishableKey: SyncConfig.publishableKey,
      );
      _ready = true;
    } catch (e) {
      lastError = '$e';
      _initializing = null;
      _logger.warning('Sync not available', tag: 'Sync', error: e);
      notifyListeners();
      return;
    }
    _auto = await MyLibraryDb.instance
            .getPreference(syncAutoPref)
            .catchError((_) => null) !=
        0;
    MyLibraryDb.onPositionSaved = _onPositionSaved;
    TranslationCache.onChanged = _onTranslationsSaved;
    GlossaryService.onSaved = _onGlossarySaved;
    _auth = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      notifyListeners();
      if (state.event == AuthChangeEvent.signedIn) {
        // Just signed in: the first run, told about like one by hand.
        unawaited(syncNow(manual: true));
      }
    });
    notifyListeners();
    if (signedIn && _auto) unawaited(syncNow());
  }

  Future<void> signIn() async {
    notifier.askPermission();
    if (!_ready) await init();
    if (!_ready) return;
    await Supabase.instance.client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? Uri.base.origin : SyncConfig.androidRedirect,
      authScreenLaunchMode:
          kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
    );
  }

  Future<void> signOut() async {
    if (!_ready) return;
    await Supabase.instance.client.auth.signOut();
    notifyListeners();
  }

  Future<void> setAuto(bool on) async {
    _auto = on;
    notifyListeners();
    await MyLibraryDb.instance
        .savePreference(syncAutoPref, on ? 1 : 0)
        .catchError((_) {});
  }

  /// The button: runs now, with a notification of how it ended.
  Future<SyncReport?> syncByHand() {
    notifier.askPermission();
    return syncNow(manual: true);
  }

  /// Runs now (or right after the run under way). [quick] leaves book
  /// files alone (the run while reading). A full run that moves books or
  /// translations shows its progress as a notification and says how it
  /// ended; [manual] says so even when nothing moved.
  Future<SyncReport?> syncNow({bool quick = false, bool manual = false}) async {
    if (!signedIn) return null;
    if (_running) {
      _again = true;
      _againFull |= !quick;
      return null;
    }
    _running = true;
    _progress = const SyncProgress(SyncStage.checking);
    notifyListeners();
    final l10n = await _l10n();
    final title = l10n.syncNotifyTitle;
    var notified = false;
    SyncReport? report;
    try {
      report = await SyncEngine(
        local: LibrarySyncLocal(),
        remote: SupabaseRemote(Supabase.instance.client),
        onProgress: (progress) {
          _progress = progress;
          notifyListeners();
          if (!quick && (progress.transfers || notified)) {
            notified = true;
            unawaited(notifier.progress(
              title: title,
              text: syncProgressText(l10n, progress),
              done: progress.done,
              total: progress.total,
            ));
          }
        },
        onLocalChange: () => onLocalChanges?.call(),
      ).run(quick: quick);
      lastReport = report;
      lastRun = DateTime.now();
      lastError = report.errors.isEmpty ? null : report.errors.first;
      _logger.info('Synced',
          tag: 'Sync', metadata: {'report': '$report', 'quick': quick});
      if (report.changedHere) onLocalChanges?.call();
      if (report.translationsReceived > 0 || report.glossariesReceived > 0) {
        arrived.value++;
      }
      if (!quick) {
        if (notified || manual || report.errors.isNotEmpty) {
          await notifier.finished(
            title: report.errors.isEmpty
                ? l10n.syncDoneTitle
                : l10n.syncFailed(report.errors.first),
            text: syncSummaryText(l10n, report),
          );
        }
        _finished.add(report);
      }
    } catch (e) {
      lastError = '$e';
      _logger.warning('Sync failed', tag: 'Sync', error: e);
      if (!quick && (notified || manual)) {
        await notifier.finished(
            title: l10n.syncNotifyTitle, text: l10n.syncFailed('$e'));
      }
    } finally {
      _running = false;
      _progress = null;
      notifyListeners();
    }
    if (_again) {
      final full = _againFull;
      _again = false;
      _againFull = false;
      unawaited(syncNow(quick: !full));
    }
    return report;
  }

  /// A book being opened: its position, translations and glossary from
  /// the other devices first (and this device's changes out). Runs next
  /// to a full run if one is under way.
  Future<void> syncBook(String fileName) async {
    if (!signedIn) return;
    try {
      final report = await SyncEngine(
        local: LibrarySyncLocal(),
        remote: SupabaseRemote(Supabase.instance.client),
      ).runBook(fileName);
      if (report == null) return;
      _logger.info('Synced the book',
          tag: 'Sync', metadata: {'book': fileName, 'report': '$report'});
      if (report.translationsReceived > 0 || report.glossariesReceived > 0) {
        arrived.value++;
      }
    } catch (e) {
      _logger.warning('Book not synced', tag: 'Sync', error: e);
    }
  }

  /// The reader closed: send what was read and translated.
  void readerClosed() {
    if (_auto) unawaited(syncNow(quick: true));
  }

  /// Back in the app.
  void resumed() {
    if (_auto) unawaited(syncNow());
  }

  Future<AppLocalizations> _l10n() async {
    final saved = await MyLibraryDb.instance
        .getPreference('locale')
        .catchError((_) => null);
    final code = saved is String && saved.isNotEmpty
        ? saved
        : PlatformDispatcher.instance.locale.languageCode;
    final locale = AppLocalizations.supportedLocales.firstWhere(
        (l) => l.languageCode == code,
        orElse: () => const Locale('en'));
    return lookupAppLocalizations(locale);
  }

  /// While reading: positions, translations and glossaries go out 20 s
  /// after the last page turn.
  void _onPositionSaved(String fileName) {
    if (!_auto || !signedIn) return;
    _positionTimer?.cancel();
    _positionTimer = Timer(
        const Duration(seconds: 20), () => unawaited(syncNow(quick: true)));
  }

  void _onTranslationsSaved(String path) {
    unawaited(MyLibraryDb.instance
        .setSyncState('trdirty:${p.normalize(path)}',
            '${DateTime.now().microsecondsSinceEpoch}')
        .catchError((_) {}));
  }

  void _onGlossarySaved(String bookFile) {
    unawaited(MyLibraryDb.instance
        .setSyncState(
            'gls:$bookFile', '${DateTime.now().millisecondsSinceEpoch}')
        .catchError((_) {}));
  }

  @override
  void dispose() {
    _auth?.cancel();
    _positionTimer?.cancel();
    _finished.close();
    arrived.dispose();
    super.dispose();
  }
}
