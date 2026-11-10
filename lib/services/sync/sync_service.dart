// Sync with the owner's Supabase project, for the app and the web build:
// Google sign-in, when runs happen (start, coming back to the app, leaving
// the reader, a position saved, by hand) and what the last one did.

// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/logger.dart';
import 'package:openlib/services/sync/library_sync_local.dart';
import 'package:openlib/services/sync/supabase_remote.dart';
import 'package:openlib/services/sync/sync_engine.dart';
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
  Timer? _positionTimer;
  StreamSubscription<AuthState>? _auth;

  /// Called after a run that changed something here (the library
  /// refreshes).
  VoidCallback? onLocalChanges;

  bool get ready => _ready;
  bool get running => _running;
  bool get auto => _auto;
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
      if (state.event == AuthChangeEvent.signedIn && _auto) {
        unawaited(syncNow());
      }
    });
    notifyListeners();
    if (signedIn && _auto) unawaited(syncNow());
  }

  Future<void> signIn() async {
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

  /// Runs now (or right after the run under way); [positionsOnly] for the
  /// quick run after reading.
  Future<SyncReport?> syncNow({bool positionsOnly = false}) async {
    if (!signedIn) return null;
    if (_running) {
      _again = true;
      _againFull |= !positionsOnly;
      return null;
    }
    _running = true;
    notifyListeners();
    SyncReport? report;
    try {
      report = await SyncEngine(
        local: LibrarySyncLocal(),
        remote: SupabaseRemote(Supabase.instance.client),
      ).run(quick: positionsOnly);
      lastReport = report;
      lastRun = DateTime.now();
      lastError = report.errors.isEmpty ? null : report.errors.first;
      _logger.info('Synced', tag: 'Sync', metadata: {'report': '$report'});
      if (report.changedHere) onLocalChanges?.call();
    } catch (e) {
      lastError = '$e';
      _logger.warning('Sync failed', tag: 'Sync', error: e);
    } finally {
      _running = false;
      notifyListeners();
    }
    if (_again) {
      final full = _againFull;
      _again = false;
      _againFull = false;
      unawaited(syncNow(positionsOnly: !full));
    }
    return report;
  }

  /// The reader closed: send what was read and translated.
  void readerClosed() {
    if (_auto) unawaited(syncNow());
  }

  /// Back in the app.
  void resumed() {
    if (_auto) unawaited(syncNow());
  }

  void _onPositionSaved(String fileName) {
    if (!_auto || !signedIn) return;
    _positionTimer?.cancel();
    _positionTimer = Timer(const Duration(seconds: 20),
        () => unawaited(syncNow(positionsOnly: true)));
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
    super.dispose();
  }
}
