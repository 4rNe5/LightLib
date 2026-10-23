// Running a translation model on the device.

// Dart imports:
import 'dart:async';
import 'dart:convert';
import 'dart:io';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:llamadart/llamadart.dart';
import 'package:path_provider/path_provider.dart';

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/epub_package.dart' show readingsIn;
import 'package:openlib/services/logger.dart';
import 'package:openlib/services/process_exits.dart';
import 'package:openlib/services/translation/paragraph_text.dart';
import 'package:openlib/services/translation/translation_model_store.dart';
import 'package:openlib/services/translation/translation_models.dart';
import 'package:openlib/services/translation/translation_scheduler.dart';

export 'package:openlib/services/translation/translation_scheduler.dart'
    show TranslationPriority;

/// Preference: where LiteRT-LM models run - `auto` (GPU, then CPU) or
/// `cpu` (keeps the GPU free for drawing the screen).
const translationDevicePref = 'translationDevice';

/// Translates one piece of text at a time.
abstract class Translator {
  /// Where the model actually runs (`GPU`, `CPU`), for status lines.
  /// Null until loaded.
  String? get deviceLabel;

  Future<void> load();

  /// [context] is the text just before [text], used for consistency and
  /// not translated. [following] is the text just after, for formats
  /// trained with it. [priority] orders the requests: the page on screen,
  /// then what the reader reaches next, then library books.
  Future<String> translate(
    String text, {
    required String targetLanguage,
    String? sourceLanguage,
    String? context,
    String? following,
    TranslationPriority priority = TranslationPriority.background,
  });

  /// How many consecutive paragraphs one request may carry (1: one at a
  /// time). One request for several shares the instructions' processing
  /// - the larger part of a paragraph's time on a phone CPU - and gives
  /// the model the scene around each paragraph.
  int get batchSize;

  /// [texts] (consecutive paragraphs) in one request. [before] are the
  /// paragraphs just before, [beforeTranslations] their translations
  /// where known. [onEach] hears each translation as soon as it is done.
  /// Returns one translation per text, empty where none came.
  Future<List<String>> translateBatch(
    List<String> texts, {
    required String targetLanguage,
    String? sourceLanguage,
    List<String> before = const [],
    List<String?> beforeTranslations = const [],
    Map<String, String> readings = const {},
    TranslationPriority priority = TranslationPriority.background,
    void Function(int index, String translation)? onEach,
  });

  Future<void> dispose();
}

class _Job {
  _Job(this.text, this.targetLanguage, this.sourceLanguage, this.context,
      [this.following]);
  final String text;
  final String targetLanguage;
  final String? sourceLanguage;
  final String? context;
  final String? following;
}

/// [Translator] on llamadart: LiteRT-LM for `.litertlm` files (GPU first,
/// then CPU), llama.cpp on the CPU for `.gguf` files.
///
/// One generation runs at a time, ordered and paced by a
/// [TranslationScheduler]: the page on screen first, the rest with pauses
/// that keep the phone responsive, a library book stopped as soon as the
/// reader needs the engine.
class LocalLlmTranslator implements Translator {
  LocalLlmTranslator({
    required this.modelPath,
    required this.runtime,
    this.contextSize = 4096,
    this.cpuOnly = false,
    int? threads,
  }) : threads = threads ?? recommendedThreads() {
    _scheduler = TranslationScheduler<Object?>(
        onYield: () => _engine?.cancelGeneration());
  }

  final String modelPath;
  final TranslationRuntime runtime;
  final int contextSize;

  /// LiteRT-LM on the CPU only, never the GPU.
  final bool cpuOnly;

  /// CPU threads (0: the runtime decides).
  final int threads;
  late final TranslationScheduler<Object?> _scheduler;

  String get _fileName => modelPath.split(RegExp(r'[\\/]')).last;

  /// The prompt format for this model, read per request so a change in
  /// settings applies without reloading.
  TranslationPromptFormat get promptFormat =>
      TranslationPromptFormats.formatFor(_fileName);

  /// LiteRT-LM files with a multi-token-prediction drafter decode faster
  /// with speculative decoding (Gemma 4: up to 2.2x on GPU). Turned off
  /// for good after the first refusal.
  bool _speculative = true;

  final AppLogger _logger = AppLogger();
  LlamaEngine? _engine;
  Future<void>? _loading;
  String? _deviceLabel;
  bool _disposed = false;

