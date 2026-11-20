// The phone's way of translating, run against a model on this machine: a
// stretch of a book through the app's own prompts, checks and fixes, with
// an OpenAI-compatible server (llama.cpp's `llama-server`) for the model.
//
//   llama-server -m gemma-4-E4B-it-Q4_0.gguf -c 4096 --reasoning off --port 8089
//   EVAL_SERVER=http://127.0.0.1:8089 EVAL_SOURCE=book.epub \
//   [EVAL_STARTS=906,1950] [EVAL_GLOSSARY=make|book|glossary.json] \
//   [EVAL_FIX=0] [EVAL_OUT=out.json] \
//   flutter test --no-pub tool/translation_eval/device_pipeline_test.dart
//
// The steps are those of `LocalLlmTranslator` (one request for twelve
// paragraphs, each answer cleaned, checked, the flagged ones sent once
// more, what did not come asked alone), without its scheduler and with
// the instructions always sent as a system message. EVAL_GLOSSARY=make
// (the default) has the model make the glossary as the app does;
// EVAL_FIX=0 stops after the first answers (what the checks add shows in
// the difference).

// Dart imports:
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/services/epub_package.dart';
import 'package:openlib/services/translation/book_glossary.dart';
import 'package:openlib/services/translation/glossary_service.dart';
import 'package:openlib/services/translation/paragraph_text.dart';
import 'package:openlib/services/translation/translation_models.dart';
import 'package:openlib/services/translation/translation_qa.dart';
import 'package:openlib/services/translation/translation_style.dart';
import 'package:openlib/services/translation/translator.dart';

import 'eval_common.dart';

/// The model for a request that is not a translation (the glossary).
class _Model implements Translator {
  _Model(this.server);
  final ModelServer server;
  @override
  String? get deviceLabel => 'server';
  @override
  int get batchSize => 12;
  @override
  Future<void> load() async {}
  @override
  Future<void> dispose() async {}
  @override
  Future<String?> complete(String prompt,
      {required int maxTokens,
      TranslationPriority priority = TranslationPriority.background,
      String? head}) {
    final split = head != null && prompt.startsWith(head);
    return server.ask(split ? prompt.substring(head.length).trimLeft() : prompt,
        system: split ? head : null, maxTokens: maxTokens);
  }

  @override
  Future<String> translate(String text,
          {required String targetLanguage,
          String? sourceLanguage,
          String? context,
          String? following,
          TranslationPriority priority =
              TranslationPriority.background}) async =>
      throw UnimplementedError();
  @override
  Future<List<String>> translateBatch(List<String> texts,
          {required String targetLanguage,
          String? sourceLanguage,
          List<String> before = const [],
          List<String?> beforeTranslations = const [],
          Map<String, String> readings = const {},
          BookGlossary glossary = BookGlossary.empty,
          TranslationPriority priority = TranslationPriority.background,
          void Function(int index, String translation)? onEach}) async =>
      throw UnimplementedError();
}

