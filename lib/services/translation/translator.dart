// Running a translation model on the device.

// Dart imports:
import 'dart:async';
import 'dart:io';

// Package imports:
import 'package:llamadart/llamadart.dart';

// Project imports:
import 'package:openlib/services/logger.dart';
import 'package:openlib/services/translation/paragraph_text.dart';
import 'package:openlib/services/translation/translation_models.dart';

/// Translates one piece of text at a time.
abstract class Translator {
  /// Where the model actually runs (`GPU`, `CPU`), for the reader's
  /// status line. Null until loaded.
  String? get deviceLabel;

  Future<void> load();

  Future<String> translate(
    String text, {
    required String targetLanguage,
    String? sourceLanguage,
  });

  Future<void> dispose();
}

/// [Translator] on llamadart: LiteRT-LM for `.litertlm` files (GPU first,
/// then CPU), llama.cpp on the CPU for `.gguf` files.
class LocalLlmTranslator implements Translator {
  LocalLlmTranslator({
    required this.modelPath,
    required this.runtime,
    this.contextSize = 2048,
  });

  final String modelPath;
  final TranslationRuntime runtime;
  final int contextSize;

  final AppLogger _logger = AppLogger();
  LlamaEngine? _engine;
  Future<void>? _loading;
  String? _deviceLabel;

  // One request at a time: the engine runs a single generation.
  Future<void> _queue = Future.value();

  @override
  String? get deviceLabel => _deviceLabel;

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
          if (device == ComputeDevice.cpu) rethrow;
        }
      }
    } else {
      final engine = LlamaEngine(LlamaBackend());
      await engine.setModel(model,
          params: ModelParams(
            contextSize: contextSize,
            device: ComputeDevice.cpu,
            gpuLayers: 0,
          ));
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
  }) {
    final result = Completer<String>();
    _queue = _queue.then((_) async {
      try {
        result.complete(await _translateNow(text,
            targetLanguage: targetLanguage, sourceLanguage: sourceLanguage));
      } catch (e, st) {
        result.completeError(e, st);
      }
    });
    return result.future;
  }

  Future<String> _translateNow(
    String text, {
    required String targetLanguage,
    String? sourceLanguage,
  }) async {
    await load();
    final engine = _engine!;
    final prompt = translationPrompt(
      text: text,
      targetLanguage: targetLanguage,
      sourceLanguage: sourceLanguage,
    );
    // Translations run about as long as the source; leave room for
    // scripts that need more tokens per character.
    final maxTokens = (text.length * 3 + 32).clamp(64, 1024);
    final completion = await engine.create(
      [LlamaChatMessage.fromText(role: LlamaChatRole.user, text: prompt)],
      params: GenerationParams(maxTokens: maxTokens, temp: 0),
      enableThinking: false,
    ).collect();
    return cleanTranslation(completion.text);
  }

  @override
  Future<void> dispose() async {
    await _queue.catchError((_) {});
    final engine = _engine;
    _engine = null;
    _loading = null;
    await engine?.dispose();
  }
}
