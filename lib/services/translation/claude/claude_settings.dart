// What the reader chose for Claude (engine, key, workspace, model, how
// much it thinks) and what each model has used today, kept on the
// device. The counterpart of `gemini_settings.dart`; the key has a file
// of its own in the app's private folder and is in no backup.

// Dart imports:
import 'dart:convert';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:path/path.dart' as p;

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/storage/app_files.dart';
import 'package:openlib/services/translation/claude/claude_api.dart';
import 'package:openlib/services/translation/cloud_engine.dart';
import 'package:openlib/services/translation/gemini/gemini_api.dart';
import 'package:openlib/services/translation/gemini/gemini_settings.dart';

const claudeModelPref = 'claudeModel';
const claudeThinkingPref = 'claudeThinking';
const claudeConcurrencyPref = 'claudeConcurrency';
const claudeDeviceFallbackPref = 'claudeDeviceFallback';
const claudePolishPref = 'claudePolish';
const claudeUsagePref = 'claudeUsage';

/// Preference: the workspace a key that is not tied to one is used in
/// (`wrkspc_…`); empty for a key that is.
const claudeWorkspacePref = 'claudeWorkspace';

/// The value of [translationEnginePref] that chooses Claude.
const claudeEngine = 'claude';

class ClaudeSettings extends ChangeNotifier implements CloudSettings {
  ClaudeSettings._();
  static final ClaudeSettings instance = ClaudeSettings._();

  @visibleForTesting
  Future<String> Function() keyPath = () async =>
      p.join(await AppFiles.instance.supportPath(), 'claude_api_key');

  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  bool _useClaude = false;
  String _key = '';
  String _workspace = '';
  ClaudeModel _model = claudeModels.first;
  GeminiThinking _thinking = GeminiThinking.speed;
  int _concurrency = 3;
  bool _deviceFallback = true;
  bool _polish = false;

  /// Today's use by model id, and of it what was read from the cache.
  Map<String, GeminiUsage> _usageBy = {};
  Map<String, int> _cachedBy = {};
  Future<void>? _loading;

  bool get useClaude => _useClaude;
  bool get hasKey => _key.isNotEmpty;

  /// Claude translates (chosen, and a key is set).
  bool get active => _useClaude && hasKey;
  String get apiKey => _key;
  String get workspace => _workspace;
  ClaudeModel get model => _model;
  GeminiThinking get thinking => _thinking;

  @override
  String get engineLabel => 'Claude';
  @override
  int get concurrency => _concurrency;
  @override
  bool get deviceFallback => _deviceFallback;
  @override
  bool get polish => _polish;

  /// No credit left: nothing more is asked until the key is set again or
  /// the day is over.
  @override
  bool get exhausted => usage.exhausted;

  /// Today's use of the model chosen now, and of [model].
  GeminiUsage get usage => usageOf(_model);
  GeminiUsage usageOf(ClaudeModel model) {
    final today = quotaDay(clock());
    final u = _usageBy[model.id];
    if (u == null || u.day != today) {
      _cachedBy.remove(model.id);
      return _usageBy[model.id] = GeminiUsage(day: today);
    }
    return u;
  }

  /// What [model] cost today, in US dollars (what it read from the cache
  /// at the cache's price).
  double costOf(ClaudeModel model) {
    final u = usageOf(model);
    return model.cost(u.promptTokens, u.outputTokens,
        cached: _cachedBy[model.id] ?? 0);
  }

  /// Today's cost of every model together.
  double get costToday => claudeModels.fold(0, (sum, m) => sum + costOf(m));

  /// The other models used today.
  Map<ClaudeModel, GeminiUsage> get otherModelsToday => {
        for (final m in claudeModels)
          if (m.id != _model.id &&
              _usageBy.containsKey(m.id) &&
              usageOf(m).requests > 0)
            m: usageOf(m),
      };

