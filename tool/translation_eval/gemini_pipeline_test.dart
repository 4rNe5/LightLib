// Gemini's way of translating, run for real: a stretch of a book through
// the app's own `GlossaryService` and `CloudTranslator`, against the API.
//
//   EVAL_GEMINI_KEY=... EVAL_SOURCE=book.epub \
//   [EVAL_GEMINI_MODEL=gemini-3.5-flash] [EVAL_STARTS=890,1923] \
//   (or EVAL_CLAUDE_KEY=... [EVAL_CLAUDE_MODEL=claude-sonnet-5-5]
//    [EVAL_CLAUDE_WORKSPACE=wrkspc_...]: the same steps on Claude) \
//   [EVAL_COUNT=80] [EVAL_GLOSSARY=make|book|glossary.json] \
//   [EVAL_STYLE=0] [EVAL_POLISH=1] [EVAL_TRANSLATED=book.ko.epub] \
//   [EVAL_SERIES=volume2.glossary.json] [EVAL_THINKING=balanced] \
//   [EVAL_GATHER=1] \
//   [EVAL_OUT=out.json] \
//   flutter test --no-pub tool/translation_eval/gemini_pipeline_test.dart
//
// It spends the key's quota: one request for each 30,000 characters of
// the book when the glossary is made (EVAL_GLOSSARY=make, the default),
// one for each EVAL_COUNT paragraphs, and one more where paragraphs are
// sent back. EVAL_STYLE=0 turns the style checks off (tense, 그녀);
// EVAL_POLISH=1 turns the reader's "smooth out stiff sentences" on.
// EVAL_TRANSLATED (the EPUB an earlier version exported for the same
// book) puts that translation of the same paragraphs beside the new one.
// EVAL_SERIES (glossaries of the series' other volumes, commas between)
// stands in for the library: what they settled carries over. EVAL_COUNT=0
// makes the glossary and translates nothing. EVAL_GATHER=1 holds the
// paragraphs to send back and sends them together, as a book translated
// on its own does.
// The key is read from the environment and is never written anywhere.

// Dart imports:
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// Package imports:
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/services/epub_package.dart';
import 'package:openlib/services/translation/book_glossary.dart';
import 'package:openlib/services/translation/claude/claude_api.dart';
import 'package:openlib/services/translation/claude/claude_client.dart';
import 'package:openlib/services/translation/claude/claude_settings.dart';
import 'package:openlib/services/translation/cloud_engine.dart';
import 'package:openlib/services/translation/gemini/cloud_translator.dart';
import 'package:openlib/services/translation/gemini/gemini_api.dart';
import 'package:openlib/services/translation/gemini/gemini_client.dart';
import 'package:openlib/services/translation/gemini/gemini_settings.dart';
import 'package:openlib/services/translation/glossary_service.dart';
import 'package:openlib/services/translation/paragraph_text.dart';

import 'eval_common.dart';

/// What each request was and what it cost, read off the traffic.
class _Meter extends Interceptor {
  final requests = <Map<String, Object?>>[];

  /// Paragraphs sent back: source → the draft that failed and why.
  final sentBack = <String, ({String draft, List<String> problems})>{};

