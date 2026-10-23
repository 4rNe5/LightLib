// Running a translation model on the device.

// Dart imports:
import 'dart:async';
import 'dart:io';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:llamadart/llamadart.dart';
import 'package:path_provider/path_provider.dart';

// Project imports:
import 'package:openlib/services/logger.dart';
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
    this.contextSize = 2048,
    this.cpuOnly = false,
    int? threads,
  }) : threads = threads ?? recommendedThreads() {
    _scheduler = TranslationScheduler<String>(
        onYield: () => _engine?.cancelGeneration());
  }

  final String modelPath;
  final TranslationRuntime runtime;
  final int contextSize;

  /// LiteRT-LM on the CPU only, never the GPU.
  final bool cpuOnly;

  /// CPU threads (0: the runtime decides).
  final int threads;
  late final TranslationScheduler<String> _scheduler;

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
    final model = LlamaModel(ModelSource.path(modelPath));
    if (runtime == TranslationRuntime.liteRtLm) {
      // auto = GPU on Android. A GPU that cannot run the model (driver,
      // memory) falls back to LiteRT-LM's CPU path with the same file.
      final devices = cpuOnly
          ? [ComputeDevice.cpu]
          : [ComputeDevice.auto, ComputeDevice.cpu];
      final cacheDir = await _liteRtCacheDir();
      for (final device in devices) {
        final engine = LlamaEngine(LlamaBackend());
        final watch = Stopwatch()..start();
        try {
          await _setModel(engine, model, device, cacheDir: cacheDir);
          final loadedMs = watch.elapsedMilliseconds;
          // LiteRT-LM starts its engine on the first generation; a GPU
          // that cannot run the model fails only there. Start it now, so
          // a failure falls back to the CPU here instead of failing
          // every paragraph, and "loading" lasts until it can translate
          // (the first start of a large model compiles GPU programs and
          // can take minutes; later starts read them from the cache).
          await _warmUp(engine);
          _logger
              .info('Translation engine started', tag: 'Translator', metadata: {
            'device': device.name,
            'loadMs': loadedMs,
            'startMs': watch.elapsedMilliseconds - loadedMs,
            'speculative': _speculative,
            'threads': threads,
          });
          _engine = engine;
          // auto means the GPU on Android, iOS and macOS only.
          _deviceLabel = device == ComputeDevice.auto &&
                  (Platform.isAndroid || Platform.isIOS || Platform.isMacOS)
              ? 'GPU'
              : 'CPU';
          _logger.info('Translation model loaded',
              tag: 'Translator',
              metadata: {'runtime': 'litert_lm', 'device': _deviceLabel});
          return;
        } catch (e) {
          _logger.warning('LiteRT-LM load failed on ${device.name}',
              tag: 'Translator', error: e);
          await engine.dispose().catchError((_) {});
          if (device == ComputeDevice.cpu) {
            _loading = null;
            rethrow;
          }
        }
      }
    } else {
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
  }

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

  /// One token of output, to start the engine (see [_load]). Speculative
  /// decoding is dropped here when the model has no drafter for it.
  Future<void> _warmUp(LlamaEngine engine) async {
    Future<void> run(bool spec) => engine.create(
          [LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hi')],
          params: GenerationParams(maxTokens: 1, temp: 0)
              .copyWith(speculativeDecoding: spec),
          enableThinking: false,
        ).collect();
    if (_speculative) {
      try {
        await run(true);
        return;
      } on LlamaUnsupportedException catch (e) {
        _speculative = false;
        _logger.info('Speculative decoding unavailable, turned off',
            tag: 'Translator', metadata: {'reason': '$e'});
      }
    }
    await run(false);
  }

  /// Loads with the CPU thread cap; a runtime that refuses the setting
  /// loads with its own.
  Future<void> _setModel(
      LlamaEngine engine, LlamaModel model, ComputeDevice device,
      {int? gpuLayers, String? cacheDir}) async {
    ModelParams params(int n) => gpuLayers == null
        ? ModelParams(
            contextSize: contextSize,
            device: device,
            numberOfThreads: n,
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
    return _scheduler.submit((token) => _translateNow(job, token), priority);
  }

  Future<String> _generate(String prompt, int maxTokens,
      TranslationPromptFormat format, YieldToken token) async {
    // Dedicated translation models: their recommended repetition penalty
    // (1.05); the general format keeps llamadart's default it was tuned on.
    final base = format == TranslationPromptFormat.general
        ? GenerationParams(maxTokens: maxTokens, temp: 0)
        : GenerationParams(
            maxTokens: maxTokens, temp: 0, topK: 1, penalty: 1.05);
    final speculative = runtime == TranslationRuntime.liteRtLm && _speculative;
    Future<String> run(bool spec) async {
      final completion = await _engine!.create(
        [LlamaChatMessage.fromText(role: LlamaChatRole.user, text: prompt)],
        params: base.copyWith(speculativeDecoding: spec),
        enableThinking: false,
      ).collect();
      // Stopped to make room: the partial text is not a translation.
      token.check();
      return cleanTranslation(completion.text);
    }

    if (!speculative) return run(false);
    try {
      return await run(true);
    } on LlamaUnsupportedException catch (e) {
      _speculative = false;
      _logger.info('Speculative decoding unavailable, turned off',
          tag: 'Translator', metadata: {'reason': '$e'});
      return run(false);
    }
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
  Future<void> dispose() async {
    if (_released) return;
    _released = true;
    SharedTranslationEngine.instance.release();
  }
}
