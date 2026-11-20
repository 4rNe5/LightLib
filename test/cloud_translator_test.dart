// Translating with Gemini: a batch in one request, blocked paragraphs
// found and handled (filters to the phone, policy refusals kept as
// written), the day's quota handing over to the phone, and today's use.

// Dart imports:
import 'dart:convert';

// Package imports:
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/services/translation/book_glossary.dart';
import 'package:openlib/services/translation/gemini/cloud_translator.dart';
import 'package:openlib/services/translation/gemini/gemini_api.dart';
import 'package:openlib/services/translation/gemini/gemini_client.dart';
import 'package:openlib/services/translation/gemini/gemini_settings.dart';
import 'package:openlib/services/translation/translator.dart';

/// Answers each request with [answer] on its JSON input.
class _Server implements HttpClientAdapter {
  _Server(this.answer);
  final (int, Object) Function(List<String> paragraphs, Map body) answer;
  final List<Map> bodies = [];
  final List<Map> refinements = [];
  final List<List?> contexts = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    final body = options.data as Map;
    bodies.add(body);
    final user = ((body['contents'] as List).first['parts'] as List)
        .first['text'] as String;
    final start = user.indexOf('\n{');
    final data0 =
        start < 0 ? null : jsonDecode(user.substring(start + 1)) as Map;
    final List<String> list;
    if (data0 == null) {
      list = [];
    } else if (data0['items'] is List) {
      final items = (data0['items'] as List).cast<Map>();
      refinements.addAll(items);
      list = [for (final x in items) 'FIX:${x['source']}'];
    } else {
      contexts.add(data0['context'] as List?);
      list = [
        for (final x in (data0['paragraphs'] as List).cast<Map>())
          x['text'] as String
      ];
    }
    final (status, data) = answer(list, body);
    return ResponseBody.fromString(jsonEncode(data), status, headers: {
      'content-type': ['application/json']
    });
  }

  @override
  void close({bool force = false}) {}
}

/// A Korean stand-in for a test paragraph (no kana left, so it passes
/// the checks).
String ko(String t) => '번역${t.runes.first}';

Map _ok(List<String> out) => {
      'candidates': [
        {
          'content': {
            'parts': [
              {
                'text': jsonEncode({
                  'translations': [
                    for (var i = 0; i < out.length; i++)
                      {'n': i + 1, 'text': out[i]}
                  ]
                })
              }
            ]
          },
          'finishReason': 'STOP'
        }
      ],
      'usageMetadata': {'promptTokenCount': 100, 'candidatesTokenCount': 20},
    };

Map _blocked(String reason) => {
      'promptFeedback': {'blockReason': reason}
    };

/// The phone's model, as a stand-in: "device:" before each text.
class _Device implements Translator {
  final List<String> asked = [];
  @override
  String? get deviceLabel => 'CPU';
  @override
  int get batchSize => 12;
  @override
  Future<void> load() async {}
  @override
  Future<String> translate(String text,
          {required String targetLanguage,
          String? sourceLanguage,
          String? context,
          String? following,
          TranslationPriority priority =
              TranslationPriority.background}) async =>
      'device:$text';
  @override
  Future<List<String>> translateBatch(List<String> texts,
      {required String targetLanguage,
      String? sourceLanguage,
      List<String> before = const [],
      List<String?> beforeTranslations = const [],
      Map<String, String> readings = const {},
      BookGlossary glossary = BookGlossary.empty,
      TranslationPriority priority = TranslationPriority.background,
      void Function(int index, String translation)? onEach}) async {
    asked.addAll(texts);
    final out = [for (final t in texts) 'device:$t'];
    for (var i = 0; i < out.length; i++) {
      onEach?.call(i, out[i]);
    }
    return out;
  }

  @override
  Future<String?> complete(String prompt,
          {required int maxTokens,
          TranslationPriority priority = TranslationPriority.background,
          String? head}) async =>
      null;
  @override
  Future<void> dispose() async {}
}