  /// What the engine answered each time it read a part of the book.
  final bookRead = <String>[];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra['started'] = DateTime.now();
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final body = response.requestOptions.data;
    var kind = 'other';
    var paragraphs = 0;
    final claude = body is Map && body['messages'] is List;
    final answered = response.data is Map
        ? Map<String, Object?>.from(response.data as Map)
        : const <String, Object?>{};
    if (body is Map) {
      final user = (((body['contents'] as List?)?.firstOrNull as Map?)?['parts']
                  as List?)
              ?.firstOrNull as Map?;
      final text = claude
          ? '${((body['messages'] as List).first as Map)['content'] ?? ''}'
          : '${user?['text'] ?? ''}';
      final at = text.indexOf('\n{');
      Map? data;
      try {
        data = at < 0 ? null : jsonDecode(text.substring(at + 1)) as Map;
      } catch (_) {}
      if (jsonEncode(body['generationConfig'] ?? body['output_config'] ?? body)
          .contains('"entries"')) {
        kind = 'book read';
        try {
          if (claude) {
            bookRead.add(claudeResult(answered).text);
          } else {
            final answer = ((((response.data as Map)['candidates'] as List)
                    .first as Map)['content'] as Map)['parts'] as List;
            bookRead.add('${(answer.first as Map)['text']}');
          }
        } catch (_) {}
      } else if (data?['items'] is List) {
        kind = 'sent back';
        for (final item in (data!['items'] as List).cast<Map>()) {
          paragraphs++;
          sentBack['${item['source']}'] = (
            draft: '${item['draft']}',
            problems: (item['problems'] as List).cast<String>(),
          );
        }
      } else if (data?['paragraphs'] is List) {
        kind = 'translation';
        paragraphs = (data!['paragraphs'] as List).length;
      } else {
        kind = 'glossary lines';
      }
    }
    final usage = answered['usageMetadata'] as Map?;
    int count(String k) => (usage?[k] as num?)?.toInt() ?? 0;
    final said = claude && response.statusCode == 200
        ? claudeResult(answered)
        : null;
    requests.add({
      'kind': kind,
      'status': response.statusCode,
      'paragraphs': paragraphs,
      'prompt': said?.promptTokens ?? count('promptTokenCount'),
      'cached': said != null
          ? claudeCachedTokens(answered)
          : count('cachedContentTokenCount'),
      'output': said?.outputTokens ?? count('candidatesTokenCount'),
      'thought': said?.thoughtTokens ?? count('thoughtsTokenCount'),
      'ms': DateTime.now()
          .difference(response.requestOptions.extra['started'] as DateTime)
          .inMilliseconds,
    });
    handler.next(response);
  }

  Map<String, Map<String, int>> get byKind {
    final out = <String, Map<String, int>>{};
    for (final r in requests) {
      final sum = out.putIfAbsent('${r['kind']}', () => {});
      sum['requests'] = (sum['requests'] ?? 0) + 1;
      if (r['status'] != 200) sum['failed'] = (sum['failed'] ?? 0) + 1;
      for (final k in ['paragraphs', 'prompt', 'cached', 'output', 'thought', 'ms']) {
        sum[k] = (sum[k] ?? 0) + (r[k] as int);
      }
    }
    return out;
  }
}

/// An engine told more than the app tells it: [notes] go after the
/// instructions of every request (a trial of what the app could send).
class _WithNotes implements CloudClient {
  _WithNotes(this.inner);
  final CloudClient inner;
  String notes = '';

  @override
  Future<GeminiResult> generate({
    required String system,
    required String user,
    Map<String, Object?>? schema,
    int? maxOutputTokens,
    int paragraphs = 0,
  }) =>
      inner.generate(
          system: notes.isEmpty ? system : '$system\n\n$notes',
          user: user,
          schema: schema,
          maxOutputTokens: maxOutputTokens,
          paragraphs: paragraphs);
}

const _speechSystem = '''
You are preparing notes for translating a Japanese light novel into Korean.
Read this part of the book and list how its characters speak TO EACH OTHER in dialogue.
For each pair that exchanges at least two lines here, one entry per direction:
- from, to: the names exactly as the book mostly writes them (しずく, 神坂先輩's name without the honorific).
- level: "반말" when from speaks to to in plain forms (だ, だよ, する), "존댓말" when in polite forms (です, ます), "섞임" when it changes.
- calls: how from addresses to in the book, as written (先輩, しずくちゃん, お前); "" when never.
The narrator counts as a character under the name the others call them. No pairs you are not sure of.''';

const _speechSchema = <String, Object?>{
  'type': 'object',
  'properties': {
    'pairs': {
      'type': 'array',
      'items': {
        'type': 'object',
        'properties': {
          'from': {'type': 'string'},
          'to': {'type': 'string'},
          'level': {'type': 'string'},
          'calls': {'type': 'string'},
        },
        'required': ['from', 'to', 'level', 'calls'],
      },
    },
  },
  'required': ['pairs'],
};

const _summarySystem = '''
You are helping a translator who will translate the paragraphs that come right after this stretch of a Japanese light novel.
In at most six plain English sentences say: what has happened in this stretch, and the scene at its end - where it is, who is present, who is talking to whom, and who tells the story.
Write every name exactly as the book writes it, in Japanese. Nothing the text does not say.''';

