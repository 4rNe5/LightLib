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

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    final body = options.data as Map;
    bodies.add(body);
    final user = ((body['contents'] as List).first['parts'] as List)
        .first['text'] as String;
    final start = user.lastIndexOf('\n[');
    final list = start < 0
        ? <String>[]
        : (jsonDecode(user.substring(start + 1)) as List).cast<String>();
    final (status, data) = answer(list, body);
    return ResponseBody.fromString(jsonEncode(data), status, headers: {
      'content-type': ['application/json']
    });
  }

  @override
  void close({bool force = false}) {}
}

Map _ok(List<String> out) => {
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': jsonEncode({'translations': out})}
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
          TranslationPriority priority = TranslationPriority.background}) async =>
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
    final server = _Server((p, _) => (200, _ok([for (final t in p) 'ko:$t'])));
    final heard = <int, String>{};
    final out = await translator(server).translateBatch(['あ', 'い', 'う'],
        targetLanguage: 'Korean',
        sourceLanguage: 'Japanese',
        before: const ['前'],
        beforeTranslations: const ['앞'],
        onEach: (i, t) => heard[i] = t);
    expect(out, ['ko:あ', 'ko:い', 'ko:う']);
    expect(heard.length, 3);
    expect(server.bodies.length, 1);
    final system = ((server.bodies.single['systemInstruction'] as Map)['parts']
        as List).first['text'] as String;
    expect(system, contains('{"translations"'));
    final user = ((server.bodies.single['contents'] as List).first['parts']
        as List).first['text'] as String;
    expect(user, contains('前\n→ 앞'));
    expect(settings.usage.requests, 1);
    expect(settings.usage.paragraphs, 3);
    expect(device.asked, isEmpty);
  });

  test('blocked: the paragraph is found; a filter block goes to the phone, '
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
      return (200, _ok([for (final t in p) 'ko:$t']));
    });
    final out = await translator(server).translateBatch(
        ['一', '禁止', '二', '過激', '三', '四'],
        targetLanguage: 'Korean');
    expect(out, ['ko:一', '禁止', 'ko:二', 'device:過激', 'ko:三', 'ko:四']);
    expect(device.asked, ['過激']);
    expect(settings.usage.blockedProhibited, 1);
    expect(settings.usage.blockedSafety, 1);
    expect(settings.usage.onDevice, 1);
  });

  test("the day's quota: the phone takes over, and later requests skip "
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
      return (200, _ok([for (final x in p) 'ko:$x']));
    });
    final dio = Dio()..httpClientAdapter = server;
    final t = CloudTranslator(
        client: GeminiClient(
            dio: dio, settings: settings, sleep: (d) async => waits.add(d)),
        settings: settings,
        device: () async => device);
    expect(await t.translateBatch(['a'], targetLanguage: 'Korean'), ['ko:a']);
    expect(waits, contains(const Duration(seconds: 7)));
  });

  test('a short answer is asked again in halves, then the phone', () async {
    final server = _Server((p, _) => p.length > 1
        ? (200, _ok(['only one']))
        : (200, _ok(['ko:${p.single}'])));
    final out = await translator(server)
        .translateBatch(['a', 'b', 'c', 'd'], targetLanguage: 'Korean');
    expect(out, ['ko:a', 'ko:b', 'ko:c', 'ko:d']);
  });

  test('a key that does not work stops the run', () async {
    final server = _Server((p, _) => (
          400,
          {
            'error': {'message': 'API key not valid.'}
          }
        ));
    expect(
        () => translator(server).translateBatch(['a'], targetLanguage: 'Korean'),
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
    final out =
        await translator(server).translateBatch(['a'], targetLanguage: 'Korean');
    expect(out, ['']);
    expect(device.asked, isEmpty);
  });
}
