// What the reader chose for Gemini (engine, key, model, safety filters)
// and what it has used today (requests, tokens, blocked paragraphs, the
// limits the API reported), kept on the device.

// Dart imports:
import 'dart:convert';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:path/path.dart' as p;

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/storage/app_files.dart';
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

/// Preference: paragraphs that read word for word are sent once more to
/// be said in natural Korean (1; off by default - more requests).
const geminiPolishPref = 'geminiPolish';

/// Today's use of one model, by the API's quota day (Pacific time). The
/// API counts each model's requests apart (3.5 Flash-Lite's are not 3.5
/// Flash's), so the settings keep one of these for each model used.
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
  /// folder, so library backups (the database) never carry it. With sync
  /// signed in it is also shared with the owner's other devices (the
  /// settings table only the owner reads), unless that is turned off.
  @visibleForTesting
  Future<String> Function() keyPath = () async =>
      p.join(await AppFiles.instance.supportPath(), 'gemini_api_key');

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
  bool _polish = false;

  /// Today's use by model id.
  Map<String, GeminiUsage> _usageBy = {};
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

  /// Whether stiff paragraphs are sent once more ([geminiPolishPref]).
  bool get polish => _polish;

  /// Today's use of the model chosen now.
  GeminiUsage get usage => usageOf(_model);

  /// Today's use of [model]: its own requests and tokens, and the limits
  /// the API named for it. Choosing another model shows that model's.
  GeminiUsage usageOf(GeminiModel model) {
    final today = quotaDay(clock());
    final u = _usageBy[model.id];
    if (u == null || u.day != today) {
      return _usageBy[model.id] = GeminiUsage.fromJson(u?.toJson(), today);
    }
    return u;
  }

  /// Whether the key is on the free tier, as far as any model's limit
  /// told (it is the key's, not a model's). Null: not seen.
  bool? get freeTier {
    final own = usage.freeTier;
    if (own != null) return own;
    for (final u in _usageBy.values) {
      if (u.freeTier != null) return u.freeTier;
    }
    return null;
  }

  /// The other models used today, with what each used.
  Map<GeminiModel, GeminiUsage> get otherModelsToday => {
        for (final m in geminiModels)
          if (m.id != _model.id &&
              _usageBy.containsKey(m.id) &&
              usageOf(m).requests > 0)
            m: usageOf(m),
      };

  /// Each model's use as it is saved.
  String _encodeUsage() => jsonEncode({
        'v': 2,
        'models': {
          for (final e in _usageBy.entries) e.key: e.value.toJson(),
        },
      });

  /// What was saved ([saved]), by model. A version before this one kept
  /// one count for whatever model was in use: it is taken for [chosen]'s.
  static Map<String, GeminiUsage> decodeUsage(
      Object? saved, String today, GeminiModel chosen) {
    Object? json = saved;
    if (json is String) {
      try {
        json = jsonDecode(json);
      } catch (_) {
        json = null;
      }
    }
    if (json is! Map) return {};
    final models = json['models'];
    if (models is Map) {
      return {
        for (final e in models.entries)
          '${e.key}': GeminiUsage.fromJson(e.value, today),
      };
    }
    return {chosen.id: GeminiUsage.fromJson(json, today)};
  }

  /// The key's last characters, for showing which one is set.
  String get keyHint =>
      _key.length <= 4 ? '' : '…${_key.substring(_key.length - 4)}';

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final db = MyLibraryDb.instance;
    Future<Object?> pref(String k) =>
        db.getPreference(k).catchError((_) => null);
    // The web has no model of its own: Gemini is the only engine there.
    _useGemini = kIsWeb || await pref(translationEnginePref) == 'gemini';
    _model = geminiModelFor(await pref(geminiModelPref) as String?);
    _safety = decodeSafety(await pref(geminiSafetyPref));
    final c = int.tryParse('${await pref(geminiConcurrencyPref)}');
    if (c != null) _concurrency = c.clamp(1, 8);
    _deviceFallback = !kIsWeb && await pref(geminiDeviceFallbackPref) != 0;
    _thinking = GeminiThinking.parse(await pref(geminiThinkingPref));
    _polish = await pref(geminiPolishPref) == 1;
    _usageBy =
        decodeUsage(await pref(geminiUsagePref), quotaDay(clock()), _model);
    try {
      _key =
          (await AppFiles.instance.readString(await keyPath()))?.trim() ?? '';
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

  /// The key was typed or removed here (sync passes it on to the owner's
  /// other devices).
  static void Function()? onKeyChanged;

  Future<void> setKey(String key) async {
    await _keepKey(key);
    onKeyChanged?.call();
  }

  /// The key another of the owner's devices has (or '' - it was removed
  /// there).
  Future<void> applySynced(String key) async {
    await load();
    if (key.trim() != _key) await _keepKey(key);
  }

  Future<void> _keepKey(String key) async {
    _key = key.trim();
    notifyListeners();
    try {
      final path = await keyPath();
      if (_key.isEmpty) {
        await AppFiles.instance.delete(path);
      } else {
        await AppFiles.instance.writeString(path, _key);
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

  Future<void> setPolish(bool on) async {
    _polish = on;
    notifyListeners();
    await _save(geminiPolishPref, on ? 1 : 0);
  }

  /// Counts one request [model] answered (the model chosen now when not
  /// said).
  void recordRequest(GeminiResult r, {int paragraphs = 0, GeminiModel? model}) {
    final m = model ?? _model;
    final u = usageOf(m);
    _update(
        m,
        u.copyWith(
            requests: u.requests + 1,
            promptTokens: u.promptTokens + r.promptTokens,
            outputTokens: u.outputTokens + r.billedOutput,
            paragraphs: u.paragraphs + paragraphs));
  }

  void recordBlocked(GeminiBlockKind kind, int paragraphs) => _update(
      _model,
      kind == GeminiBlockKind.safety
          ? usage.copyWith(blockedSafety: usage.blockedSafety + paragraphs)
          : usage.copyWith(
              blockedProhibited: usage.blockedProhibited + paragraphs));

  void recordOnDevice(int paragraphs) =>
      _update(_model, usage.copyWith(onDevice: usage.onDevice + paragraphs));

  /// What a limit error said of [model]: the limit, the tier, a used-up
  /// day. Another model's day goes on.
  void recordLimit(GeminiError e, {GeminiModel? model}) {
    final m = model ?? _model;
    var u = usageOf(m);
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
    _update(m, u);
  }

  DateTime _savedAt = DateTime.fromMillisecondsSinceEpoch(0);

  void _update(GeminiModel model, GeminiUsage u) {
    _usageBy[model.id] = u;
    notifyListeners();
    // At most every few seconds while a book goes through.
    final now = clock();
    if (now.difference(_savedAt) > const Duration(seconds: 3)) {
      _savedAt = now;
      _save(geminiUsagePref, _encodeUsage());
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
    bool? polish,
    Map<String, GeminiUsage>? usageBy,
  }) {
    if (useGemini != null) _useGemini = useGemini;
    if (key != null) _key = key;
    if (model != null) _model = model;
    if (usageBy != null) _usageBy = {...usageBy};
    // (The chosen model's.)
    if (usage != null) _usageBy[_model.id] = usage;
    if (deviceFallback != null) _deviceFallback = deviceFallback;
    if (concurrency != null) _concurrency = concurrency;
    if (thinking != null) _thinking = thinking;
    if (polish != null) _polish = polish;
    _loading = Future.value();
    notifyListeners();
  }
}
