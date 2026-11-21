// Which engine translates - the model on the phone, Gemini or Claude -
// for the reader and for library books, and under which id their
// translations are kept (one set for every engine, per style).

// Flutter imports:
import 'package:flutter/foundation.dart' show kIsWeb;

// Project imports:
import 'package:openlib/services/translation/book_glossary.dart';
import 'package:openlib/services/translation/claude/claude_client.dart';
import 'package:openlib/services/translation/claude/claude_settings.dart';
import 'package:openlib/services/translation/cloud_engine.dart';
import 'package:openlib/services/translation/gemini/cloud_translator.dart';
import 'package:openlib/services/translation/gemini/gemini_client.dart';
import 'package:openlib/services/translation/gemini/gemini_settings.dart';
import 'package:openlib/services/translation/translation_cache.dart';
import 'package:openlib/services/translation/translation_model_store.dart';
import 'package:openlib/services/translation/translation_models.dart';
import 'package:openlib/services/translation/translator.dart';

class TranslationEngines {
  TranslationEngines._();

  /// An engine off the phone (Gemini, Claude) is chosen and has a key.
  static Future<bool> cloud() async => await _chosen() != null;

  /// That engine: what sends its requests, and the reader's choices for
  /// it.
  static Future<({CloudClient client, CloudSettings settings})?>
      _chosen() async {
    await ClaudeSettings.instance.load();
    if (ClaudeSettings.instance.active) {
      return (client: ClaudeClient.shared, settings: ClaudeSettings.instance);
    }
    await GeminiSettings.instance.load();
    if (GeminiSettings.instance.active) {
      return (client: GeminiClient.shared, settings: GeminiSettings.instance);
    }
    return null;
  }

  /// The id translations are kept under (one set for every engine, per
  /// style); null when nothing can translate (no model on the phone,
  /// no engine off it set up).
  static Future<String?> cacheModelId() async {
    if (!await cloud() &&
        (kIsWeb ||
            await TranslationModelStore.instance.activeModel() == null)) {
      return null;
    }
    return TranslationCache.sharedModelId(
        lightNovel: TranslationStyle.lightNovel);
  }

  /// [bookFileName]'s translations into [targetLanguage]: the one shared
  /// set, started from what earlier versions kept per model (the active
  /// model's first).
  static Future<TranslationCache> openCache({
    required String bookFileName,
    required String targetLanguage,
  }) async {
    final lightNovel = TranslationStyle.lightNovel;
    return TranslationCache.open(
      bookFileName: bookFileName,
      targetLanguage: targetLanguage,
      modelId: TranslationCache.sharedModelId(lightNovel: lightNovel),
      mergeFrom: await legacyCacheIds(lightNovel: lightNovel),
    );
  }

  /// The ids earlier versions kept translations under (per model and
  /// prompt format), the active model's first: merged into the shared
  /// set when it is first made.
  static Future<List<String>> legacyCacheIds({required bool lightNovel}) async {
    // The web never had any.
    if (kIsWeb) return const [];
    final active = await TranslationModelStore.instance
        .activeModel()
        .catchError((_) => null);
    final installed = await TranslationModelStore.instance
        .installed()
        .catchError((_) => <InstalledModel>[]);
    final names = <String>{
      if (active != null) active.fileName,
      for (final m in installed) m.fileName,
      for (final m in translationModelPresets) m.fileName,
    };
    final style = lightNovel ? '' : '+plain';
    return [
      for (final n in names) ...[
        '$n$style',
        for (final f in TranslationPromptFormat.values)
          if (f != TranslationPromptFormat.general) '$n$style+${f.name}',
      ],
    ];
  }

  /// The reader's translator: the page on screen goes first.
  static Future<Translator?> forReader() async {
    final engine = await _chosen();
    if (engine != null) {
      return CloudTranslator(
        client: engine.client,
        settings: engine.settings,
        // A screenful at a time, so the first page comes quickly.
        batchSize: 24,
        device: () async {
          final shared = await SharedTranslationEngine.instance.acquire();
          return shared == null ? null : UrgentTranslator(shared);
        },
      );
    }
    final shared = await SharedTranslationEngine.instance.acquire();
    return shared == null ? null : UrgentTranslator(shared);
  }

  /// Library books' translator (background priority on the phone).
  static Future<Translator?> forLibrary() async {
    final engine = await _chosen();
    if (engine != null) {
      return CloudTranslator(
          client: engine.client,
          settings: engine.settings,
          // A book on its own: the paragraphs to send back go together.
          gatherCorrections: true,
          device: () async {
            final shared = await SharedTranslationEngine.instance.acquire();
            return shared == null ? null : SharedHandle(shared);
          });
    }
    final shared = await SharedTranslationEngine.instance.acquire();
    return shared == null ? null : SharedHandle(shared);
  }
}

/// A hold on the shared engine at its own priorities; disposing it lets
/// the engine go.
class SharedHandle implements Translator {
  SharedHandle(this.inner);
  final LocalLlmTranslator inner;
  bool _released = false;

  @override
  String? get deviceLabel => inner.deviceLabel;

  @override
  int get batchSize => inner.batchSize;

  @override
  Future<void> load() => inner.load();

  @override
  Future<String> translate(String text,
          {required String targetLanguage,
          String? sourceLanguage,
          String? context,
          String? following,
          TranslationPriority priority = TranslationPriority.background}) =>
      inner.translate(text,
          targetLanguage: targetLanguage,
          sourceLanguage: sourceLanguage,
          context: context,
          following: following,
          priority: priority);

  @override
  Future<List<String>> translateBatch(
    List<String> texts, {
    required String targetLanguage,
    String? sourceLanguage,
    List<String> before = const [],
    List<String?> beforeTranslations = const [],
    Map<String, String> readings = const {},
    BookGlossary glossary = BookGlossary.empty,
    TranslationPriority priority = TranslationPriority.background,
    void Function(int index, String translation)? onEach,
  }) =>
      inner.translateBatch(texts,
          targetLanguage: targetLanguage,
          sourceLanguage: sourceLanguage,
          before: before,
          beforeTranslations: beforeTranslations,
          readings: readings,
          glossary: glossary,
          priority: priority,
          onEach: onEach);

  @override
  Future<String?> complete(String prompt,
          {required int maxTokens,
          TranslationPriority priority = TranslationPriority.background,
          String? head}) =>
      inner.complete(prompt,
          maxTokens: maxTokens, priority: priority, head: head);

  @override
  Future<void> dispose() async {
    if (_released) return;
    _released = true;
    SharedTranslationEngine.instance.release();
  }
}