  @override
  String? get deviceLabel => _deviceLabel;

  bool get isIdle => _scheduler.isIdle;

  /// The user is scrolling or turning pages: nothing new starts until
  /// they stop, and a library book in progress steps aside.
  void noteInteraction() => _scheduler.noteInteraction();

  /// Stops a library book's paragraph in progress (the reader opened).
  void yieldBackground() => _scheduler.yieldBackground();

  @override
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    await LlamaLogging.configure(level: LlamaLogLevel.none);
    if (runtime == TranslationRuntime.liteRtLm) {
      await _loadLiteRt(from: await _afterCrash(await _savedSetup()));
      return;
    }
    final model = LlamaModel(ModelSource.path(modelPath));
    final engine = LlamaEngine(LlamaBackend());
    try {
      await _setModel(engine, model, ComputeDevice.cpu, gpuLayers: 0);
    } catch (_) {
      _loading = null;
      await engine.dispose().catchError((_) {});
      rethrow;
    }
    _engine = engine;
    _deviceLabel = 'CPU';
    _logger.info('Translation model loaded',
        tag: 'Translator', metadata: {'runtime': 'llama_cpp'});
  }

  /// The ways to run a LiteRT-LM file, fastest first: the GPU with the
  /// multi-token drafter, without it, with float32 activations (some GPUs
  /// produce garbage in float16), then the CPU.
  List<_Setup> get _setups => [
        if (!cpuOnly) ...const [
          _Setup(gpu: true, speculative: true),
          _Setup(gpu: true, speculative: false),
          _Setup(gpu: true, speculative: false, float32: true),
        ],
        const _Setup(gpu: false, speculative: true),
        const _Setup(gpu: false, speculative: false),
      ];

  int _setupIndex = 0;

  // 2: the GPU could not load the phone's OpenCL driver before the manifest
  // declared it, so what earlier versions found says nothing about it.
  static const _setupPrefPrefix = 'translationEngineSetup2:';
  static const _failuresPrefPrefix = 'translationEngineFailures:';

  /// The setup being started; cleared once it works or fails. Still set
  /// at the next launch, the app died starting it - a native crash or the
  /// system reclaiming memory, which no try/catch sees.
  static const _tryingPrefPrefix = 'translationEngineTrying:';

  /// Marked with the process id: a mark from this same process (an
  /// earlier translator, disposed while starting) is not a crash.
  Future<void> _setTrying(String key) => MyLibraryDb.instance
      .savePreference(
          '$_tryingPrefPrefix$_fileName', key.isEmpty ? '' : '$key@$pid')
      .catchError((_) {});

  /// The previous run's exit was looked at in this process already.
  static bool _crashChecked = false;

  /// Where to start after the app died starting a setup: the next one,
  /// and past the GPU entirely when the GPU without extras died too (the
  /// others only add to what it needs).
  Future<int> _afterCrash(int from) async {
    final trying = await MyLibraryDb.instance
        .getPreference('$_tryingPrefPrefix$_fileName')
        .catchError((_) => null);
    final setups = _setups;
    final int index;
    final last = await ProcessExits.previous();
    if (trying is String && trying.isNotEmpty) {
      await _setTrying('');
      final at = trying.lastIndexOf('@');
      if (at < 0 || trying.substring(at + 1) == '$pid') return from;
      index = setups.indexWhere((s) => s.key == trying.substring(0, at));
    } else if (last != null &&
        from < setups.length &&
        setups[from].gpu &&
        last.reason == 'crash_native' &&
        RegExp('litert|opencl', caseSensitive: false)
            .hasMatch(last.trace ?? '') &&
        !_crashChecked) {
      // A crash in the engine from a version that kept no mark: the setup
      // it would have started with.
      index = from;
    } else {
      return from;
    }
    _crashChecked = true;
    if (index < 0) return from;
    // Swiped away, or reclaimed in the background: not the setup's fault.
    if (last != null && !last.likelyCrash) return from;
    final setup = setups[index];
    _logger.warning('Engine setup ${setup.key} closed the app last time',
        tag: 'Translator',
        metadata: {
          'exit': last?.reason ?? 'unknown',
          if (last?.description != null) 'description': last!.description,
        });
    await _recordFailure(
        setup, 'app closed while starting (${last?.reason ?? 'unknown'})', 0);
    var next = index + 1;
    if (setup.gpu && !setup.speculative) {
      next = setups.indexWhere((s) => !s.gpu);
    }
    if (next >= setups.length || next < 0) next = setups.length - 1;
    await MyLibraryDb.instance
        .savePreference('$_setupPrefPrefix$_fileName', setups[next].key)
        .catchError((_) {});
    return next > from ? next : from;
  }

  /// Why setups failed on this device (newest last, a few kept): logged
  /// whenever the engine starts past them, so a report shows the cause
  /// even when the failures happened long before.
  Future<List<Object?>> _failures() async {
    try {
      final raw = await MyLibraryDb.instance
          .getPreference('$_failuresPrefPrefix$_fileName');
      return raw is String && raw.isNotEmpty
          ? (jsonDecode(raw) as List).cast<Object?>()
          : <Object?>[];
    } catch (_) {
      return <Object?>[];
    }
  }

  Future<void> _recordFailure(_Setup setup, Object error, int afterMs) async {
    final text = '$error';
    final list = [
      ...await _failures(),
      {
        'setup': setup.key,
        'error': text.length > 240 ? text.substring(0, 240) : text,
        'afterMs': afterMs,
        'at': DateTime.now().toIso8601String(),
      },
    ];
    await MyLibraryDb.instance
        .savePreference('$_failuresPrefPrefix$_fileName',
            jsonEncode(list.length > 6 ? list.sublist(list.length - 6) : list))
        .catchError((_) {});
  }

  /// Where to start: the setup that worked last time with this model (the
  /// ones before it failed on this device).
  Future<int> _savedSetup() async {
    final saved = await MyLibraryDb.instance
        .getPreference('$_setupPrefPrefix$_fileName')
        .catchError((_) => null);
    final index = _setups.indexWhere((s) => s.key == saved);
    return index < 0 ? 0 : index;
  }

  /// Forgets what worked with [fileName] (the processor was chosen again
  /// in settings): the next start tries the fastest setup first.
  static Future<void> clearGpuStall(String fileName) async {
    await MyLibraryDb.instance
        .savePreference('$_setupPrefPrefix$fileName', '')
        .catchError((_) {});
    await MyLibraryDb.instance
        .savePreference('$_failuresPrefPrefix$fileName', '')
        .catchError((_) {});
  }

  /// Starts the engine with the first setup from [from] that translates:
  /// a real request must come back in time and in the target script.
  Future<void> _loadLiteRt({required int from}) async {
    final model = LlamaModel(ModelSource.path(modelPath));
    final cacheDir = await _liteRtCacheDir();
    final setups = _setups;
    if (from > 0) {
      _logger.info('Engine starts past setups that failed before',
          tag: 'Translator',
          metadata: {'from': setups[from].key, 'failures': await _failures()});
    }
    Object? lastError;
    var gpuStuck = false;
    for (var i = from; i < setups.length; i++) {
      final setup = setups[i];
      // A GPU that did not answer in minutes will not with other options;
      // trying each would keep the reader waiting several times as long.
      if (setup.gpu && gpuStuck) continue;
      // auto means the GPU on Android, iOS and macOS only.
      final label = setup.gpu &&
              (Platform.isAndroid || Platform.isIOS || Platform.isMacOS)
          ? 'GPU'
          : 'CPU';
      final engine = LlamaEngine(LlamaBackend());
      final watch = Stopwatch()..start();
      await _setTrying(setup.key);
      try {
        await _setModel(
            engine, model, setup.gpu ? ComputeDevice.auto : ComputeDevice.cpu,
            cacheDir: cacheDir, float32: setup.float32);
        final loadedMs = watch.elapsedMilliseconds;
        // LiteRT-LM starts its engine on the first generation, and
        // prepares each prompt length the first time it sees one (on a
        // GPU: compiling programs, minutes for a large model, cached
        // afterwards). A request as long as a real one does both now,
        // while the reader says "preparing", and shows whether this setup
        // translates at all.
        final sample = await _warmUp(engine,
            gpu: setup.gpu, speculative: setup.speculative);
        _logger
            .info('Translation engine started', tag: 'Translator', metadata: {
          'setup': setup.key,
          'loadMs': loadedMs,
          'startMs': watch.elapsedMilliseconds - loadedMs,
          'threads': threads,
          'sample': sample,
        });
        _engine = engine;
        _deviceLabel = label;
        _speculative = setup.speculative;
        _setupIndex = i;
        _firstGeneration = true;
        _badOutputs = 0;
        await MyLibraryDb.instance
            .savePreference('$_setupPrefPrefix$_fileName', setup.key)
            .catchError((_) {});
        // The mark stays until the first real request is through: a
        // longer prompt than the test's can still bring the GPU down.
        return;
      } catch (e) {
        lastError = e;
        if (setup.gpu && e is TimeoutException) gpuStuck = true;
        _logger.warning('Engine setup ${setup.key} failed',
            tag: 'Translator',
            error: e,
            metadata: {'afterMs': watch.elapsedMilliseconds});
        await _recordFailure(setup, e, watch.elapsedMilliseconds);
        // A stuck GPU may never finish tearing down; do not wait on it.
        await engine
            .dispose()
            .timeout(const Duration(seconds: 15), onTimeout: () {})
            .catchError((_) {});
        await _setTrying('');
      }
    }
    _loading = null;
    throw lastError ?? StateError('No engine setup worked');
  }

  /// The running setup misbehaved (stalled, or answered with nothing):
  /// the engine starts again with the next one.
  Future<void> _nextSetup(String why) async {
    final old = _engine;
    _engine = null;
    _deviceLabel = null;
    _logger.warning('Engine setup ${_setups[_setupIndex].key} dropped',
        tag: 'Translator', metadata: {'why': why});
    await _recordFailure(_setups[_setupIndex], 'dropped: $why', 0);
    await old
        ?.dispose()
        .timeout(const Duration(seconds: 15), onTimeout: () {})
        .catchError((_) {});
    if (_setupIndex + 1 >= _setups.length) {
      throw StateError('No engine setup left ($why)');
    }
    await _loadLiteRt(from: _setupIndex + 1);
  }

  int _badOutputs = 0;

  /// LiteRT-LM's caches (compiled GPU programs, CPU weight layouts) in the
  /// app's support directory, which Android does not clear like the
  /// temporary one: a large model is then prepared only once.
  static Future<String?> _liteRtCacheDir() async {
    try {
      final dir = Directory(
          '${(await getApplicationSupportDirectory()).path}/litert_cache');
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir.path;
    } catch (_) {
      return null;
    }
  }

  /// A short translation with a prompt of the real length, to start the
  /// engine (see [_loadLiteRt]). Returns its text; throws when it stalls
  /// or answers without any Korean (a GPU producing garbage).
  Future<String> _warmUp(LlamaEngine engine,
      {required bool gpu, required bool speculative}) async {
    final prompt = buildTranslationPrompt(
      format: TranslationPromptFormat.general,
      text: '「おはよう。今日もいい天気だね」',
      targetLanguage: 'Korean',
      sourceLanguage: 'Japanese',
      lightNovelStyle: TranslationStyle.lightNovel,
    );
    // Generous: the first start of a large model on a GPU compiles for
    // minutes. Past this it is stuck, not slow.
    final limit =
        gpu ? const Duration(minutes: 6) : const Duration(minutes: 10);
    final completion = await _withTimeout(
        engine,
        engine.create(
          [LlamaChatMessage.fromText(role: LlamaChatRole.user, text: prompt)],
          params: _liteRtParams(12).copyWith(speculativeDecoding: speculative),
          enableThinking: false,
        ).collect(),
        limit);
    final text = completion.text;
    if (!RegExp('[가-힣]').hasMatch(text)) {
      throw StateError('No Korean in the test translation: '
          '${jsonEncode(text.length > 60 ? text.substring(0, 60) : text)}');
    }
    return text.trim();
  }

  /// Sampling for LiteRT-LM: greedy through top-k 1 at temperature 1.
  /// Temperature 0 divides by zero in GPU samplers, whose output then is
  /// garbage (whitespace to the token limit).
  static GenerationParams _liteRtParams(int maxTokens, {double? penalty}) =>
      penalty == null
          ? GenerationParams(
              maxTokens: maxTokens, temp: 1.0, topK: 1, topP: 1.0)
          : GenerationParams(
              maxTokens: maxTokens,
              temp: 1.0,
              topK: 1,
              topP: 1.0,
              penalty: penalty);

  /// [work] on [engine], cancelled and failed with a [TimeoutException]
  /// after [limit].
  Future<T> _withTimeout<T>(
      LlamaEngine engine, Future<T> work, Duration limit) async {
    final timer = Completer<void>();
    final t = Timer(limit, () {
      if (!timer.isCompleted) timer.complete();
    });
    try {
      return await Future.any<T>([
        work,
        timer.future.then<T>((_) async {
          engine.cancelGeneration();
          // Let the cancelled request end before the next one starts.
          await work.timeout(const Duration(seconds: 10),
              onTimeout: () => throw TimeoutException('stalled', limit));
          throw TimeoutException('stalled', limit);
        }),
      ]);
    } finally {
      t.cancel();
    }
  }

  /// Loads with the CPU thread cap; a runtime that refuses the setting
  /// loads with its own.
  Future<void> _setModel(
      LlamaEngine engine, LlamaModel model, ComputeDevice device,
      {int? gpuLayers, String? cacheDir, bool float32 = false}) async {
    ModelParams params(int n) => gpuLayers == null
        ? ModelParams(
            contextSize: contextSize,
            device: device,
            numberOfThreads: n,
            liteRtLmActivationDataType:
                float32 ? LiteRtLmActivationDataType.float32 : null,
            liteRtLmCacheDir: cacheDir,
            // Room for E4B's compiled GPU programs next to another model's;
            // the 1 GiB default could prune them before every start.
            liteRtLmMaxProgramCacheBytes: 3 << 30)
        : ModelParams(
            contextSize: contextSize,
            device: device,
            gpuLayers: gpuLayers,
            numberOfThreads: n,
            numberOfThreadsBatch: n);
    if (threads <= 0) return engine.setModel(model, params: params(0));
    try {
      await engine.setModel(model, params: params(threads));
    } catch (e) {
      _logger.info('Thread count not accepted, runtime default used',
          tag: 'Translator', metadata: {'reason': '$e'});
      await engine.setModel(model, params: params(0));
    }
  }

  @override
  Future<String> translate(
    String text, {
    required String targetLanguage,
    String? sourceLanguage,
    String? context,
    String? following,
    TranslationPriority priority = TranslationPriority.background,
  }) {
    if (_disposed) return Future.error(StateError('Translator disposed'));
    final job = _Job(text, targetLanguage, sourceLanguage, context, following);
    return _scheduler
        .submit((token) => _translateNow(job, token), priority)
        .then((v) => v as String);
  }

  /// How long one generation may take before it counts as stalled: far
  /// more than a slow phone needs for [maxTokens] (and the first one after
  /// a start, which may still be preparing).
  Duration _limitFor(int maxTokens) {
    final perToken = _deviceLabel == 'GPU' ? 0.35 : 0.8;
    final seconds = 40 + maxTokens * perToken + (_firstGeneration ? 90 : 0);
    return Duration(milliseconds: (seconds * 1000).round());
  }

  int _generationCount = 0;
  bool _firstGeneration = true;

  /// One generation, retried on the next engine setup when it stalls or
  /// produces garbage. [onText] hears the text so far as it streams.
  /// Returns the raw answer.
  Future<String> _generateRaw(
      String prompt, int maxTokens, double? penalty, YieldToken token,
      {void Function(String textSoFar)? onText,
      bool Function(String raw)? isGarbage}) async {
    final liteRt = runtime == TranslationRuntime.liteRtLm;
    final GenerationParams base = liteRt
        ? _liteRtParams(maxTokens, penalty: penalty)
        : penalty == null
            ? GenerationParams(maxTokens: maxTokens, temp: 0)
            : GenerationParams(
                maxTokens: maxTokens, temp: 0, topK: 1, penalty: penalty);
    for (var attempt = 0;; attempt++) {
      final engine = _engine;
      if (engine == null) throw StateError('Translator not loaded');
      final spec = liteRt && _speculative;
      final watch = Stopwatch()..start();
      try {
        final buffer = StringBuffer();
        final work = engine
            .create(
              [
                LlamaChatMessage.fromText(
                    role: LlamaChatRole.user, text: prompt)
              ],
              params: base.copyWith(speculativeDecoding: spec),
              enableThinking: false,
            )
            .textDeltas()
            .forEach((delta) {
              buffer.write(delta);
              onText?.call(buffer.toString());
            })
            .then((_) => buffer.toString());
        final raw = await _withTimeout(engine, work, _limitFor(maxTokens));
        if (_firstGeneration && liteRt) await _setTrying('');
        _firstGeneration = false;
        // Stopped to make room: the partial text is not a translation.
        token.check();
        final garbage = raw.isNotEmpty &&
            (isGarbage?.call(raw) ?? cleanTranslation(raw).isEmpty);
        _generationCount++;
        if (_generationCount <= 3 ||
            watch.elapsed > const Duration(seconds: 20) ||
            garbage ||
            raw.isEmpty) {
          _logger.info('Generation', tag: 'Translator', metadata: {
            'n': _generationCount,
            'ms': watch.elapsedMilliseconds,
            'device': _deviceLabel,
            'speculative': spec,
            'promptChars': prompt.length,
            'maxTokens': maxTokens,
            'rawChars': raw.length,
            if (garbage || raw.isEmpty)
              'raw': jsonEncode(raw.length > 40 ? raw.substring(0, 40) : raw),
          });
        }
        // Something came back but none of it is text: the engine is
        // producing garbage. Twice in a row, the next setup takes over.
        if (liteRt && garbage) {
          if (++_badOutputs >= 2 && attempt < 4) {
            await _nextSetup('garbage output');
            continue;
          }
        } else {
          _badOutputs = 0;
        }
        return raw;
      } on LlamaUnsupportedException catch (e) {
        if (!spec || attempt >= 4) rethrow;
        await _nextSetup('speculative decoding unsupported: $e');
      } on TimeoutException {
        if (token.yielded) rethrow;
        _logger.warning('Generation stalled', tag: 'Translator', metadata: {
          'ms': watch.elapsedMilliseconds,
          'device': _deviceLabel,
          'speculative': spec,
          'attempt': attempt,
        });
        if (!liteRt || attempt >= 4) rethrow;
        await _nextSetup('stalled');
      }
    }
  }

  Future<String> _generate(String prompt, int maxTokens,
      TranslationPromptFormat format, YieldToken token) async {
    // Dedicated translation models: their recommended repetition penalty
    // (1.05); the general format keeps the runtime's default.
    final penalty = format == TranslationPromptFormat.general ? null : 1.05;
    return cleanTranslation(
        await _generateRaw(prompt, maxTokens, penalty, token));
  }

  @override
  int get batchSize => promptFormat == TranslationPromptFormat.general ? 8 : 1;

  @override
  Future<List<String>> translateBatch(
    List<String> texts, {
    required String targetLanguage,
    String? sourceLanguage,
    List<String> before = const [],
    List<String?> beforeTranslations = const [],
    Map<String, String> readings = const {},
    TranslationPriority priority = TranslationPriority.background,
    void Function(int index, String translation)? onEach,
  }) {
    if (_disposed) return Future.error(StateError('Translator disposed'));
    return _scheduler
        .submit(
            (token) => _translateBatchNow(texts, targetLanguage, sourceLanguage,
                before, beforeTranslations, readings, onEach, token),
            priority)
        .then((v) => (v as List).cast<String>());
  }

  Future<List<String>> _translateBatchNow(
    List<String> texts,
    String targetLanguage,
    String? sourceLanguage,
    List<String> before,
    List<String?> beforeTranslations,
    Map<String, String> readings,
    void Function(int index, String translation)? onEach,
    YieldToken token,
  ) async {
    await load();
    token.check();
    final results = List<String?>.filled(texts.length, null);
    void deliver(int i, String answer) {
      if (results[i] != null) return;
      final polished =
          polishTranslation(cleanTranslation(answer), texts[i], targetLanguage);
      // Source script left in it: translated again alone (with the retry
      // that names the problem) once the batch is done.
      if (polished.isEmpty ||
          leftoverSourceScript(polished, targetLanguage).isNotEmpty) {
        return;
      }
      results[i] = polished;
      onEach?.call(i, polished);
    }

    if (texts.length > 1 && promptFormat == TranslationPromptFormat.general) {
      final prompt = batchTranslationPrompt(
        texts: texts,
        targetLanguage: targetLanguage,
        sourceLanguage: sourceLanguage,
        before: before,
        beforeTranslations: beforeTranslations,
        readings: readingsIn(readings, [...texts, ...before]),
        lightNovelStyle: TranslationStyle.lightNovel,
      );
      final maxTokens =
          (texts.fold<int>(0, (n, t) => n + t.length * 3 + 16) + 32)
              .clamp(64, 2048);
      // Each line is shown as soon as the next one starts.
      var settled = 0;
      void onText(String soFar) {
        final lines = soFar.split('\n');
        for (var k = settled; k < lines.length - 1; k++) {
          final got = parseNumberedTranslations(lines[k], texts.length);
          for (var i = 0; i < got.length; i++) {
            if (got[i] != null) deliver(i, got[i]!);
          }
        }
        settled = lines.length - 1;
      }

      final raw = await _generateRaw(prompt, maxTokens, null, token,
          onText: onText,
          isGarbage: (raw) => !RegExp(r'\p{L}', unicode: true).hasMatch(raw));
      final got = parseNumberedTranslations(raw, texts.length);
      for (var i = 0; i < got.length; i++) {
        if (got[i] != null) deliver(i, got[i]!);
      }
    }
    // Whatever the batch did not bring back, one at a time.
    for (var i = 0; i < texts.length; i++) {
      if (results[i] != null) continue;
      token.check();
      final context =
          i > 0 ? texts[i - 1] : (before.isNotEmpty ? before.last : null);
      final out = await _translateNow(
          _Job(texts[i], targetLanguage, sourceLanguage, context,
              i + 1 < texts.length ? texts[i + 1] : null),
          token);
      results[i] = out;
      if (out.isNotEmpty) onEach?.call(i, out);
    }
    return [for (final r in results) r ?? ''];
  }

  Future<String> _translateNow(_Job job, YieldToken token) async {
    await load();
    token.check();
    // Small models drop the second line of a two-line paragraph; each
    // line goes on its own and the breaks are put back.
    final lines = job.text.split('\n');
    if (lines.length > 1) {
      final out = <String>[];
      final kept = lines.where((l) => l.trim().isNotEmpty).toList();
      for (var i = 0; i < kept.length; i++) {
        final line = kept[i];
        // Each line sees the lines around it (and the paragraphs around
        // the whole) as context, for the formats that use it.
        final before = [
          if (job.context != null) job.context!,
          ...kept.take(i),
        ].join('\n');
        final after = i + 1 < kept.length ? kept[i + 1] : job.following;
        out.add(shouldTranslate(line)
            ? await _translateLine(
                _Job(line, job.targetLanguage, job.sourceLanguage,
                    before.isEmpty ? null : before, after),
                token)
            : line);
        token.check();
      }
      return out.join('\n');
    }
    return _translateLine(job, token);
  }

  Future<String> _translateLine(_Job job, YieldToken token) async {
    var format = promptFormat;
    // A one-language model asked for another language: the general
    // instructions at least name the target.
    if (!format.supportsTarget(job.targetLanguage)) {
      format = TranslationPromptFormat.general;
    }
    final prompt = buildTranslationPrompt(
      format: format,
      text: job.text,
      targetLanguage: job.targetLanguage,
      sourceLanguage: job.sourceLanguage,
      context: job.context,
      following: job.following,
      lightNovelStyle: TranslationStyle.lightNovel,
    );
    // Translations run about as long as the source; leave room for
    // scripts that need more tokens per character.
    final maxTokens = (job.text.length * 3 + 32).clamp(64, 1024);
    var answer = await _generate(prompt, maxTokens, format, token);
    if (format == TranslationPromptFormat.jaKoDialogue) {
      // Trained to answer with one line; anything after it is noise.
      answer = answer
          .split('\n')
          .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '')
          .trim();
    }

    // Source script left in the answer (an untranslated word, a name in
    // kana): ask once more, naming the problem, and keep the cleaner one.
    // Only the general format understands a follow-up instruction.
    final leftover = leftoverSourceScript(answer, job.targetLanguage);
    if (leftover.isNotEmpty &&
        !_disposed &&
        format == TranslationPromptFormat.general) {
      final again = await _generate(
          retryPrompt(prompt, answer, job.targetLanguage),
          maxTokens,
          format,
          token);
      if (again.isNotEmpty &&
          leftoverSourceScript(again, job.targetLanguage).length <
              leftover.length) {
        answer = again;
      }
    }
    return polishTranslation(answer, job.text, job.targetLanguage);
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _scheduler.close();
    final engine = _engine;
    _engine = null;
    _loading = null;
    await engine?.dispose();
  }
}

