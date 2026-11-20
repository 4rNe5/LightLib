// Translating with Claude: the request it is sent (no thinking for
// speed, the answer held to a schema, the instructions kept read), what
// its answers and errors say, the count of what each model cost, and a
// batch through the same translator Gemini uses.

// Dart imports:
import 'dart:convert';

// Package imports:
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';

// Project imports:
import 'package:openlib/services/storage/app_files.dart';
import 'package:openlib/services/storage/idb_app_files.dart';
import 'package:openlib/services/translation/claude/claude_api.dart';
import 'package:openlib/services/translation/claude/claude_client.dart';
import 'package:openlib/services/translation/claude/claude_settings.dart';
import 'package:openlib/services/translation/gemini/cloud_translator.dart';
import 'package:openlib/services/translation/gemini/gemini_api.dart';
import 'package:openlib/services/translation/gemini/gemini_settings.dart';
import 'package:openlib/services/translation/translation_engine.dart';

/// The API's stand-in: each request answered by [answer].
class _Api implements HttpClientAdapter {
  _Api(this.answer);
  final (int, Object, Map<String, List<String>>) Function(Map body, int attempt)
      answer;
  final bodies = <Map>[];
  final headers = <Map<String, dynamic>>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    bodies.add(options.data as Map);
    headers.add(options.headers);
    final (status, data, extra) = answer(options.data as Map, bodies.length);
    return ResponseBody.fromString(jsonEncode(data), status, headers: {
      'content-type': ['application/json'],
      ...extra,
    });
  }

  @override
  void close({bool force = false}) {}
}

Map _said(String text,
        {int input = 100,
        int output = 20,
        int cached = 0,
        int thought = 0,
        String stop = 'end_turn'}) =>
    {
      'content': [
        if (thought > 0) {'type': 'thinking', 'thinking': '...'},
        {'type': 'text', 'text': text},
      ],
      'stop_reason': stop,
      'usage': {
        'input_tokens': input,
        'cache_read_input_tokens': cached,
        'output_tokens': output,
        if (thought > 0) 'output_tokens_details': {'thinking_tokens': thought},
      },
    };

Map _error(String type, String message) => {
      'type': 'error',
      'error': {'type': type, 'message': message},
    };

