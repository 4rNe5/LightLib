// What the reader chose for Gemini (engine, key, model, safety filters)
// and what it has used today (requests, tokens, blocked paragraphs, the
// limits the API reported), kept on the device.

// Dart imports:
import 'dart:convert';
import 'dart:io';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/translation/gemini/gemini_api.dart';

/// Preference: `device` (the model on the phone) or `gemini`.
const translationEnginePref = 'translationEngine';
const geminiModelPref = 'geminiModel';
const geminiSafetyPref = 'geminiSafety';
const geminiConcurrencyPref = 'geminiConcurrency';
const geminiThinkingPref = 'geminiThinking';

/// Preference: when Gemini cannot translate (the day's quota, a filter, no
/// connection), the model on the phone does (1, the default) or the
/// paragraph waits (0).
const geminiDeviceFallbackPref = 'geminiDeviceFallback';
const geminiUsagePref = 'geminiUsage';

/// Today's use, by the API's quota day (Pacific time).
@immutable
class GeminiUsage {
  const GeminiUsage({
    required this.day,
    this.requests = 0,
    this.promptTokens = 0,
    this.outputTokens = 0,
    this.paragraphs = 0,
    this.blockedSafety = 0,
    this.blockedProhibited = 0,
    this.onDevice = 0,
    this.exhausted = false,
    this.dailyLimit,
    this.minuteLimit,
    this.freeTier,
  });

  final String day;
  final int requests;
  final int promptTokens;

  /// Answer and thinking tokens (both billed as output).
  final int outputTokens;
  final int paragraphs;

  /// Paragraphs a filter blocked (the categories in settings), and those
  /// the API refuses whatever is set (left in the original).
  final int blockedSafety;
  final int blockedProhibited;

  /// Paragraphs the model on the phone translated instead.
  final int onDevice;

  /// The day's requests are used up.
  final bool exhausted;

  /// The limits the API named when one was reached (requests per day and
  /// per minute), and whether they are the free tier's. Null: not seen.
  final int? dailyLimit;
  final int? minuteLimit;
  final bool? freeTier;

  GeminiUsage copyWith({
    int? requests,
    int? promptTokens,
    int? outputTokens,
    int? paragraphs,
    int? blockedSafety,
    int? blockedProhibited,
    int? onDevice,
    bool? exhausted,
    int? dailyLimit,
    int? minuteLimit,
    bool? freeTier,
  }) =>
      GeminiUsage(
        day: day,
        requests: requests ?? this.requests,
        promptTokens: promptTokens ?? this.promptTokens,
        outputTokens: outputTokens ?? this.outputTokens,
        paragraphs: paragraphs ?? this.paragraphs,
        blockedSafety: blockedSafety ?? this.blockedSafety,
        blockedProhibited: blockedProhibited ?? this.blockedProhibited,
        onDevice: onDevice ?? this.onDevice,
        exhausted: exhausted ?? this.exhausted,
        dailyLimit: dailyLimit ?? this.dailyLimit,
        minuteLimit: minuteLimit ?? this.minuteLimit,
        freeTier: freeTier ?? this.freeTier,
      );

  Map<String, Object?> toJson() => {
        'day': day,
        'requests': requests,
        'promptTokens': promptTokens,
        'outputTokens': outputTokens,
        'paragraphs': paragraphs,
        'blockedSafety': blockedSafety,
        'blockedProhibited': blockedProhibited,
        'onDevice': onDevice,
        'exhausted': exhausted,
        'dailyLimit': dailyLimit,
        'minuteLimit': minuteLimit,
        'freeTier': freeTier,
      };