/// The one translation engine the app keeps: the reader and the
/// background book translator share it, so the model is loaded once.
/// It is released after a few idle minutes to give the memory back.
class SharedTranslationEngine {
  SharedTranslationEngine._();
  static final SharedTranslationEngine instance = SharedTranslationEngine._();

  static const idleRelease = Duration(minutes: 3);

  /// LiteRT-LM models on the CPU only ([translationDevicePref]).
  static bool cpuOnly = false;

  LocalLlmTranslator? _translator;
  String? _modelFile;
  bool _cpuOnly = false;
  Timer? _idleTimer;
  int _users = 0;

  /// How many readers are open; library books wait while one is, so the
  /// page turns stay smooth.
  final ValueNotifier<int> readers = ValueNotifier(0);

  void enterReader() {
    readers.value++;
    _translator?.yieldBackground();
  }

  void leaveReader() {
    if (readers.value > 0) readers.value--;
  }

  /// The translator for the active model, created (not yet loaded) on
  /// first use. Null when no model is installed.
  Future<LocalLlmTranslator?> acquire() async {
    final model = await TranslationModelStore.instance.activeModel();
    if (model == null) return null;
    _idleTimer?.cancel();
    if (_translator == null ||
        _modelFile != model.fileName ||
        _cpuOnly != cpuOnly) {
      final old = _translator;
      _translator = LocalLlmTranslator(
          modelPath: model.path, runtime: model.runtime, cpuOnly: cpuOnly);
      _modelFile = model.fileName;
      _cpuOnly = cpuOnly;
      await old?.dispose();
    }
    _users++;
    return _translator;
  }