/// What a trial of "more context" sends: how the characters speak to
/// each other (the book read whole), and where the story is before each
/// stretch (the 200 paragraphs before it, summed up).
Future<Map<String, Object?>> _makeContext(
    CloudClient client, List<String> paragraphs, List<int> starts) async {
  final levels = <String, Map<String, int>>{};
  final calls = <String, String>{};
  for (final chunk in bookAnalysisChunks(paragraphs.join('\n'))) {
    final r = await client.generate(
        system: _speechSystem,
        user: chunk,
        schema: _speechSchema,
        maxOutputTokens: 4096);
    try {
      for (final raw in (jsonDecode(r.text) as Map)['pairs'] as List) {
        final pair = raw as Map;
        final from = '${pair['from']}'.trim(), to = '${pair['to']}'.trim();
        if (from.isEmpty || to.isEmpty || from == to) continue;
        final key = '$from → $to';
        final level = '${pair['level']}'.trim();
        (levels[key] ??= {})[level] = (levels[key]![level] ?? 0) + 1;
        final how = '${pair['calls']}'.trim();
        if (how.isNotEmpty) calls.putIfAbsent(key, () => how);
      }
    } catch (_) {}
  }
  final speech = [
    for (final MapEntry(key: pair, value: seen) in levels.entries)
      '$pair: ${(seen.entries.toList()..sort((a, b) => b.value - a.value)).first.key}'
          '${calls[pair] == null ? '' : ', calls them ${calls[pair]}'}',
  ];
  final summaries = <String, String>{};
  for (final start in starts) {
    if (start < 20) continue;
    final r = await client.generate(
        system: _summarySystem,
        user: paragraphs.sublist((start - 200).clamp(0, start), start).join('\n'),
        maxOutputTokens: 1024);
    summaries['$start'] = r.text.trim();
  }
  return {'speech': speech, 'summaries': summaries};
}

