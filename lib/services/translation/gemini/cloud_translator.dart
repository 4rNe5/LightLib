// A [Translator] on Gemini: many paragraphs per request, the answer
// constrained to exactly one translation each, the app's own style
// instructions and the book's glossary. What Gemini cannot translate goes
// to the model on the phone (the day's quota, a filter, no connection) -
// except paragraphs the API refuses under its own policy whatever the
// settings say: those stay in the original, and are not sent elsewhere.

// Dart imports:
import 'dart:async';
import 'dart:convert';

// Project imports:
import 'package:openlib/services/epub_package.dart' show readingsIn;
import 'package:openlib/services/logger.dart';
import 'package:openlib/services/translation/book_glossary.dart';
import 'package:openlib/services/translation/gemini/gemini_api.dart';
import 'package:openlib/services/translation/gemini/gemini_client.dart';
import 'package:openlib/services/translation/gemini/gemini_settings.dart';
import 'package:openlib/services/translation/translation_models.dart';
import 'package:openlib/services/translation/translator.dart';

/// The instructions (system) and the request (user) for [texts].
({String system, String user}) cloudTranslationPrompt({
  required List<String> texts,
  required String targetLanguage,
  String? sourceLanguage,
  List<String> before = const [],
  List<String?> beforeTranslations = const [],
  List<MapEntry<String, String>> readings = const [],
  List<GlossaryEntry> glossary = const [],
  bool lightNovelStyle = true,
  String? narration,
}) {
  final system = StringBuffer(batchPromptHead(
      texts: texts,
      targetLanguage: targetLanguage,
      sourceLanguage: sourceLanguage,
      lightNovelStyle: lightNovelStyle,
      narration: narration));
  if (glossary.isNotEmpty) {
    system
      ..writeln()
      ..writeln()
      ..writeln('Names and terms in this book - write them exactly like this '
          '(a gender tells how that person speaks and is spoken of):');
    for (final e in glossary) {
      system.writeln(e.promptLine);
    }
  }
  final covered = {for (final e in glossary) e.source};
  final hints = [
    for (final r in readings)
      if (!covered.any((c) => c.contains(r.key))) r,
  ];
  if (hints.isNotEmpty) {
    system
      ..writeln()
      ..writeln()
      ..writeln('Readings of names and words in this book (write names as '
          'they are read, in $targetLanguage letters; translate ordinary '
          'words by meaning):');
    for (final r in hints) {
      system.writeln('${r.key} = ${r.value}');
    }
  }
  system
    ..writeln()
    ..writeln()
    ..write('You receive a JSON array of consecutive paragraphs. Answer with '
        '{"translations": [...]}: exactly one $targetLanguage translation per '
        'paragraph, in the same order - never merge, split, skip or add '
        'paragraphs, and add no notes or explanations of your own.');

  final user = StringBuffer();
  if (before.isNotEmpty) {
    user.writeln('The story just before (context only, do not translate it '
        'again):');
    for (var i = 0; i < before.length; i++) {
      user.writeln(before[i]);
      final done = i < beforeTranslations.length ? beforeTranslations[i] : null;
      if (done != null && done.isNotEmpty) user.writeln('→ $done');
    }
    user.writeln();
  }
  user
    ..writeln('Translate these ${texts.length} paragraphs:')
    ..write(jsonEncode(texts));
  return (system: system.toString(), user: user.toString());
}

class CloudTranslator implements Translator {
  CloudTranslator({
    GeminiClient? client,
    GeminiSettings? settings,
    this.batchSize = 80,
    Future<Translator?> Function()? device,
  })  : _client = client ?? GeminiClient.shared,
        _settings = settings ?? GeminiSettings.instance,
        _deviceSource = device;

  final GeminiClient _client;
  final GeminiSettings _settings;

  /// The model on the phone, made on first need (null: none installed).
  final Future<Translator?> Function()? _deviceSource;
  Future<Translator?>? _device;
  final AppLogger _logger = AppLogger();

  /// Paragraphs per request: the reader asks for a screenful at a time,
  /// a whole-book run for many more.
  @override
  final int batchSize;

  /// Requests that may be in flight at once for a book.
  int get concurrency => _settings.concurrency;

  @override
  String? get deviceLabel => 'Gemini';

  @override
  Future<void> load() async {}

  Future<Translator?> _onDevice() =>
      _device ??= (_deviceSource?.call() ?? Future<Translator?>.value())
          .catchError((_) => null);