void main() {
  final settings = GeminiSettings.instance;
  late _Device device;

  CloudTranslator translator(_Server server) {
    final dio = Dio()..httpClientAdapter = server;
    return CloudTranslator(
      client: GeminiClient(dio: dio, settings: settings, sleep: (_) async {}),
      settings: settings,
      device: () async => device,
    );
  }

  setUp(() {
    device = _Device();
    settings.debugSet(
        useGemini: true,
        key: 'test-key',
        deviceFallback: true,
        usage: GeminiUsage(day: quotaDay(DateTime.now())));
  });

  test('a batch in one request, one translation each, counted', () async {
    final server = _Server((p, _) => (200, _ok([for (final t in p) ko(t)])));
    final heard = <int, String>{};
    final out = await translator(server).translateBatch(['あ', 'い', 'う'],
        targetLanguage: 'Korean',
        sourceLanguage: 'Japanese',
        before: const ['前'],
        beforeTranslations: const ['앞'],
        onEach: (i, t) => heard[i] = t);
    expect(out, [ko('あ'), ko('い'), ko('う')]);
    expect(heard.length, 3);
    expect(server.bodies.length, 1);
    final system =
        ((server.bodies.single['systemInstruction'] as Map)['parts'] as List)
            .first['text'] as String;
    expect(system, contains('{"translations"'));
    expect(server.contexts.single, [
      {'text': '前', 'translation': '앞'}
    ]);
    expect(settings.usage.requests, 1);
    expect(settings.usage.paragraphs, 3);
    expect(device.asked, isEmpty);
  });

  test(
      'blocked: the paragraph is found; a filter block goes to the phone, '
      'a policy refusal stays as written', () async {
    final server = _Server((p, _) {
      if (p.contains('禁止')) return (200, _blocked('PROHIBITED_CONTENT'));
      if (p.contains('過激')) {
        return (
          200,
          {
            'candidates': [
              {'finishReason': 'SAFETY'}
            ]
          }
        );
      }
      return (200, _ok([for (final t in p) ko(t)]));
    });
    final out = await translator(server).translateBatch(
        ['一', '禁止', '二', '過激', '三', '四'],
        targetLanguage: 'Korean');
    expect(out, [ko('一'), '禁止', ko('二'), 'device:過激', ko('三'), ko('四')]);
    expect(device.asked, ['過激']);
    expect(settings.usage.blockedProhibited, 1);
    expect(settings.usage.blockedSafety, 1);
    expect(settings.usage.onDevice, 1);
  });

  test(
      "the day's quota: the phone takes over, and later requests skip "
      'Gemini until the reset', () async {
    var calls = 0;
    final server = _Server((p, _) {
      calls++;
      return (
        429,
        {
          'error': {
            'status': 'RESOURCE_EXHAUSTED',
            'message': 'quota',
            'details': [
              {
                '@type': 'type.googleapis.com/google.rpc.QuotaFailure',
                'violations': [
                  {
                    'quotaMetric': 'x/generate_content_free_tier_requests',
                    'quotaId':
                        'GenerateRequestsPerDayPerProjectPerModel-FreeTier',
                    'quotaValue': '20'
                  }
                ]
              }
            ]
          }
        }
      );
    });
    final t = translator(server);
    final out = await t.translateBatch(['a', 'b'], targetLanguage: 'Korean');
    expect(out, ['device:a', 'device:b']);
    expect(settings.usage.exhausted, isTrue);
    expect(settings.usage.dailyLimit, 20);
    expect(settings.usage.freeTier, isTrue);
    await t.translateBatch(['c'], targetLanguage: 'Korean');
    expect(calls, 1);
  });

  test('a per-minute limit: waits as told, then goes on', () async {
    var calls = 0;
    final waits = <Duration>[];
    final server = _Server((p, _) {
      calls++;
      if (calls == 1) {
        return (
          429,
          {
            'error': {
              'status': 'RESOURCE_EXHAUSTED',
              'message': 'rate',
              'details': [
                {
                  '@type': 'type.googleapis.com/google.rpc.RetryInfo',
                  'retryDelay': '7s'
                }
              ]
            }
          }
        );
      }
      return (200, _ok([for (final x in p) ko(x)]));
    });
    final dio = Dio()..httpClientAdapter = server;
    final t = CloudTranslator(
        client: GeminiClient(
            dio: dio, settings: settings, sleep: (d) async => waits.add(d)),
        settings: settings,
        device: () async => device);
    expect(await t.translateBatch(['a'], targetLanguage: 'Korean'), [ko('a')]);
    expect(waits, contains(const Duration(seconds: 7)));
  });

  test('a short answer is asked again in halves, then the phone', () async {
    final server = _Server((p, _) =>
        p.length > 1 ? (200, _ok(['only one'])) : (200, _ok([ko(p.single)])));
    final out = await translator(server)
        .translateBatch(['a', 'b', 'c', 'd'], targetLanguage: 'Korean');
    expect(out, [ko('a'), ko('b'), ko('c'), ko('d')]);
  });

  test('a key that does not work stops the run', () async {
    final server = _Server((p, _) => (
          400,
          {
            'error': {'message': 'API key not valid.'}
          }
        ));
    expect(
        () =>
            translator(server).translateBatch(['a'], targetLanguage: 'Korean'),
        throwsA(isA<GeminiError>()
            .having((e) => e.kind, 'kind', GeminiErrorKind.badKey)));
  });

  test('without the phone fallback, what Gemini cannot do waits', () async {
    settings.debugSet(deviceFallback: false);
    final server = _Server((p, _) => (
          200,
          {
            'candidates': [
              {'finishReason': 'SAFETY'}
            ]
          }
        ));
    final out = await translator(server)
        .translateBatch(['a'], targetLanguage: 'Korean');
    expect(out, ['']);
    expect(device.asked, isEmpty);
  });

  test(
      'a translation failing a check goes back once with its problem, and '
      'the better one is kept', () async {
    final server = _Server((p, _) => (
          200,
          _ok([
            for (final t in p)
              t.startsWith('FIX:') ? '고친 번역' : (t == 'う' ? 'う가 남음' : ko(t))
          ])
        ));
    final out = await translator(server)
        .translateBatch(['あ', 'う'], targetLanguage: 'Korean');
    expect(out, [ko('あ'), '고친 번역']);
    expect(server.refinements.single['source'], 'う');
    expect(server.refinements.single['draft'], 'う가 남음');
    expect((server.refinements.single['problems'] as List).single,
        contains('untranslated'));
    expect(server.bodies.length, 2);
  });

  test(
      'an answer that slipped by one paragraph is not used: asked again '
      'in parts', () async {
    const names = {
      '一つ目の段落': '첫째',
      '二つ目の段落': '둘째',
      '三つ目の段落': '셋째',
      '四つ目の段落': '넷째',
    };
    var calls = 0;
    final server = _Server((p, _) {
      calls++;
      if (p.length == 4) {
        // The context's last line translated again, the rest one late.
        return (
          200,
          _ok([
            '앞 문장을 한 번 더 옮긴 번역입니다',
            '첫째 문단의 번역입니다',
            '둘째 문단의 번역입니다',
            '셋째 문단의 번역입니다'
          ])
        );
      }
      return (200, _ok([for (final t in p) '${names[t]} 문단을 제대로 옮긴 번역']));
    });
    final out = await translator(server).translateBatch(
        ['一つ目の段落', '二つ目の段落', '三つ目の段落', '四つ目の段落'],
        targetLanguage: 'Korean',
        before: const ['前の段落です'],
        beforeTranslations: const ['앞 문장을 옮긴 번역입니다']);
    expect(out, [
      for (final n in names.values) '$n 문단을 제대로 옮긴 번역'
    ]);
    expect(calls, 3);
  });

  test('style: a slip of tense and 그녀 go back, with the story before',
      () async {
    const sources = ['彼は席に着いた。', 'しずくが手を伸ばす。', '彼女は笑った。', '二人は店を出た。'];
    const first = ['그는 자리에 앉았다.', '시즈쿠가 손을 뻗는다.', '그녀는 웃었다.', '두 사람은 가게를 나왔다.'];
    const mended = {
      'しずくが手を伸ばす。': '시즈쿠가 손을 뻗었다.',
      '彼女は笑った。': '시즈쿠는 웃었다.',
    };
    final server = _Server((p, _) => (
          200,
          _ok(p.first.startsWith('FIX:')
              ? [for (final t in p) mended[t.substring(4)]!]
              : first)
        ));
    final out = await translator(server).translateBatch(sources,
        targetLanguage: 'Korean', sourceLanguage: 'Japanese');
    expect(out, [
      '그는 자리에 앉았다.',
      '시즈쿠가 손을 뻗었다.',
      '시즈쿠는 웃었다.',
      '두 사람은 가게를 나왔다.',
    ]);
    // One request, one correction for both.
    expect(server.bodies.length, 2);
    final bySource = {for (final r in server.refinements) r['source']: r};
    expect((bySource['しずくが手を伸ばす。']!['problems'] as List).single,
        contains('End that sentence in the past'));
    expect(bySource['しずくが手を伸ばす。']!.containsKey('before'), isFalse);
    // Who 彼女 is: the Korean of the paragraphs just before.
    expect(bySource['彼女は笑った。']!['before'],
        ['그는 자리에 앉았다.', '시즈쿠가 손을 뻗는다.']);
  });

  test('style: a second answer that is no better is not kept', () async {
    const sources = ['彼は席に着いた。', 'しずくが手を伸ばす。', '二人は店を出た。'];
    const first = ['그는 자리에 앉았다.', '시즈쿠가 손을 뻗는다.', '두 사람은 가게를 나왔다.'];
    final server = _Server((p, _) => (
          200,
          // Still in the present.
          _ok(p.first.startsWith('FIX:') ? ['시즈쿠가 손을 내민다.'] : first)
        ));
    final out = await translator(server).translateBatch(sources,
        targetLanguage: 'Korean', sourceLanguage: 'Japanese');
    expect(out[1], '시즈쿠가 손을 뻗는다.');
  });

  test('style: a stiff paragraph goes back only when the reader asks for it',
      () async {
    const sources = ['彼は席に着いた。', '彼にとってそれは大事なことだった。', '二人は店を出た。'];
    const stiff = '그에게 있어서 그것은 중요하다는 것이라고 생각했다.';
    const first = ['그는 자리에 앉았다.', stiff, '두 사람은 가게를 나왔다.'];
    _Server server() => _Server((p, _) => (
          200,
          _ok(p.first.startsWith('FIX:') ? ['그에게 그것은 소중한 일이었다.'] : first)
        ));
    // As it comes: off.
    final plain = server();
    expect(
        (await translator(plain).translateBatch(sources,
            targetLanguage: 'Korean', sourceLanguage: 'Japanese'))[1],
        stiff);
    expect(plain.bodies.length, 1);

    settings.debugSet(polish: true);
    addTearDown(() => settings.debugSet(polish: false));
    final asked = server();
    final out = await translator(asked).translateBatch(sources,
        targetLanguage: 'Korean', sourceLanguage: 'Japanese');
    expect(out[1], '그에게 그것은 소중한 일이었다.');
    expect(asked.bodies.length, 2);
    expect((asked.refinements.single['problems'] as List).single,
        contains('word for word'));
  });

  test('every request of a book opens alike: all its names, readings apart',
      () async {
    const glossary = BookGlossary(complete: true, entries: [
      GlossaryEntry(source: '純太郎', target: '준타로', gender: GlossaryGender.male),
      GlossaryEntry(source: 'しずく', target: '시즈쿠', gender: GlossaryGender.female),
      GlossaryEntry(source: '上野', target: '우에노', kind: GlossaryKind.place),
    ]);
    final server = _Server((p, _) => (
          200,
          _ok([p.single.contains('純太郎') ? '준타로는 걸었다.' : '흉내를 냈다.'])
        ));
    final t = translator(server);
    await t.translateBatch(['純太郎は歩いた。'],
        targetLanguage: 'Korean',
        sourceLanguage: 'Japanese',
        glossary: glossary,
        readings: const {'真似': 'まね'});
    await t.translateBatch(['真似をした。'],
        targetLanguage: 'Korean',
        sourceLanguage: 'Japanese',
        glossary: glossary,
        readings: const {'真似': 'まね'});
    String system(Map body) =>
        ((body['systemInstruction'] as Map)['parts'] as List).first['text']
            as String;
    String user(Map body) =>
        ((body['contents'] as List).first['parts'] as List).first['text']
            as String;
    // Not only the names of its own paragraphs: the same instructions.
    expect(system(server.bodies[0]), system(server.bodies[1]));
    expect(system(server.bodies[0]), contains('しずく = 시즈쿠 (female)'));
    expect(system(server.bodies[0]), contains('上野 = 우에노 (place)'));
    expect(system(server.bodies[0]), isNot(contains('まね')));
    expect(user(server.bodies[0]), isNot(contains('"readings"')));
    expect(user(server.bodies[1]), contains('"readings":{"真似":"まね"}'));
  });

  group('paragraphs to send back, gathered (a book on its own)', () {
    const a = ['彼は席に着いた。', 'しずくが手を伸ばす。', '二人は店を出た。'];
    const aFirst = ['그는 자리에 앉았다.', '시즈쿠가 손을 뻗는다.', '두 사람은 가게를 나왔다.'];
    const b = ['彼は窓を開けた。', '風が部屋を駆け抜ける。', '彼は窓を閉めた。'];
    const bFirst = ['그는 창문을 열었다.', '바람이 방을 스쳐 지나간다.', '그는 창문을 닫았다.'];
    const mended = {
      'しずくが手を伸ばす。': '시즈쿠가 손을 뻗었다.',
      '風が部屋を駆け抜ける。': '바람이 방을 스쳐 지나갔다.',
    };

    CloudTranslator gathering(_Server server) => CloudTranslator(
          client: GeminiClient(
              dio: Dio()..httpClientAdapter = server,
              settings: settings,
              sleep: (_) async {}),
          settings: settings,
          gatherCorrections: true,
          device: () async => device,
        );

    /// What each paragraph of a request was handed, in order.
    (Map<int, List<String>>, void Function(int, String)) heard() {
      final all = <int, List<String>>{};
      return (all, (i, t) => all.putIfAbsent(i, () => []).add(t));
    }

    test('first answers at once, one request for the corrections of '
        'several, each back where it came from', () async {
      final server = _Server((p, _) => (
            200,
            _ok(p.first.startsWith('FIX:')
                ? [for (final t in p) mended[t.substring(4)]!]
                : p.first == a.first
                    ? aFirst
                    : bFirst)
          ));
      final translator = gathering(server);
      final (heardA, onA) = heard();
      final (heardB, onB) = heard();
      await translator.translateBatch(a,
          targetLanguage: 'Korean', sourceLanguage: 'Japanese', onEach: onA);
      await translator.translateBatch(b,
          targetLanguage: 'Korean', sourceLanguage: 'Japanese', onEach: onB);
      // Two translation requests and nothing more yet; the paragraph to
      // be sent back is with the caller as it first came.
      expect(server.bodies.length, 2);
      expect(heardA[1], ['시즈쿠가 손을 뻗는다.']);
      expect(heardB[1], ['바람이 방을 스쳐 지나간다.']);

      await translator.flushCorrections();
      expect(server.bodies.length, 3);
      expect(server.refinements.map((r) => r['source']),
          ['しずくが手を伸ばす。', '風が部屋を駆け抜ける。']);
      expect(heardA[1], ['시즈쿠가 손을 뻗는다.', '시즈쿠가 손을 뻗었다.']);
      expect(heardB[1], ['바람이 방을 스쳐 지나간다.', '바람이 방을 스쳐 지나갔다.']);
      // Nothing else was touched, and nothing is left to send.
      expect(heardA[0], ['그는 자리에 앉았다.']);
      expect(heardB[2], ['그는 창문을 닫았다.']);
      await translator.flushCorrections();
      expect(server.bodies.length, 3);
    });

    test('corrections that came back in each other\'s place: none is used',
        () async {
      final server = _Server((p, _) => (
            200,
            _ok(p.first.startsWith('FIX:')
                // One place late, the last come round to the first.
                ? [
                    for (var k = 0; k < p.length; k++)
                      mended[p[(k + 1) % p.length].substring(4)]!
                  ]
                : p.first == a.first
                    ? aFirst
                    : bFirst)
          ));
      final translator = gathering(server);
      final (heardA, onA) = heard();
      final (heardB, onB) = heard();
      await translator.translateBatch(a,
          targetLanguage: 'Korean', sourceLanguage: 'Japanese', onEach: onA);
      await translator.translateBatch(b,
          targetLanguage: 'Korean', sourceLanguage: 'Japanese', onEach: onB);
      await translator.flushCorrections();
      expect(server.bodies.length, 3);
      // Each keeps its own first answer; no paragraph has another's text.
      expect(heardA[1], ['시즈쿠가 손을 뻗는다.']);
      expect(heardB[1], ['바람이 방을 스쳐 지나간다.']);
    });

    test('the same correction for two different paragraphs: none is used',
        () async {
      final server = _Server((p, _) => (
            200,
            _ok(p.first.startsWith('FIX:')
                ? [for (final _ in p) '시즈쿠가 손을 뻗었다.']
                : p.first == a.first
                    ? aFirst
                    : bFirst)
          ));
      final translator = gathering(server);
      final (heardA, onA) = heard();
      final (heardB, onB) = heard();
      await translator.translateBatch(a,
          targetLanguage: 'Korean', sourceLanguage: 'Japanese', onEach: onA);
      await translator.translateBatch(b,
          targetLanguage: 'Korean', sourceLanguage: 'Japanese', onEach: onB);
      await translator.flushCorrections();
      expect(heardA[1], ['시즈쿠가 손을 뻗는다.']);
      expect(heardB[1], ['바람이 방을 스쳐 지나간다.']);
    });

    test('a draft with Japanese left in it is not shown: it waits for its '
        'correction', () async {
      const first = ['그는 자리에 앉았다.', 'しずく가 손을 뻗었다.', '두 사람은 가게를 나왔다.'];
      final server = _Server((p, _) => (
            200,
            _ok(p.first.startsWith('FIX:') ? ['시즈쿠가 손을 뻗었다.'] : first)
          ));
      final translator = gathering(server);
      final (all, on) = heard();
      final out = await translator.translateBatch(a,
          targetLanguage: 'Korean', sourceLanguage: 'Japanese', onEach: on);
      expect(all.containsKey(1), isFalse);
      expect(out[1], isEmpty);
      await translator.flushCorrections();
      expect(all[1], ['시즈쿠가 손을 뻗었다.']);
    });

    test('no answer to the corrections: the first answers stand', () async {
      final server = _Server((p, _) => p.first.startsWith('FIX:')
          ? (200, _ok(const ['하나뿐']))
          : (200, _ok(p.first == a.first ? aFirst : bFirst)));
      final translator = gathering(server);
      final (heardA, onA) = heard();
      final (heardB, onB) = heard();
      await translator.translateBatch(a,
          targetLanguage: 'Korean', sourceLanguage: 'Japanese', onEach: onA);
      await translator.translateBatch(b,
          targetLanguage: 'Korean', sourceLanguage: 'Japanese', onEach: onB);
      await translator.flushCorrections();
      expect(heardA[1], ['시즈쿠가 손을 뻗는다.']);
      expect(heardB[1], ['바람이 방을 스쳐 지나간다.']);
    });

    test('one paragraph asked for by itself is corrected at once', () async {
      final server = _Server((p, _) => (
            200,
            _ok(p.first.startsWith('FIX:') ? ['시즈쿠가 손을 뻗었다.'] : ['しずく가 손을 뻗었다.'])
          ));
      final translator = gathering(server);
      expect(
          await translator.translate('しずくが手を伸ばす。',
              targetLanguage: 'Korean', sourceLanguage: 'Japanese'),
          '시즈쿠가 손을 뻗었다.');
      expect(server.bodies.length, 2);
    });
  });

  test('corrections out of place are told from corrections', () {
    const drafts = ['시즈쿠가 손을 뻗는다.', '바람이 방을 스쳐 지나간다.', '그녀는 조용히 웃고 있었다.'];
    // Each its own, a little changed.
    expect(
        misplacedCorrections(drafts,
            const ['시즈쿠가 손을 뻗었다.', '바람이 방을 스쳐 지나갔다.', '시즈쿠는 조용히 웃었다.']),
        isEmpty);
    // One place late.
    expect(
        misplacedCorrections(drafts,
            const ['그녀는 조용히 웃었다.', '시즈쿠가 손을 뻗었다.', '바람이 방을 스쳐 지나갔다.']),
        {0, 1, 2});
    // One paragraph's text twice.
    expect(
        misplacedCorrections(drafts,
            const ['시즈쿠가 손을 뻗었다.', '시즈쿠가 손을 뻗었다.', '시즈쿠는 조용히 웃었다.']),
        containsAll([0, 1]));
    // The story shown before it, given back as the correction.
    expect(
        misplacedCorrections(const ['그녀는 조용히 웃고 있었다.'],
            const ['시즈쿠가 가게 문을 열고 들어왔다.'],
            before: const [
              ['시즈쿠가 가게 문을 열고 들어왔다.']
            ]),
        {0});
    // Two short lines that are alike may well be corrected alike.
    expect(misplacedCorrections(const ['“응.”', '“응.”'], const ['“응.”', '“응.”']),
        isEmpty);
  });
}
