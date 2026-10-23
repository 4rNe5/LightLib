// Running a translation model on the device.

// Dart imports:
import 'dart:async';
import 'dart:collection';
import 'dart:io';

// Package imports:
import 'package:llamadart/llamadart.dart';

// Project imports:
import 'package:openlib/services/logger.dart';
import 'package:openlib/services/translation/paragraph_text.dart';
import 'package:openlib/services/translation/translation_model_store.dart';
import 'package:openlib/services/translation/translation_models.dart';

/// Translates one piece of text at a time.
abstract class Translator {
  /// Where the model actually runs (`GPU`, `CPU`), for status lines.
  /// Null until loaded.
  String? get deviceLabel;

  Future<void> load();

  /// [context] is the text just before [text], used for consistency and
  /// not translated. [urgent] requests (the page being read) run before
  /// queued background work.
  /// [following] is the text just after, for formats trained with it.
  Future<String> translate(
    String text, {
    required String targetLanguage,
    String? sourceLanguage,
    String? context,
    String? following,
    bool urgent = false,
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
  final Completer<String> result = Completer<String>();
}

/// [Translator] on llamadart: LiteRT-LM for `.litertlm` files (GPU first,
/// then CPU), llama.cpp on the CPU for `.gguf` files.
///
/// One generation runs at a time. Urgent requests jump ahead of the
/// background queue (but never interrupt a generation in progress).
class LocalLlmTranslator implements Translator {
  LocalLlmTranslator({
    required this.modelPath,
    required this.runtime,
    this.contextSize = 2048,
  });

  final String modelPath;
  final TranslationRuntime runtime;
  final int contextSize;

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

  final Queue<_Job> _urgent = Queue();
  final Queue<_Job> _background = Queue();
  bool _working = false;

  @override
  String? get deviceLabel => _deviceLabel;

  bool get isIdle => !_working && _urgent.isEmpty && _background.isEmpty;

  @override
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    await LlamaLogging.configure(level: LlamaLogLevel.none);
    final model = LlamaModel(ModelSource.path(modelPath));
    if (runtime == TranslationRuntime.liteRtLm) {
      // auto = GPU on Android. A GPU that cannot run the model (driver,
      // memory) falls back to LiteRT-LM's CPU path with the same file.
      for (final device in [ComputeDevice.auto, ComputeDevice.cpu]) {
        final engine = LlamaEngine(LlamaBackend());
        try {
          await engine.setModel(model,
              params: ModelParams(contextSize: contextSize, device: device));
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
        await engine.setModel(model,
            params: ModelParams(
              contextSize: contextSize,
              device: ComputeDevice.cpu,
              gpuLayers: 0,
            ));
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

  @override
  Future<String> translate(
    String text, {
    required String targetLanguage,
    String? sourceLanguage,
    String? context,
    String? following,
    bool urgent = false,
  }) {
    if (_disposed) return Future.error(StateError('Translator disposed'));
    final job = _Job(text, targetLanguage, sourceLanguage, context, following);
    (urgent ? _urgent : _background).add(job);
    _drain();
    return job.result.future;
  }

  Future<void> _drain() async {
    if (_working) return;
    _working = true;
    try {
      while (!_disposed && (_urgent.isNotEmpty || _background.isNotEmpty)) {
        final job = _urgent.isNotEmpty
            ? _urgent.removeFirst()
            : _background.removeFirst();
        try {
          job.result.complete(await _translateNow(job));
        } catch (e, st) {
          job.result.completeError(e, st);
        }
      }
    } finally {
      _working = false;
    }
  }

  Future<String> _generate(
      String prompt, int maxTokens, TranslationPromptFormat format) async {
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

  Future<String> _translateNow(_Job job) async {
    await load();
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
            ? await _translateLine(_Job(line, job.targetLanguage,
                job.sourceLanguage, before.isEmpty ? null : before, after))
            : line);
      }
      return out.join('\n');
    }
    return _translateLine(job);
  }

  Future<String> _translateLine(_Job job) async {
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
    var answer = await _generate(prompt, maxTokens, format);
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
          retryPrompt(prompt, answer, job.targetLanguage), maxTokens, format);
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
    for (final job in [..._urgent, ..._background]) {
      job.result.completeError(StateError('Translator disposed'));
    }
    _urgent.clear();
    _background.clear();
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

  LocalLlmTranslator? _translator;
  String? _modelFile;
  Timer? _idleTimer;
  int _users = 0;

  /// The translator for the active model, created (not yet loaded) on
  /// first use. Null when no model is installed.
  Future<LocalLlmTranslator?> acquire() async {
    final model = await TranslationModelStore.instance.activeModel();
    if (model == null) return null;
    _idleTimer?.cancel();
    if (_translator == null || _modelFile != model.fileName) {
      final old = _translator;
      _translator =
          LocalLlmTranslator(modelPath: model.path, runtime: model.runtime);
      _modelFile = model.fileName;
      await old?.dispose();
    }
    _users++;
    return _translator;
  }

  String? get activeModelFile => _modelFile;

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

/// A [Translator] handle on the shared engine that marks every request
/// urgent - what the reader uses for the page on screen. Disposing it only
/// releases the handle.
class UrgentTranslator implements Translator {
  UrgentTranslator(this._inner);
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
          bool urgent = true}) =>
      _inner.translate(text,
          targetLanguage: targetLanguage,
          sourceLanguage: sourceLanguage,
          context: context,
          following: following,
          urgent: true);

  @override
  Future<void> dispose() async {
    if (_released) return;
    _released = true;
    SharedTranslationEngine.instance.release();
  }
}