  @override
  Future<String> translate(
    String text, {
    required String targetLanguage,
    String? sourceLanguage,
    String? context,
    String? following,
    TranslationPriority priority = TranslationPriority.background,
  }) async {
    final out = await translateBatch([text],
        targetLanguage: targetLanguage,
        sourceLanguage: sourceLanguage,
        before: context == null ? const [] : [context],
        priority: priority);
    return out.first;
  }

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
  }) async {
    final results = List<String>.filled(texts.length, '');
    void deliver(int i, String t) {
      results[i] = t;
      if (t.isNotEmpty) onEach?.call(i, t);
    }

    Future<void> onDevice(List<int> indexes) async {
      if (!_settings.deviceFallback) return;
      final device = await _onDevice();
      if (device == null) return;
      final outs = await device.translateBatch(
          [for (final i in indexes) texts[i]],
          targetLanguage: targetLanguage,
          sourceLanguage: sourceLanguage,
          before: before,
          beforeTranslations: beforeTranslations,
          readings: readings,
          glossary: glossary,
          priority: priority,
          onEach: (k, t) => deliver(indexes[k], t));
      for (var k = 0; k < outs.length; k++) {
        if (results[indexes[k]].isEmpty && outs[k].isNotEmpty) {
          deliver(indexes[k], outs[k]);
        }
      }
      _settings.recordOnDevice(indexes.length);
    }

    Future<void> run(List<int> indexes, {int depth = 0}) async {
      if (_settings.usage.exhausted) return onDevice(indexes);
      final part = [for (final i in indexes) texts[i]];
      final prompt = cloudTranslationPrompt(
        texts: part,
        targetLanguage: targetLanguage,
        sourceLanguage: sourceLanguage,
        before: before,
        beforeTranslations: beforeTranslations,
        readings: readingsIn(readings, [...part, ...before]),
        glossary: glossary.inTexts([...part, ...before], limit: 60),
        lightNovelStyle: TranslationStyle.lightNovel,
        narration: targetLanguage == 'Korean' ? glossary.narrationNote : null,
      );
      final GeminiResult result;
      try {
        result = await _client.generate(
          system: prompt.system,
          user: prompt.user,
          schema: translationSchema(part.length),
          maxOutputTokens:
              (part.fold<int>(0, (n, t) => n + t.length * 3) + 1024)
                  .clamp(1024, 65536),
          paragraphs: part.length,
        );
      } on GeminiError catch (e) {
        if (e.kind == GeminiErrorKind.badKey ||
            e.kind == GeminiErrorKind.badRequest) {
          rethrow;
        }
        // The day's quota, the service down, no connection.
        _logger.warning('Gemini unavailable, translating on the device',
            tag: 'Gemini', metadata: {'kind': e.kind.name});
        return onDevice(indexes);
      }
      final block = result.block;
      if (block != null) {
        // Find the paragraphs that were blocked: the rest still goes.
        if (indexes.length > 1) {
          final half = indexes.length ~/ 2;
          await run(indexes.sublist(0, half), depth: depth + 1);
          await run(indexes.sublist(half), depth: depth + 1);
          return;
        }
        _settings.recordBlocked(block, 1);
        _logger.info('Gemini blocked a paragraph',
            tag: 'Gemini', metadata: {'kind': block.name});
        if (block == GeminiBlockKind.prohibited) {
          // Refused under the API's own policy: kept as written, not
          // routed around the refusal.
          deliver(indexes.single, texts[indexes.single]);
          return;
        }
        return onDevice(indexes);
      }
      final got = parseTranslations(result.text, part.length);
      if (got == null || got.any((t) => t.isEmpty)) {
        // A cut-off or malformed answer: smaller requests, then the phone.
        if (indexes.length > 1 && depth < 3) {
          final half = indexes.length ~/ 2;
          await run(indexes.sublist(0, half), depth: depth + 1);
          await run(indexes.sublist(half), depth: depth + 1);
          return;
        }
        return onDevice(indexes);
      }
      for (var k = 0; k < got.length; k++) {
        deliver(indexes[k], got[k]);
      }
    }

    await run([for (var i = 0; i < texts.length; i++) i]);
    return results;
  }

  @override
  Future<String?> complete(String prompt,
      {required int maxTokens,
      TranslationPriority priority = TranslationPriority.background,
      String? head}) async {
    if (_settings.usage.exhausted) {
      final device = await _onDevice();
      return device?.complete(prompt,
          maxTokens: maxTokens, priority: priority, head: head);
    }
    final split = head != null && prompt.startsWith(head);
    try {
      final r = await _client.generate(
        system: split ? head : 'Follow the instructions exactly.',
        user: split ? prompt.substring(head.length).trimLeft() : prompt,
        maxOutputTokens: maxTokens * 2 + 512,
      );
      if (r.block != null || r.text.trim().isEmpty) return null;
      return r.text;
    } on GeminiError catch (e) {
      if (e.kind == GeminiErrorKind.badKey) rethrow;
      final device = await _onDevice();
      return device?.complete(prompt,
          maxTokens: maxTokens, priority: priority, head: head);
    }
  }

  @override
  Future<void> dispose() async {
    final device = await _device;
    await device?.dispose();
  }
}