  /// The key's last characters, for showing which one is set.
  String get keyHint =>
      _key.length <= 4 ? '' : '…${_key.substring(_key.length - 4)}';

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final db = MyLibraryDb.instance;
    Future<Object?> pref(String k) =>
        db.getPreference(k).catchError((_) => null);
    _useClaude = await pref(translationEnginePref) == claudeEngine;
    _model = claudeModelFor(await pref(claudeModelPref) as String?);
    _thinking = GeminiThinking.parse(await pref(claudeThinkingPref));
    final c = int.tryParse('${await pref(claudeConcurrencyPref)}');
    if (c != null) _concurrency = c.clamp(1, 8);
    // (The web has no model of its own to fall back on.)
    _deviceFallback = !kIsWeb && await pref(claudeDeviceFallbackPref) != 0;
    _polish = await pref(claudePolishPref) == 1;
    _workspace = '${await pref(claudeWorkspacePref) ?? ''}'.trim();
    _decodeUsage(await pref(claudeUsagePref));
    try {
      _key =
          (await AppFiles.instance.readString(await keyPath()))?.trim() ?? '';
    } catch (_) {}
    notifyListeners();
  }

  void _decodeUsage(Object? saved) {
    Object? json = saved;
    if (json is String) {
      try {
        json = jsonDecode(json);
      } catch (_) {
        json = null;
      }
    }
    final today = quotaDay(clock());
    final models = json is Map ? json['models'] : null;
    final cached = json is Map ? json['cached'] : null;
    _usageBy = {
      if (models is Map)
        for (final e in models.entries)
          '${e.key}': GeminiUsage.fromJson(e.value, today),
    };
    _cachedBy = {
      if (cached is Map)
        for (final e in cached.entries)
          if (e.value is num && (_usageBy['${e.key}']?.requests ?? 0) > 0)
            '${e.key}': (e.value as num).toInt(),
    };
  }

  Future<void> _save(String key, Object value) =>
      MyLibraryDb.instance.savePreference(key, value).catchError((_) {});

  /// Chooses Claude (or, with false, the model on the phone). Choosing
  /// another engine elsewhere goes through [engineChosen].
  Future<void> setUseClaude(bool on) async {
    _useClaude = on;
    if (on) GeminiSettings.instance.engineChosen(gemini: false);
    notifyListeners();
    await _save(translationEnginePref, on ? claudeEngine : 'device');
  }

  /// Another engine was chosen ([claude]: this one was).
  void engineChosen({required bool claude}) {
    if (_useClaude == claude) return;
    _useClaude = claude;
    notifyListeners();
  }

  /// Keeps [key] (and the [workspace] it is used in, for a key that is
  /// not tied to one). A used-up credit is forgotten: the new key may
  /// have some.
  Future<void> setKey(String key, {String? workspace}) async {
    _key = key.trim();
    if (workspace != null) {
      _workspace = workspace.trim();
      await _save(claudeWorkspacePref, _workspace);
    }
    for (final id in _usageBy.keys.toList()) {
      _usageBy[id] = _usageBy[id]!.copyWith(exhausted: false);
    }
    notifyListeners();
    await _keepKey();
    onKeyChanged?.call();
  }

  Future<void> _keepKey() async {
    try {
      final path = await keyPath();
      if (_key.isEmpty) {
        await AppFiles.instance.delete(path);
      } else {
        await AppFiles.instance.writeString(path, _key);
      }
    } catch (_) {}
  }

  /// The key was typed or removed here (sync passes it on to the owner's
  /// other devices).
  static void Function()? onKeyChanged;

  /// The key and its workspace as the devices share them: "" without a
  /// key.
  String get sharedValue => _key.isEmpty
      ? ''
      : jsonEncode({
          'key': _key,
          if (_workspace.isNotEmpty) 'workspace': _workspace,
        });

  /// A key set on another device ("" = removed there): kept without
  /// being announced again.
  Future<void> applySynced(String value) async {
    await load();
    var key = '', workspace = '';
    if (value.trim().isNotEmpty) {
      try {
        final json = jsonDecode(value);
        if (json is Map) {
          key = '${json['key'] ?? ''}'.trim();
          workspace = '${json['workspace'] ?? ''}'.trim();
        }
      } catch (_) {
        key = value.trim();
      }
    }
    if (key == _key && workspace == _workspace) return;
    _key = key;
    _workspace = workspace;
    for (final id in _usageBy.keys.toList()) {
      _usageBy[id] = _usageBy[id]!.copyWith(exhausted: false);
    }
    notifyListeners();
    await _save(claudeWorkspacePref, _workspace);
    await _keepKey();
  }

  Future<void> setModel(ClaudeModel model) async {
    _model = model;
    notifyListeners();
    await _save(claudeModelPref, model.id);
  }

  Future<void> setThinking(GeminiThinking mode) async {
    _thinking = mode;
    notifyListeners();
    await _save(claudeThinkingPref, mode.name);
  }

  Future<void> setConcurrency(int n) async {
    _concurrency = n.clamp(1, 8);
    notifyListeners();
    await _save(claudeConcurrencyPref, _concurrency);
  }

  Future<void> setDeviceFallback(bool on) async {
    _deviceFallback = on;
    notifyListeners();
    await _save(claudeDeviceFallbackPref, on ? 1 : 0);
  }

  Future<void> setPolish(bool on) async {
    _polish = on;
    notifyListeners();
    await _save(claudePolishPref, on ? 1 : 0);
  }

  /// Counts one request [model] answered ([cached]: tokens of its prompt
  /// read from the cache).
  void recordRequest(GeminiResult r,
      {int paragraphs = 0, ClaudeModel? model, int cached = 0}) {
    final m = model ?? _model;
    final u = usageOf(m);
    _cachedBy[m.id] = (_cachedBy[m.id] ?? 0) + cached;
    _update(
        m,
        u.copyWith(
            requests: u.requests + 1,
            promptTokens: u.promptTokens + r.promptTokens,
            outputTokens: u.outputTokens + r.billedOutput,
            paragraphs: u.paragraphs + paragraphs));
  }

  @override
  void recordBlocked(GeminiBlockKind kind, int paragraphs) => _update(
      _model,
      kind == GeminiBlockKind.safety
          ? usage.copyWith(blockedSafety: usage.blockedSafety + paragraphs)
          : usage.copyWith(
              blockedProhibited: usage.blockedProhibited + paragraphs));

  @override
  void recordOnDevice(int paragraphs) =>
      _update(_model, usage.copyWith(onDevice: usage.onDevice + paragraphs));

  /// The credit ran out ([GeminiErrorKind.quotaExhausted]).
  void recordLimit(GeminiError e, {ClaudeModel? model}) {
    if (e.kind != GeminiErrorKind.quotaExhausted) return;
    // Credit is the key's, not a model's.
    for (final m in claudeModels) {
      _usageBy[m.id] = usageOf(m).copyWith(exhausted: true);
    }
    _update(model ?? _model, usageOf(model ?? _model));
  }

  DateTime _savedAt = DateTime.fromMillisecondsSinceEpoch(0);

  void _update(ClaudeModel model, GeminiUsage u) {
    _usageBy[model.id] = u;
    notifyListeners();
    final now = clock();
    if (now.difference(_savedAt) > const Duration(seconds: 3)) {
      _savedAt = now;
      _save(
          claudeUsagePref,
          jsonEncode({
            'models': {
              for (final e in _usageBy.entries) e.key: e.value.toJson(),
            },
            'cached': _cachedBy,
          }));
    }
  }

  /// For tests: settings without the database or the key file.
  @visibleForTesting
  void debugSet({
    bool? useClaude,
    String? key,
    String? workspace,
    ClaudeModel? model,
    GeminiThinking? thinking,
    bool? deviceFallback,
    int? concurrency,
    bool? polish,
    Map<String, GeminiUsage>? usageBy,
  }) {
    if (useClaude != null) _useClaude = useClaude;
    if (key != null) _key = key;
    if (workspace != null) _workspace = workspace;
    if (model != null) _model = model;
    if (thinking != null) _thinking = thinking;
    if (deviceFallback != null) _deviceFallback = deviceFallback;
    if (concurrency != null) _concurrency = concurrency;
    if (polish != null) _polish = polish;
    if (usageBy != null) {
      _usageBy = {...usageBy};
      _cachedBy = {};
    }
    _loading = Future.value();
    notifyListeners();
  }
}
