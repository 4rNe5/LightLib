// The reader's own Z-Library account, for its download limit instead of
// the anonymous one (a few files a day per network): signed in once, the
// session Z-Library gives (two cookies) is kept in a file of its own in
// the app's private folder - never the password, and neither backups nor
// sync carry it. Book pages and download links are then asked for as
// that account.

// Dart imports:
import 'dart:convert';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:path/path.dart' as p;

// Project imports:
import 'package:openlib/services/storage/app_files.dart';

/// A signed-in session: the two cookies every mirror reads.
@immutable
class ZlibrarySession {
  const ZlibrarySession({
    required this.userId,
    required this.userKey,
    this.email = '',
    this.name = '',
  });

  final String userId;
  final String userKey;
  final String email;
  final String name;

  static const idCookie = 'remix_userid';
  static const keyCookie = 'remix_userkey';

  Map<String, String> get cookies => {idCookie: userId, keyCookie: userKey};

  /// What to call the account: its name, its email, or its number.
  String get label =>
      name.isNotEmpty ? name : (email.isNotEmpty ? email : '#$userId');

  Map<String, String> toJson() =>
      {'id': userId, 'key': userKey, 'email': email, 'name': name};

  static ZlibrarySession? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = '${j['id'] ?? ''}'.trim();
    final key = '${j['key'] ?? ''}'.trim();
    if (id.isEmpty || key.isEmpty) return null;
    return ZlibrarySession(
        userId: id,
        userKey: key,
        email: '${j['email'] ?? ''}',
        name: '${j['name'] ?? ''}');
  }

  /// From cookies (a browser's, after signing in there); null unless
  /// both are there.
  static ZlibrarySession? fromCookies(Map<String, String> cookies) {
    final id = (cookies[idCookie] ?? '').trim();
    final key = (cookies[keyCookie] ?? '').trim();
    if (id.isEmpty || key.isEmpty) return null;
    return ZlibrarySession(userId: id, userKey: key);
  }

  /// From what `/eapi/user/login` or `/eapi/user/profile` answer:
  /// `{"success": 1, "user": {"id": 1, "remix_userkey": "...", ...}}`.
  /// [fallback] supplies the key where the answer has none (the profile).
  static ZlibrarySession? fromApi(Object? data, {ZlibrarySession? fallback}) {
    if (data is! Map || data['user'] is! Map) return null;
    final user = data['user'] as Map;
    final id = '${user['id'] ?? fallback?.userId ?? ''}'.trim();
    final key = '${user['remix_userkey'] ?? fallback?.userKey ?? ''}'.trim();
    if (id.isEmpty || key.isEmpty) return null;
    return ZlibrarySession(
      userId: id,
      userKey: key,
      email: '${user['email'] ?? fallback?.email ?? ''}',
      name: '${user['name'] ?? fallback?.name ?? ''}',
    );
  }
}

/// How many files the account took today, and how many a day it may.
@immutable
class ZlibraryLimits {
  const ZlibraryLimits({required this.today, required this.limit});
  final int today;
  final int limit;

  int get left => (limit - today).clamp(0, limit);

  static ZlibraryLimits? fromApi(Object? data) {
    if (data is! Map || data['user'] is! Map) return null;
    final user = data['user'] as Map;
    final today = int.tryParse('${user['downloads_today'] ?? ''}');
    final limit = int.tryParse('${user['downloads_limit'] ?? ''}');
    if (today == null || limit == null) return null;
    return ZlibraryLimits(today: today, limit: limit);
  }
}

/// The cookies in a `Cookie` header, by name.
Map<String, String> parseCookieHeader(String? header) {
  final out = <String, String>{};
  for (final part in (header ?? '').split(';')) {
    final eq = part.indexOf('=');
    if (eq <= 0) continue;
    out[part.substring(0, eq).trim()] = part.substring(eq + 1).trim();
  }
  return out;
}

String cookieHeader(Map<String, String> cookies) =>
    cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

class ZlibraryAccount extends ChangeNotifier {
  ZlibraryAccount();

  static final ZlibraryAccount instance = ZlibraryAccount();

  /// Where the session is kept (replaceable in tests).
  @visibleForTesting
  Future<String> Function() path = () async =>
      p.join(await AppFiles.instance.supportPath(), 'zlibrary_session');

  ZlibrarySession? _session;
  Future<void>? _loading;

  ZlibrarySession? get session => _session;
  bool get signedIn => _session != null;

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final text = await AppFiles.instance.readString(await path());
      if (text != null && text.trim().isNotEmpty) {
        _session = ZlibrarySession.fromJson(jsonDecode(text));
      }
    } catch (_) {
      // Unreadable: signed out.
    }
    notifyListeners();
  }

  Future<void> signIn(ZlibrarySession session) async {
    await load();
    _session = session;
    notifyListeners();
    try {
      await AppFiles.instance
          .writeString(await path(), jsonEncode(session.toJson()));
    } catch (_) {
      // Kept for this run of the app.
    }
  }

  Future<void> signOut() async {
    await load();
    _session = null;
    notifyListeners();
    try {
      await AppFiles.instance.delete(await path());
    } catch (_) {}
  }

  @visibleForTesting
  void debugSet(ZlibrarySession? session) {
    _loading = Future.value();
    _session = session;
    notifyListeners();
  }
}