  String? get activeModelFile => _modelFile;

  /// The user is scrolling or turning pages (see
  /// [LocalLlmTranslator.noteInteraction]).
  void noteInteraction() => _translator?.noteInteraction();

  void release() {
    if (_users > 0) _users--;
    if (_users == 0) {
      _idleTimer?.cancel();
      _idleTimer = Timer(idleRelease, () async {
        if (_users > 0) return;
        final t = _translator;
        if (t != null && t.isIdle) {
          _translator = null;
          _modelFile = null;
          await t.dispose();
        }
      });
    }
  }

  /// Drops the engine now (model deleted or switched in settings).
  Future<void> reset() async {
    _idleTimer?.cancel();
    final t = _translator;
    _translator = null;
    _modelFile = null;
    await t?.dispose();
  }
}

/// The reader's handle on the shared engine: its requests are never
/// background work, and a library book's paragraph in progress steps
/// aside at once. Disposing it only releases the handle.
class UrgentTranslator implements Translator {
  UrgentTranslator(this._inner) {
    _inner.yieldBackground();
  }
  final LocalLlmTranslator _inner;
  bool _released = false;

  @override
  String? get deviceLabel => _inner.deviceLabel;

  @override
  Future<void> load() => _inner.load();

  @override
  Future<String> translate(String text,
          {required String targetLanguage,
          String? sourceLanguage,
          String? context,
          String? following,
          TranslationPriority priority = TranslationPriority.visible}) =>
      _inner.translate(text,
          targetLanguage: targetLanguage,
          sourceLanguage: sourceLanguage,
          context: context,
          following: following,
          priority: priority == TranslationPriority.background
              ? TranslationPriority.ahead
              : priority);