void main() {
  final base = env('EVAL_SERVER');
  final source = env('EVAL_SOURCE');

  test('a stretch of a book, the phone\'s way', () async {
    final server = ModelServer(base!);
    final bytes = Uint8List.fromList(File(source!).readAsBytesSync());
    final paragraphs = epubReaderParagraphs(bytes)!;
    final book = EpubPackage.open(bytes)!;
    final readings = epubRubyReadings(book);
    const size = 12;
    final starts = env('EVAL_STARTS')?.split(',').map(int.parse).toList() ??
        [for (var k = 1; k <= 6; k++) paragraphs.length * k ~/ 7];
    final fix = env('EVAL_FIX') != '0';

    // The glossary.
    final which = env('EVAL_GLOSSARY') ?? 'make';
    final BookGlossary glossary;
    final glossaryWatch = Stopwatch()..start();
    if (which == 'make') {
      final dir = Directory.systemTemp.createTempSync('eval_glossary');
      final service = GlossaryService.instance..directory = () async => dir;
      glossary = await service.make(
          bookFile: 'eval.epub', bookPath: source, translator: _Model(server));
      dir.deleteSync(recursive: true);
    } else if (which == 'book') {
      glossary = glossaryFromBook(source);
    } else {
      glossary = BookGlossary.decode(File(which).readAsStringSync());
    }
    final glossaryPace = server.pace;
    final glossarySeconds = glossaryWatch.elapsed.inSeconds;

    final all = <String>[], out = <String?>[], first = <String?>[];
    final log = <Map<String, Object?>>[];
    var sentBack = 0, kept = 0, alone = 0;
    final why = <String, int>{};
    final watch = Stopwatch()..start();
    for (final start in starts) {
      final texts = paragraphs.sublist(
          start, (start + size).clamp(0, paragraphs.length));
      final before = paragraphs.sublist((start - 3).clamp(0, start), start);
      final head = batchPromptHead(
          texts: texts,
          targetLanguage: 'Korean',
          sourceLanguage: 'Japanese',
          narration: glossary.narrationNote);
      final prompt = batchTranslationPrompt(
          texts: texts,
          targetLanguage: 'Korean',
          sourceLanguage: 'Japanese',
          before: before,
          readings: readingsIn(readings, [...texts, ...before]),
          glossary: glossary.inTexts([...texts, ...before]),
          narration: glossary.narrationNote);
      final maxTokens =
          (texts.fold<int>(0, (n, t) => n + t.length * 3 + 16) + 32)
              .clamp(64, 2048);
      final raw = await server.ask(
          prompt.startsWith(head)
              ? prompt.substring(head.length).trimLeft()
              : prompt,
          system: prompt.startsWith(head) ? head : null,
          maxTokens: maxTokens);
      final got = parseNumberedTranslations(raw, texts.length);
      final results = List<String?>.filled(texts.length, null);
      final drafts = List<String?>.filled(texts.length, null);
      final flagged = <int, (String, List<QaIssue>)>{};
      for (var i = 0; i < texts.length; i++) {
        final answer = got[i];
        if (answer == null) continue;
        final cleaned = cleanTranslation(answer);
        drafts[i] = cleaned;
        if (leftoverSourceScript(cleaned, 'Korean').isNotEmpty) continue;
        final polished = finishTranslation(cleaned, texts[i], 'Korean', glossary);
        if (polished.isEmpty) continue;
        drafts[i] = polished;
        final issues = checkTranslation(texts[i], polished,
            targetLanguage: 'Korean', glossary: glossary);
        if (issues.isNotEmpty) {
          flagged[i] = (polished, issues);
        } else {
          results[i] = polished;
        }
      }
      for (final i in tenseSlips(texts, [
        for (var i = 0; i < texts.length; i++) results[i] ?? flagged[i]?.$1,
      ])) {
        final held = flagged[i];
        if (held != null) {
          flagged[i] = (held.$1, [...held.$2, QaIssue.tenseSlip]);
        } else if (results[i] != null) {
          flagged[i] = (results[i]!, const [QaIssue.tenseSlip]);
          results[i] = null;
        }
      }
      first.addAll(drafts);

      Future<String> refine(String text, String draft, List<QaIssue> issues) async {
        final again = finishTranslation(
            cleanTranslation(await server.ask(
                refinementPrompt(
                        style: head,
                        source: text,
                        draft: draft,
                        issues: issues,
                        glossary: glossary.inTexts([text]),
                        targetLanguage: 'Korean')
                    .substring(head.length)
                    .trimLeft(),
                system: head,
                maxTokens: (text.length * 3 + 32).clamp(64, 1024))),
            text,
            'Korean',
            glossary);
        final after = checkTranslation(text, again,
            targetLanguage: 'Korean',
            glossary: glossary,
            also: {
              for (final q in issues)
                if (styleChecks.contains(q)) q,
            });
        final better = again.isNotEmpty && refinedIsBetter(issues, after);
        sentBack++;
        if (better) kept++;
        for (final q in issues) {
          why[q.name] = (why[q.name] ?? 0) + 1;
        }
        log.add({
          'start': start,
          'issues': [for (final q in issues) q.name],
          'after': [for (final q in after) q.name],
          'kept': better,
          'draft': draft,
          'again': again,
        });
        return better ? again : draft;
      }

      if (fix) {
        for (final MapEntry(key: i, value: (draft, issues)) in flagged.entries) {
          results[i] = await refine(texts[i], draft, issues);
        }
        for (var i = 0; i < texts.length; i++) {
          if (results[i] != null) continue;
          alone++;
          final prompt = buildTranslationPrompt(
              format: TranslationPromptFormat.general,
              text: texts[i],
              targetLanguage: 'Korean',
              sourceLanguage: 'Japanese',
              context: i > 0 ? texts[i - 1] : before.lastOrNull,
              following: i + 1 < texts.length ? texts[i + 1] : null);
          final maxTokens = (texts[i].length * 3 + 32).clamp(64, 1024);
          var answer =
              cleanTranslation(await server.ask(prompt, maxTokens: maxTokens));
          final leftover = leftoverSourceScript(answer, 'Korean');
          if (leftover.isNotEmpty) {
            final again = cleanTranslation(await server.ask(
                retryPrompt(prompt, answer, 'Korean'),
                maxTokens: maxTokens));
            if (again.isNotEmpty &&
                leftoverSourceScript(again, 'Korean').length <
                    leftover.length) {
              answer = again;
            }
          }
          var one = polishTranslation(answer, texts[i], 'Korean');
          if (one.isNotEmpty) one = enforceGlossary(texts[i], one, glossary);
          if (one.isNotEmpty) {
            final issues = checkTranslation(texts[i], one,
                targetLanguage: 'Korean', glossary: glossary);
            if (issues.isNotEmpty) one = await refine(texts[i], one, issues);
          }
          results[i] = one;
        }
      } else {
        for (var i = 0; i < texts.length; i++) {
          results[i] ??= flagged[i]?.$1;
        }
      }
      all.addAll(texts);
      out.addAll(results);
      // ignore: avoid_print
      print('$start: ${results.where((r) => (r ?? '').isNotEmpty).length}/'
          '${texts.length}, flagged ${flagged.length}, ${server.pace}');
    }

    final names = [
      for (final e in glossary.entries)
        if (e.isName && e.target.isNotEmpty) '${e.source}=${e.target}',
    ];
    // ignore: avoid_print
    print('\n용어집: ${glossary.entries.length}항목 '
        '(이름 ${names.length}), ${glossarySeconds}s, $glossaryPace\n'
        '${names.take(40).join(', ')}\n\n'
        '번역: ${watch.elapsed.inSeconds}s (용어집 포함 전체 ${server.pace})\n'
        '다시 쓰기: $sentBack문단 보냄, $kept개 채택, 사유 $why; '
        '따로 번역 $alone문단\n\n'
        '${table({
          if (fix) '첫 답 (검사·수정 전)': measure(all, first, glossary: glossary),
          fix ? '최종 (검사·수정 후)' : '첫 답': measure(all, out, glossary: glossary),
        })}');
    final save = env('EVAL_OUT');
    if (save != null) {
      File(save).writeAsStringSync(const JsonEncoder.withIndent(' ').convert({
        'starts': starts,
        'glossary': glossary.toJson(),
        'sources': all,
        'first': first,
        'final': out,
        'refined': log,
        'pace': server.pace,
      }));
    }
    server.close();
  },
      timeout: const Timeout(Duration(hours: 6)),
      skip: base == null || source == null
          ? 'needs EVAL_SERVER (an OpenAI-compatible server) and EVAL_SOURCE'
          : false);
}