  /// [json] as saved, or a fresh day when it is another day's (limits
  /// and the tier carry over: they rarely change).
  factory GeminiUsage.fromJson(Object? json, String today) {
    if (json is String) {
      try {
        json = jsonDecode(json);
      } catch (_) {
        json = null;
      }
    }
    if (json is! Map) return GeminiUsage(day: today);
    int n(String k) =>
        json is Map && json[k] is num ? (json[k] as num).toInt() : 0;
    int? opt(String k) =>
        json is Map && json[k] is num ? (json[k] as num).toInt() : null;
    final free = json['freeTier'] is bool ? json['freeTier'] as bool : null;
    if (json['day'] != today) {
      return GeminiUsage(
          day: today,
          dailyLimit: opt('dailyLimit'),
          minuteLimit: opt('minuteLimit'),
          freeTier: free);
    }
    return GeminiUsage(
      day: today,
      requests: n('requests'),
      promptTokens: n('promptTokens'),
      outputTokens: n('outputTokens'),
      paragraphs: n('paragraphs'),
      blockedSafety: n('blockedSafety'),
      blockedProhibited: n('blockedProhibited'),
      onDevice: n('onDevice'),
      exhausted: json['exhausted'] == true,
      dailyLimit: opt('dailyLimit'),
      minuteLimit: opt('minuteLimit'),
      freeTier: free,
    );
  }
}

class GeminiSettings extends ChangeNotifier {
  GeminiSettings._();
  static final GeminiSettings instance = GeminiSettings._();

  /// Where the key is kept: a file of its own in the app's private
  /// folder, so library backups (the database) never carry it.
  @visibleForTesting
  Future<File> Function() keyFile = () async => File(
      p.join((await getApplicationSupportDirectory()).path, 'gemini_api_key'));

  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  bool _useGemini = false;
  String _key = '';
  GeminiModel _model = geminiModels.first;
  Map<GeminiHarm, GeminiBlock> _safety = {
    for (final h in GeminiHarm.values) h: GeminiBlock.off
  };
  int _concurrency = 3;
  GeminiThinking _thinking = GeminiThinking.speed;
  bool _deviceFallback = true;
  GeminiUsage? _usage;
  Future<void>? _loading;

  bool get useGemini => _useGemini;
  bool get hasKey => _key.isNotEmpty;

  /// Gemini translates (chosen, and a key is set).
  bool get active => _useGemini && hasKey;
  String get apiKey => _key;
  GeminiModel get model => _model;
  Map<GeminiHarm, GeminiBlock> get safety => Map.unmodifiable(_safety);
  int get concurrency => _concurrency;
  GeminiThinking get thinking => _thinking;
  bool get deviceFallback => _deviceFallback;

  GeminiUsage get usage {
    final today = quotaDay(clock());
    final u = _usage;
    if (u == null || u.day != today) {
      return _usage = GeminiUsage.fromJson(u?.toJson(), today);
    }
    return u;
  }