void main() {
  final claudeKey = env('EVAL_CLAUDE_KEY');
  final key = claudeKey ?? env('EVAL_GEMINI_KEY');
  final source = env('EVAL_SOURCE');

  test('a stretch of a book, Gemini\'s way', () async {
    final meter = _Meter();
    final dio = Dio()
      ..httpClientAdapter = IOHttpClientAdapter(
          createHttpClient: () =>
              HttpClient()..findProxy = HttpClient.findProxyFromEnvironment)
      ..interceptors.add(meter);
    final thinking = GeminiThinking.parse(env('EVAL_THINKING'));
    final polish = env('EVAL_POLISH') == '1';
    final String id;
    final CloudClient client;
    final CloudSettings settings;
    double Function(int input, int cached, int output)? price;
    if (claudeKey != null) {
      id = env('EVAL_CLAUDE_MODEL') ?? claudeModels.first.id;
      final model = claudeModels.where((m) => m.id == id).firstOrNull ??
          ClaudeModel(
              id: id,
              label: id,
              inputPrice: 0,
              outputPrice: 0,
              cacheReadShare: 0.1,
              quiet: ClaudeQuiet.never);
      final chosen = ClaudeSettings.instance
        // ignore: invalid_use_of_visible_for_testing_member
        ..debugSet(
            useClaude: true,
            key: claudeKey,
            workspace: env('EVAL_CLAUDE_WORKSPACE') ?? '',
            model: model,
            deviceFallback: false,
            thinking: thinking,
            polish: polish,
            concurrency: 2,
            usageBy: {});
      settings = chosen;
      client = ClaudeClient(dio: dio, settings: chosen);
      price = (input, cached, output) =>
          model.cost(input, output, cached: cached);
    } else {
      id = env('EVAL_GEMINI_MODEL') ?? 'gemini-3.5-flash';
      final known = geminiModels.where((m) => m.id == id).firstOrNull;
      final model = known ??
          GeminiModel(
              id: id,
              label: id,
              inputPrice: 0,
              outputPrice: 0,
              freeRpm: 10,
              freeRpd: 250);
      final chosen = GeminiSettings.instance
        // ignore: invalid_use_of_visible_for_testing_member
        ..debugSet(
            useGemini: true,
            key: key,
            model: model,
            deviceFallback: false,
            thinking: thinking,
            polish: polish,
            usage: GeminiUsage(day: quotaDay(DateTime.now())));
      settings = chosen;
      client = GeminiClient(dio: dio, settings: chosen);
      if (known != null) {
        price = (input, cached, output) => known.cost(input, output);
      }
    }
    final style = env('EVAL_STYLE') != '0';
    final noted = _WithNotes(client);
    final translator = CloudTranslator(
        client: noted,
        settings: settings,
        fixTense: style,
        fixPronouns: style,
        gatherCorrections: env('EVAL_GATHER') == '1',
        device: () async => null);

    final bytes = Uint8List.fromList(File(source!).readAsBytesSync());
    final paragraphs = epubReaderParagraphs(bytes)!;
    final readings = epubRubyReadings(EpubPackage.open(bytes)!);
    final size = int.parse(env('EVAL_COUNT') ?? '80');
    final starts = env('EVAL_STARTS')?.split(',').map(int.parse).toList() ??
        [for (var k = 1; k <= 3; k++) paragraphs.length * k ~/ 4];

    // More context, on trial: made once (EVAL_CONTEXT_MAKE=file, with
    // this run's engine; nothing is translated), then given to any
    // engine (EVAL_CONTEXT=file; EVAL_CONTEXT_USE=speech,summary).
    final makeContext = env('EVAL_CONTEXT_MAKE');
    if (makeContext != null) {
      final made = await _makeContext(client, paragraphs, starts);
      File(makeContext)
          .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(made));
      // ignore: avoid_print
      print('context: ${(made['speech'] as List).length} pairs, '
          '${(made['summaries'] as Map).length} summaries');
      return;
    }
    final contextFile = env('EVAL_CONTEXT');
    final context = contextFile == null
        ? null
        : jsonDecode(File(contextFile).readAsStringSync()) as Map;
    final contextUse = (env('EVAL_CONTEXT_USE') ?? 'speech,summary').split(',');
    String notesFor(int start) {
      if (context == null) return '';
      final speech = (context['speech'] as List).cast<String>();
      final summary = (context['summaries'] as Map)['$start'];
      return [
        if (contextUse.contains('speech') && speech.isNotEmpty)
          'How the characters of this book speak to each other (반말 = '
              'plain speech, 존댓말 = polite speech) - keep each pair the '
              'same unless the scene itself changes it:\n${speech.join('\n')}',
        if (contextUse.contains('summary') && summary != null)
          'Where the story is when these paragraphs begin (to understand '
              'them; never translate or repeat this):\n$summary',
      ].join('\n\n');
    }

    final which = env('EVAL_GLOSSARY') ?? 'make';
    final BookGlossary glossary;
    final watch = Stopwatch()..start();
    if (which == 'make') {
      final dir = Directory.systemTemp.createTempSync('eval_glossary');
      final service = GlossaryService.instance..directory = () async => dir;
      final series = env('EVAL_SERIES')?.split(',') ?? const [];
      if (series.isNotEmpty) {
        GlossaryService.seriesOf = (_) async => [
              for (final path in series)
                BookGlossary.decode(File(path).readAsStringSync()),
            ];
      }
      glossary = await service.make(
          bookFile: 'eval.epub', bookPath: source, translator: translator);
      dir.deleteSync(recursive: true);
    } else if (which == 'book') {
      glossary = glossaryFromBook(source);
    } else {
      glossary = BookGlossary.decode(File(which).readAsStringSync());
    }
    final glossarySeconds = watch.elapsed.inSeconds;

    final all = <String>[], out = <String>[];
    watch.reset();
    for (final start in size == 0 ? const <int>[] : starts) {
      final texts = paragraphs.sublist(
          start, (start + size).clamp(0, paragraphs.length));
      final at = all.length;
      all.addAll(texts);
      out.addAll([for (final _ in texts) '']);
      noted.notes = notesFor(start);
      // (What is handed over later - a correction sent with others'
      // - comes the same way.)
      await translator.translateBatch(texts,
          targetLanguage: 'Korean',
          sourceLanguage: 'Japanese',
          before: paragraphs.sublist((start - 3).clamp(0, start), start),
          readings: readings,
          glossary: glossary,
          onEach: (i, t) => out[at + i] = t);
      // ignore: avoid_print
      print('$start: '
          '${out.sublist(at).where((t) => t.isNotEmpty).length}/${texts.length}');
    }
    await translator.flushCorrections();
    final translateSeconds = watch.elapsed.inSeconds;

    // The first answers: what was sent back, as it stood before.
    final first = [
      for (var i = 0; i < all.length; i++)
        meter.sentBack[all[i]]?.draft ?? out[i],
    ];
    final asked = [
      for (var i = 0; i < all.length; i++)
        if (meter.sentBack.containsKey(all[i])) i,
    ];
    final kept = asked.where((i) => out[i] != first[i]).length;
    final why = <String, int>{};
    for (final i in asked) {
      for (final p in meter.sentBack[all[i]]!.problems) {
        final name = p.contains('End that sentence in the past')
            ? '시제'
            : p.contains('그녀')
                ? '그녀'
                : p.contains('word for word')
                    ? '직역투'
                    : p.split(RegExp(r'[.:(]')).first.trim();
        why[name] = (why[name] ?? 0) + 1;
      }
    }

    final columns = <String, Map<String, Object>>{};
    final earlier = env('EVAL_TRANSLATED');
    var before = const <String?>[];
    if (earlier != null) {
      final was = {for (final (s, t) in pairsOf(source, earlier)) s: t};
      before = [for (final s in all) was[s]];
      columns['이전 번역본'] = measure(all, before, glossary: glossary);
    }
    columns['첫 답'] = measure(all, first, glossary: glossary);
    columns['최종'] = measure(all, out, glossary: glossary);

    final names = [
      for (final e in glossary.entries)
        if (e.target.isNotEmpty) '${e.source}=${e.target}',
    ];
    final cost = StringBuffer();
    var prompt = 0, cached = 0, output = 0;
    for (final MapEntry(key: kind, value: s) in meter.byKind.entries) {
      prompt += s['prompt'] ?? 0;
      cached += s['cached'] ?? 0;
      output += (s['output'] ?? 0) + (s['thought'] ?? 0);
      cost.writeln('| $kind | ${s['requests']} | ${s['failed'] ?? 0} | '
          '${s['paragraphs']} | ${s['prompt']} | ${s['cached']} | '
          '${s['output']} | ${s['thought']} | ${(s['ms']! / 1000).round()} |');
    }
    // ignore: avoid_print
    print('\n모델 $id, 생각 ${thinking.name}, '
        '문체 검사 ${style ? '켬' : '끔'}, '
        '다듬기 ${polish ? '켬' : '끔'}\n'
        '용어집: ${glossary.entries.length}항목 '
        '(이름 ${glossary.entries.where((e) => e.isName).length}), '
        '${glossarySeconds}s\n${names.join(', ')}\n\n'
        '번역: ${all.length}문단, ${translateSeconds}s\n'
        '다시 쓰기: ${asked.length}문단 보냄 '
        '(${all.isEmpty ? 0 : (100 * asked.length / all.length).toStringAsFixed(1)}%), '
        '$kept개 바뀜, 사유 $why\n\n'
        '| 요청 | 수 | 실패 | 문단 | 입력 토큰 | 그중 캐시 | 출력 토큰 | 생각 토큰 | 초 |\n'
        '|---|---|---|---|---|---|---|---|---|\n$cost'
        '합계: 입력 $prompt (캐시 $cached), 출력+생각 $output'
        '${price == null ? '' : ', 유료 요금으로 \$${price(prompt, cached, output).toStringAsFixed(4)}'}\n\n'
        '${all.isEmpty ? '' : table(columns)}');
    final save = env('EVAL_OUT');
    if (save != null) {
      File(save).writeAsStringSync(const JsonEncoder.withIndent(' ').convert({
        'model': id,
        'starts': starts,
        'glossary': glossary.toJson(),
        'sources': all,
        'first': first,
        'final': out,
        // (The earlier translation of the same paragraphs, for the judge:
        // `old=out.json:earlier`.)
        if (before.isNotEmpty) 'earlier': [for (final t in before) t ?? ''],
        'sentBack': {
          for (final i in asked)
            '$i': {
              'problems': meter.sentBack[all[i]]!.problems,
              'draft': first[i],
              'final': out[i],
            },
        },
        'requests': meter.requests,
        'bookRead': meter.bookRead,
      }));
    }
  },
      timeout: const Timeout(Duration(hours: 3)),
      skip: key == null || source == null
          ? 'needs EVAL_GEMINI_KEY or EVAL_CLAUDE_KEY, and EVAL_SOURCE'
          : false);
}