  @override
  int get batchSize => _inner.batchSize;

  @override
  Future<List<String>> translateBatch(
    List<String> texts, {
    required String targetLanguage,
    String? sourceLanguage,
    List<String> before = const [],
    List<String?> beforeTranslations = const [],
    Map<String, String> readings = const {},
    TranslationPriority priority = TranslationPriority.visible,
    void Function(int index, String translation)? onEach,
  }) =>
      _inner.translateBatch(texts,
          targetLanguage: targetLanguage,
          sourceLanguage: sourceLanguage,
          before: before,
          beforeTranslations: beforeTranslations,
          readings: readings,
          priority: priority == TranslationPriority.background
              ? TranslationPriority.ahead
              : priority,
          onEach: onEach);

  @override
  Future<void> dispose() async {
    if (_released) return;
    _released = true;
    SharedTranslationEngine.instance.release();
  }
}

/// One way to run a LiteRT-LM model (see [LocalLlmTranslator._setups]).
@immutable
class _Setup {
  const _Setup(
      {required this.gpu, required this.speculative, this.float32 = false});
  final bool gpu;
  final bool speculative;
  final bool float32;

  String get key =>
      '${gpu ? 'gpu' : 'cpu'}${speculative ? '+mtp' : ''}${float32 ? '+f32' : ''}';
}