  /// The key's last characters, for showing which one is set.
  String get keyHint =>
      _key.length <= 4 ? '' : '…${_key.substring(_key.length - 4)}';

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final db = MyLibraryDb.instance;
    Future<Object?> pref(String k) =>
        db.getPreference(k).catchError((_) => null);
    _useGemini = await pref(translationEnginePref) == 'gemini';
    _model = geminiModelFor(await pref(geminiModelPref) as String?);
    _safety = decodeSafety(await pref(geminiSafetyPref));
    final c = int.tryParse('${await pref(geminiConcurrencyPref)}');
    if (c != null) _concurrency = c.clamp(1, 8);
    _deviceFallback = await pref(geminiDeviceFallbackPref) != 0;
    _thinking = GeminiThinking.parse(await pref(geminiThinkingPref));
    _usage =
        GeminiUsage.fromJson(await pref(geminiUsagePref), quotaDay(clock()));
    try {
      final f = await keyFile();
      if (await f.exists()) _key = (await f.readAsString()).trim();
    } catch (_) {}
    notifyListeners();
  }

  static Map<GeminiHarm, GeminiBlock> decodeSafety(Object? saved) {
    Map? map;
    if (saved is String) {
      try {
        final d = jsonDecode(saved);
        if (d is Map) map = d;
      } catch (_) {}
    }
    return {
      for (final h in GeminiHarm.values) h: GeminiBlock.parse(map?[h.name]),
    };
  }

  Future<void> _save(String key, Object value) =>
      MyLibraryDb.instance.savePreference(key, value).catchError((_) {});

  Future<void> setUseGemini(bool on) async {
    _useGemini = on;
    notifyListeners();
    await _save(translationEnginePref, on ? 'gemini' : 'device');
  }

  Future<void> setKey(String key) async {
    _key = key.trim();
    notifyListeners();
    try {
      final f = await keyFile();
      if (_key.isEmpty) {
        if (await f.exists()) await f.delete();
      } else {
        await f.parent.create(recursive: true);
        await f.writeAsString(_key, flush: true);
      }
    } catch (_) {}
  }

  Future<void> setModel(GeminiModel model) async {
    _model = model;
    notifyListeners();
    await _save(geminiModelPref, model.id);
  }

  Future<void> setSafety(GeminiHarm harm, GeminiBlock block) async {
    _safety = {..._safety, harm: block};
    notifyListeners();
    await _save(
        geminiSafetyPref,
        jsonEncode(
            {for (final e in _safety.entries) e.key.name: e.value.name}));
  }

  Future<void> setConcurrency(int n) async {
    _concurrency = n.clamp(1, 8);
    notifyListeners();
    await _save(geminiConcurrencyPref, _concurrency);
  }

  Future<void> setThinking(GeminiThinking mode) async {
    _thinking = mode;
    notifyListeners();
    await _save(geminiThinkingPref, mode.name);
  }

  Future<void> setDeviceFallback(bool on) async {
    _deviceFallback = on;
    notifyListeners();
    await _save(geminiDeviceFallbackPref, on ? 1 : 0);
  }

  /// Counts one answered request.
  void recordRequest(GeminiResult r, {int paragraphs = 0}) =>
      _update(usage.copyWith(
          requests: usage.requests + 1,
          promptTokens: usage.promptTokens + r.promptTokens,
          outputTokens: usage.outputTokens + r.billedOutput,
          paragraphs: usage.paragraphs + paragraphs));

  void recordBlocked(GeminiBlockKind kind, int paragraphs) =>
      _update(kind == GeminiBlockKind.safety
          ? usage.copyWith(blockedSafety: usage.blockedSafety + paragraphs)
          : usage.copyWith(
              blockedProhibited: usage.blockedProhibited + paragraphs));

  void recordOnDevice(int paragraphs) =>
      _update(usage.copyWith(onDevice: usage.onDevice + paragraphs));

  /// What a limit error said: the limit, the tier, a used-up day.
  void recordLimit(GeminiError e) {
    var u = usage;
    if (e.freeTier != null) u = u.copyWith(freeTier: e.freeTier);
    // Request limits only (a token limit is another number).
    final requests = e.quotaId?.contains('Requests') ?? false;
    if (e.quotaLimit != null && requests && e.perDay) {
      u = u.copyWith(dailyLimit: e.quotaLimit);
    }
    if (e.quotaLimit != null && requests && e.perMinute) {
      u = u.copyWith(minuteLimit: e.quotaLimit);
    }
    if (e.kind == GeminiErrorKind.quotaExhausted) {
      u = u.copyWith(exhausted: true);
    }
    _update(u);
  }

  DateTime _savedAt = DateTime.fromMillisecondsSinceEpoch(0);

  void _update(GeminiUsage u) {
    _usage = u;
    notifyListeners();
    // At most every few seconds while a book goes through.
    final now = clock();
    if (now.difference(_savedAt) > const Duration(seconds: 3)) {
      _savedAt = now;
      _save(geminiUsagePref, jsonEncode(u.toJson()));
    }
  }

  /// For tests: settings without the database or the key file.
  @visibleForTesting
  void debugSet({
    bool? useGemini,
    String? key,
    GeminiModel? model,
    GeminiUsage? usage,
    bool? deviceFallback,
    int? concurrency,
    GeminiThinking? thinking,
  }) {
    if (useGemini != null) _useGemini = useGemini;
    if (key != null) _key = key;
    if (model != null) _model = model;
    if (usage != null) _usage = usage;
    if (deviceFallback != null) _deviceFallback = deviceFallback;
    if (concurrency != null) _concurrency = concurrency;
    if (thinking != null) _thinking = thinking;
    _loading = Future.value();
    notifyListeners();
  }
}