void main() {
  final haiku = claudeModelFor('claude-haiku-5-5');
  final sonnet = claudeModelFor('claude-sonnet-5-5');
  final opus = claudeModelFor('claude-opus-5-5');
  final settings = ClaudeSettings.instance;

  setUp(() {
    settings.debugSet(
        useClaude: true,
        key: 'sk-ant-test',
        workspace: '',
        model: sonnet,
        thinking: GeminiThinking.speed,
        deviceFallback: false,
        polish: false,
        usageBy: {});
  });

  group('the request', () {
    test('a schema as Claude takes one: objects closed, no sizes', () {
      final schema = claudeSchema(translationSchema(3)) as Map;
      expect(schema['additionalProperties'], isFalse);
      final list = (schema['properties'] as Map)['translations'] as Map;
      expect(list.containsKey('minItems'), isFalse);
      expect(list.containsKey('maxItems'), isFalse);
      expect((list['items'] as Map)['additionalProperties'], isFalse);
      expect(jsonEncode(translationSchema(3)), contains('minItems'),
          reason: 'what Gemini is sent keeps its sizes');
    });

    test('speed: no thinking before the answer, each model its own way', () {
      Map request(ClaudeModel m, GeminiThinking t) => claudeRequest(
          system: 's', user: 'u', model: m, thinking: t, maxOutputTokens: 5000);
      expect(request(haiku, GeminiThinking.speed)['thinking'],
          {'type': 'disabled'});
      expect(request(sonnet, GeminiThinking.speed)['thinking'],
          {'type': 'between_tools'});
      // Opus always thinks as much as the effort has it think.
      final quick = request(opus, GeminiThinking.speed);
      expect(quick.containsKey('thinking'), isFalse);
      expect((quick['output_config'] as Map)['effort'], 'low');
      expect(quick['max_tokens'], greaterThan(5000),
          reason: 'room for what it thinks');
      expect(request(haiku, GeminiThinking.speed)['max_tokens'], 5000);

      final careful = request(sonnet, GeminiThinking.quality);
      expect(careful.containsKey('thinking'), isFalse);
      expect((careful['output_config'] as Map)['effort'], 'high');
      expect(careful['max_tokens'],
          5000 + GeminiModel.thinkingRoom(GeminiThinking.quality));
      expect(careful.containsKey('temperature'), isFalse);
    });

    test(
        'the instructions are marked to be kept read; the schema goes '
        'with the answer\'s format', () {
      final r = claudeRequest(
          system: 'instructions',
          user: 'paragraphs',
          model: sonnet,
          schema: translationSchema(2));
      final system = (r['system'] as List).single as Map;
      expect(system['text'], 'instructions');
      expect(system['cache_control'], {'type': 'ephemeral'});
      expect((r['messages'] as List).single,
          {'role': 'user', 'content': 'paragraphs'});
      final format = (r['output_config'] as Map)['format'] as Map;
      expect(format['type'], 'json_schema');
      expect((format['schema'] as Map)['type'], 'object');
    });
  });

  group('the answer', () {
    test('text, and tokens: the cache\'s are the prompt\'s, thinking apart',
        () {
      final r = claudeResult(Map<String, Object?>.from(
          _said('안녕', input: 40, cached: 300, output: 90, thought: 60)));
      expect(r.text, '안녕');
      expect(r.promptTokens, 340);
      expect(r.outputTokens, 30);
      expect(r.thoughtTokens, 60);
      expect(r.billedOutput, 90);
      expect(r.finishReason, 'STOP');
      expect(r.block, isNull);
      expect(
          claudeCachedTokens(
              Map<String, Object?>.from(_said('x', cached: 300))),
          300);
    });

    test('a refusal is a paragraph kept as written; a cut answer is told', () {
      final refused =
          claudeResult(Map<String, Object?>.from(_said('', stop: 'refusal')));
      expect(refused.block, GeminiBlockKind.prohibited);
      final cut = claudeResult(
          Map<String, Object?>.from(_said('{"tr', stop: 'max_tokens')));
      expect(cut.finishReason, 'MAX_TOKENS');
    });

    test('errors by what can be done about them', () {
      GeminiErrorKind kind(int status, String type, String message) =>
          claudeError(status, _error(type, message)).kind;
      expect(
          kind(400, 'invalid_request_error',
              'Your credit balance is too low to access the Anthropic API.'),
          GeminiErrorKind.quotaExhausted);
      expect(kind(401, 'authentication_error', 'invalid x-api-key'),
          GeminiErrorKind.badKey);
      expect(
          kind(400, 'invalid_request_error',
              'anthropic-workspace-id header is required for this key'),
          GeminiErrorKind.badKey);
      expect(kind(403, 'permission_error', 'no'), GeminiErrorKind.badKey);
      expect(
          kind(529, 'overloaded_error', 'Overloaded'), GeminiErrorKind.server);
      expect(kind(400, 'invalid_request_error', 'max_tokens: too large'),
          GeminiErrorKind.badRequest);
      final wait = claudeError(429, _error('rate_limit_error', 'slow down'),
          retryAfter: '7');
      expect(wait.kind, GeminiErrorKind.rateLimited);
      expect(wait.retryAfter, const Duration(seconds: 7));
      expect(claudeError(502, '<html>bad gateway</html>').kind,
          GeminiErrorKind.server);
    });

    test('what it costs: the cache at its own price', () {
      expect(haiku.cost(1000000, 1000000), closeTo(0.60, 1e-9));
      expect(sonnet.cost(1000000, 0, cached: 1000000),
          closeTo(sonnet.inputPrice * sonnet.cacheReadShare, 1e-9));
      expect(claudeModelFor('no-such-model').id, claudeModels.first.id);
    });
  });

  group('the client', () {
    ClaudeClient client(_Api api, {List<Duration>? slept}) => ClaudeClient(
        dio: Dio()..httpClientAdapter = api,
        settings: settings,
        sleep: (d) async => slept?.add(d));

    test('the key, the version, and the workspace only when one is set',
        () async {
      final api = _Api((_, __) => (200, _said('OK'), const {}));
      await client(api).generate(system: 's', user: 'u');
      expect(api.headers.single['x-api-key'], 'sk-ant-test');
      expect(api.headers.single['anthropic-version'], '2023-06-01');
      expect(api.headers.single.containsKey('anthropic-workspace-id'), isFalse);
      expect(api.bodies.single['model'], sonnet.id);

      settings.debugSet(workspace: 'wrkspc_1');
      await client(api).generate(system: 's', user: 'u', model: haiku);
      expect(api.headers.last['anthropic-workspace-id'], 'wrkspc_1');
      expect(api.bodies.last['model'], haiku.id);
    });

    test('asked to wait: waits as long as it says, then asks again', () async {
      final slept = <Duration>[];
      final api = _Api((_, attempt) => attempt == 1
          ? (
              429,
              _error('rate_limit_error', 'slow down'),
              {
                'retry-after': ['3']
              }
            )
          : attempt == 2
              ? (529, _error('overloaded_error', 'Overloaded'), const {})
              : (200, _said('OK'), const {}));
      final r =
          await client(api, slept: slept).generate(system: 's', user: 'u');
      expect(r.text, 'OK');
      expect(api.bodies, hasLength(3));
      expect(slept.first, const Duration(seconds: 3));
      expect(settings.usage.requests, 1, reason: 'only the answer counts');
    });

    test('no credit: nothing more is asked, of any model', () async {
      final api = _Api((_, __) => (
            400,
            _error('invalid_request_error',
                'Your credit balance is too low to access the Anthropic API.'),
            const {}
          ));
      await expectLater(
          client(api).generate(system: 's', user: 'u'),
          throwsA(isA<GeminiError>()
              .having((e) => e.kind, 'kind', GeminiErrorKind.quotaExhausted)));
      expect(api.bodies, hasLength(1));
      expect(settings.exhausted, isTrue);
      expect(settings.usageOf(haiku).exhausted, isTrue);
    });

    test('a key that does not work is said at once; none is not sent',
        () async {
      final api = _Api((_, __) =>
          (401, _error('authentication_error', 'invalid x-api-key'), const {}));
      await expectLater(
          client(api).test(apiKey: 'sk-ant-wrong'),
          throwsA(isA<GeminiError>()
              .having((e) => e.kind, 'kind', GeminiErrorKind.badKey)));
      expect(api.bodies, hasLength(1));
      expect(api.headers.single['x-api-key'], 'sk-ant-wrong');

      settings.debugSet(key: '');
      await expectLater(client(api).generate(system: 's', user: 'u'),
          throwsA(isA<GeminiError>()));
      expect(api.bodies, hasLength(1));
    });
  });

  group('today\'s use', () {
    test('each model its own count and its own price', () {
      settings.recordRequest(
          const GeminiResult(
              text: '', promptTokens: 1000000, outputTokens: 100000),
          paragraphs: 80,
          model: haiku);
      settings.recordRequest(
          const GeminiResult(
              text: '',
              promptTokens: 1000000,
              outputTokens: 60000,
              thoughtTokens: 40000),
          paragraphs: 80,
          model: sonnet,
          cached: 500000);
      expect(settings.usageOf(haiku).requests, 1);
      expect(settings.costOf(haiku), closeTo(0.10 + 0.05, 1e-9));
      // Half the prompt read from the cache (5% of the price), and what
      // it thought billed as output.
      expect(settings.costOf(sonnet),
          closeTo(0.5 * 2 + 0.5 * 2 * 0.05 + 0.1 * 10, 1e-9));
      expect(settings.usage.requests, 1, reason: 'Sonnet is the chosen one');
      expect(settings.otherModelsToday.keys.single.id, haiku.id);
      expect(settings.costToday,
          closeTo(settings.costOf(haiku) + settings.costOf(sonnet), 1e-9));
      expect(settings.costOf(opus), 0);
    });

    test('a new day starts at zero', () {
      var now = DateTime.utc(2026, 11, 20, 12);
      final clock = settings.clock;
      settings.clock = () => now;
      addTearDown(() => settings.clock = clock);
      settings.debugSet(usageBy: {});
      settings.recordRequest(
          const GeminiResult(text: '', promptTokens: 500, outputTokens: 50),
          model: sonnet,
          cached: 100);
      expect(settings.usage.requests, 1);
      now = now.add(const Duration(days: 1));
      expect(settings.usage.requests, 0);
      expect(settings.costOf(sonnet), 0);
    });

    test(
        'a new key: the used-up credit is forgotten, the key kept in its '
        'own file', () async {
      final files = AppFiles.instance;
      final keyPath = settings.keyPath;
      AppFiles.instance = IdbAppFiles(newIdbFactoryMemory());
      settings.keyPath = () async => '/support/claude_api_key';
      addTearDown(() {
        AppFiles.instance = files;
        settings.keyPath = keyPath;
      });
      settings.recordLimit(
          const GeminiError(GeminiErrorKind.quotaExhausted, 'no credit'));
      expect(settings.exhausted, isTrue);
      await settings.setKey('  sk-ant-new-key-9876 ', workspace: ' wrkspc_2 ');
      expect(settings.exhausted, isFalse);
      expect(settings.apiKey, 'sk-ant-new-key-9876');
      expect(settings.workspace, 'wrkspc_2');
      expect(settings.keyHint, '…9876');
      expect(await AppFiles.instance.readString('/support/claude_api_key'),
          'sk-ant-new-key-9876');
      await settings.setKey('');
      expect(settings.active, isFalse);
      expect(
          await AppFiles.instance.exists('/support/claude_api_key'), isFalse);
    });
  });

  group('the key between devices', () {
    test('typed here: announced, with its workspace; from another device: '
        'kept and not announced; removed there: removed here', () async {
      final files = AppFiles.instance;
      final keyPath = settings.keyPath;
      AppFiles.instance = IdbAppFiles(newIdbFactoryMemory());
      settings.keyPath = () async => '/support/claude_api_key';
      var announced = 0;
      ClaudeSettings.onKeyChanged = () => announced++;
      addTearDown(() {
        AppFiles.instance = files;
        settings.keyPath = keyPath;
        ClaudeSettings.onKeyChanged = null;
      });
      settings.debugSet(key: '', workspace: '');
      expect(settings.sharedValue, '');

      await settings.setKey('sk-ant-here', workspace: 'wrkspc_1');
      expect(announced, 1);
      expect(jsonDecode(settings.sharedValue),
          {'key': 'sk-ant-here', 'workspace': 'wrkspc_1'});

      settings.recordLimit(
          const GeminiError(GeminiErrorKind.quotaExhausted, 'no credit'));
      await settings.applySynced(jsonEncode({'key': 'sk-ant-there'}));
      expect(announced, 1);
      expect(settings.apiKey, 'sk-ant-there');
      expect(settings.workspace, '');
      expect(settings.exhausted, isFalse, reason: 'another key, its own credit');
      expect(await AppFiles.instance.readString('/support/claude_api_key'),
          'sk-ant-there');

      await settings.applySynced('');
      expect(settings.hasKey, isFalse);
      expect(await AppFiles.instance.exists('/support/claude_api_key'),
          isFalse);
      expect(announced, 1);
    });
  });

  group('one engine at a time', () {
    test('choosing Claude takes the choice from Gemini, and back', () async {
      final gemini = GeminiSettings.instance
        ..debugSet(useGemini: true, key: 'AIzaTEST');
      settings.debugSet(useClaude: false);
      expect(await TranslationEngines.cloud(), isTrue);

      await settings.setUseClaude(true);
      expect(gemini.useGemini, isFalse);
      expect(settings.active, isTrue);
      expect(await TranslationEngines.cloud(), isTrue);

      await gemini.setUseGemini(true);
      expect(settings.useClaude, isFalse);
      expect(gemini.active, isTrue);

      await gemini.setUseGemini(false);
      expect(await TranslationEngines.cloud(), isFalse);
    });
  });

  group('a batch through the translator', () {
    test('one request, one translation each, counted as Claude\'s', () async {
      final api = _Api((body, _) {
        final user =
            ((body['messages'] as List).single as Map)['content'] as String;
        final data = jsonDecode(user.substring(user.indexOf('\n{') + 1)) as Map;
        final list = (data['paragraphs'] as List).cast<Map>();
        return (
          200,
          _said(
              jsonEncode({
                'translations': [
                  for (final p in list) {'n': p['n'], 'text': '번역 ${p['n']}'}
                ]
              }),
              input: 900,
              cached: 600,
              output: 120),
          const {}
        );
      });
      final translator = CloudTranslator(
          client: ClaudeClient(
              dio: Dio()..httpClientAdapter = api,
              settings: settings,
              sleep: (_) async {}),
          settings: settings,
          fixTense: false,
          fixPronouns: false,
          device: () async => null);
      expect(translator.deviceLabel, 'Claude');
      final out = await translator.translateBatch(
          ['一つ目の段落。', '二つ目の段落。', '三つ目の段落。'],
          targetLanguage: 'Korean', sourceLanguage: 'Japanese');
      expect(out, ['번역 1', '번역 2', '번역 3']);
      expect(api.bodies, hasLength(1));
      final body = api.bodies.single;
      expect(body['thinking'], {'type': 'between_tools'});
      expect(
          jsonEncode((body['output_config'] as Map)['format']),
          allOf(contains('"translations"'),
              contains('"additionalProperties":false')));
      expect(settings.usage.requests, 1);
      expect(settings.usage.paragraphs, 3);
      expect(settings.usage.promptTokens, 1500);
      expect(settings.costOf(sonnet),
          closeTo((900 * 2 + 600 * 2 * 0.05 + 120 * 10) / 1e6, 1e-12));
    });

    test(
        'a refused request: its paragraphs are found one by one and kept '
        'as written', () async {
      final api = _Api((body, _) {
        final user =
            ((body['messages'] as List).single as Map)['content'] as String;
        final data = jsonDecode(user.substring(user.indexOf('\n{') + 1)) as Map;
        final list = (data['paragraphs'] as List).cast<Map>();
        if (list.any((p) => '${p['text']}'.contains('禁'))) {
          return (200, _said('', stop: 'refusal'), const {});
        }
        return (
          200,
          _said(jsonEncode({
            'translations': [
              for (final p in list) {'n': p['n'], 'text': '번역됨'}
            ]
          })),
          const {}
        );
      });
      final translator = CloudTranslator(
          client: ClaudeClient(
              dio: Dio()..httpClientAdapter = api,
              settings: settings,
              sleep: (_) async {}),
          settings: settings,
          fixTense: false,
          fixPronouns: false,
          device: () async => null);
      final out = await translator.translateBatch(
          ['一つ目の段落。', '禁じられた段落。', '三つ目の段落。', '四つ目の段落。'],
          targetLanguage: 'Korean', sourceLanguage: 'Japanese');
      expect(out[0], '번역됨');
      expect(out[1], isNot('번역됨'));
      expect(out[2], '번역됨');
      expect(out[3], '번역됨');
      expect(settings.usage.blockedProhibited, 1);
    });
  });
}
