// Gemini over REST: the request a translation sends, what comes back
// (text, blocks, usage), errors such as a used-up quota, and the quota day.

// Dart imports:
import 'dart:convert';

// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/services/translation/gemini/gemini_api.dart';

void main() {
  test('a request: instructions, text, filters, thinking and schema', () {
    final body = geminiRequest(
      system: 'SYS',
      user: 'USER',
      model: geminiModelFor('gemini-3.5-flash-lite'),
      safety: {GeminiHarm.sexual: GeminiBlock.onlyHigh},
      schema: translationSchema(3),
    );
    expect((body['systemInstruction'] as Map)['parts'], [
      {'text': 'SYS'}
    ]);
    final contents = body['contents'] as List;
    expect((contents.single as Map)['role'], 'user');
    final safety = body['safetySettings'] as List;
    expect(safety.length, 4);
    expect(
        safety.firstWhere((s) =>
            s['category'] == 'HARM_CATEGORY_SEXUALLY_EXPLICIT')['threshold'],
        'BLOCK_ONLY_HIGH');
    // Unset categories are off.
    expect(
        safety.firstWhere(
            (s) => s['category'] == 'HARM_CATEGORY_HARASSMENT')['threshold'],
        'OFF');
    final config = body['generationConfig'] as Map;
    expect(config['thinkingConfig'], {'thinkingLevel': 'minimal'});
    final format = (config['responseFormat'] as Map)['text'] as Map;
    expect(format['mimeType'], 'APPLICATION_JSON');
    final items = ((format['schema'] as Map)['properties']
        as Map)['translations'] as Map;
    expect(items['minItems'], 3);
    expect(items['maxItems'], 3);

    // The older field names, and a model without "minimal".
    final legacy = geminiRequest(
        system: 's',
        user: 'u',
        model: geminiModelFor('gemini-3.8-flash'),
        safety: const {},
        schema: translationSchema(1),
        schemaStyle: GeminiSchemaStyle.legacy);
    final c = legacy['generationConfig'] as Map;
    expect(c['responseMimeType'], 'application/json');
    expect(c['responseJsonSchema'], isNotNull);
    expect(c['thinkingConfig'], {'thinkingLevel': 'low'});
    // Body is plain JSON.
    expect(() => jsonEncode(body), returnsNormally);
  });

  test('an answer: text without thoughts, usage, and blocks', () {
    final ok = GeminiResult.fromJson({
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': 'thinking...', 'thought': true},
              {'text': '{"translations":["가","나"]}'},
            ]
          },
          'finishReason': 'STOP',
        }
      ],
      'usageMetadata': {
        'promptTokenCount': 1200,
        'candidatesTokenCount': 300,
        'thoughtsTokenCount': 40,
      },
    });
    expect(ok.block, isNull);
    expect(ok.text, '{"translations":["가","나"]}');
    expect(ok.billedOutput, 340);
    expect(parseTranslations(ok.text, 2), ['가', '나']);

    final prompt = GeminiResult.fromJson({
      'promptFeedback': {'blockReason': 'PROHIBITED_CONTENT'}
    });
    expect(prompt.block, GeminiBlockKind.prohibited);
    final safety = GeminiResult.fromJson({
      'candidates': [
        {'finishReason': 'SAFETY'}
      ]
    });
    expect(safety.block, GeminiBlockKind.safety);
    expect(GeminiResult.fromJson({'candidates': []}).block,
        GeminiBlockKind.other);
    expect(
        GeminiResult.fromJson({
          'candidates': [
            {'finishReason': 'RECITATION'}
          ]
        }).block,
        GeminiBlockKind.other);
  });

  test('translations: exactly the count, fenced or bare', () {
    expect(parseTranslations('```json\n{"translations":["a"]}\n```', 1), ['a']);
    expect(parseTranslations('["a","b"]', 2), ['a', 'b']);
    expect(parseTranslations('{"translations":["a"]}', 2), isNull);
    expect(parseTranslations('not json', 1), isNull);
    expect(parseTranslations('{"translations":[1]}', 1), isNull);
  });

  test('errors: the day used up on the free tier, a minute, a bad key', () {
    final day = GeminiError.fromResponse(429, {
      'error': {
        'code': 429,
        'status': 'RESOURCE_EXHAUSTED',
        'message': 'You exceeded your current quota',
        'details': [
          {
            '@type': 'type.googleapis.com/google.rpc.QuotaFailure',
            'violations': [
              {
                'quotaMetric':
                    'generativelanguage.googleapis.com/generate_content_free_tier_requests',
                'quotaId': 'GenerateRequestsPerMinutePerProjectPerModel-FreeTier',
                'quotaValue': '15',
              },
              {
                'quotaMetric':
                    'generativelanguage.googleapis.com/generate_content_free_tier_requests',
                'quotaId': 'GenerateRequestsPerDayPerProjectPerModel-FreeTier',
                'quotaValue': '500',
              }
            ]
          },
          {
            '@type': 'type.googleapis.com/google.rpc.RetryInfo',
            'retryDelay': '35.5s'
          }
        ]
      }
    });
    expect(day.kind, GeminiErrorKind.quotaExhausted);
    expect(day.quotaLimit, 500);
    expect(day.freeTier, isTrue);
    expect(day.perDay, isTrue);
    expect(day.retryAfter, const Duration(milliseconds: 35500));

    final minute = GeminiError.fromResponse(
        429,
        jsonEncode({
          'error': {
            'status': 'RESOURCE_EXHAUSTED',
            'message': 'slow down',
            'details': [
              {
                '@type': 'type.googleapis.com/google.rpc.QuotaFailure',
                'violations': [
                  {
                    'quotaMetric': 'generativelanguage.googleapis.com/x',
                    'quotaId': 'GenerateRequestsPerMinutePerProjectPerModel',
                    'quotaValue': '2000',
                  }
                ]
              },
              {
                '@type': 'type.googleapis.com/google.rpc.RetryInfo',
                'retryDelay': '6s'
              }
            ]
          }
        }));
    expect(minute.kind, GeminiErrorKind.rateLimited);
    expect(minute.perMinute, isTrue);
    expect(minute.freeTier, isFalse);
    expect(minute.retryAfter, const Duration(seconds: 6));

    expect(
        GeminiError.fromResponse(400, {
          'error': {'message': 'API key not valid. Please pass a valid API key.'}
        }).kind,
        GeminiErrorKind.badKey);
    expect(GeminiError.fromResponse(503, null).kind, GeminiErrorKind.server);
    expect(
        GeminiError.fromResponse(400, {
          'error': {'message': 'Unknown name "responseFormat"'}
        }).kind,
        GeminiErrorKind.badRequest);
  });

  test('the quota day runs on US Pacific time, with daylight saving', () {
    // 2026-10-27 15:00 UTC = 08:00 PDT (UTC-7).
    expect(quotaDay(DateTime.utc(2026, 10, 27, 15)), '2026-10-27');
    // 2026-10-27 06:00 UTC = 23:00 PDT on the 26th.
    expect(quotaDay(DateTime.utc(2026, 10, 27, 6)), '2026-10-26');
    // After the first Sunday of November (Nov 1, 2026): PST, UTC-8.
    expect(pacificTime(DateTime.utc(2026, 11, 2, 12)).hour, 4);
    // Before the second Sunday of March (Mar 8, 2026): PST.
    expect(pacificTime(DateTime.utc(2026, 3, 1, 12)).hour, 4);
    expect(pacificTime(DateTime.utc(2026, 3, 9, 12)).hour, 5);
    // The day ends at 07:00 UTC in summer time (midnight PDT).
    expect(quotaResetAt(DateTime.utc(2026, 10, 27, 15)).toUtc(),
        DateTime.utc(2026, 10, 28, 7));
    expect(quotaResetAt(DateTime.utc(2026, 12, 1, 12)).toUtc(),
        DateTime.utc(2026, 12, 2, 8));
  });

  test('thinking: least for speed, more for balance, most for quality, '
      'with room for it in the output', () {
    final lite = geminiModelFor('gemini-3.5-flash-lite');
    final flash = geminiModelFor('gemini-3.8-flash');
    Map config(GeminiModel m, GeminiThinking t) => geminiRequest(
            system: 's',
            user: 'u',
            model: m,
            safety: const {},
            thinkingMode: t,
            maxOutputTokens: 2000)['generationConfig'] as Map;
    expect(config(lite, GeminiThinking.speed)['thinkingConfig'],
        {'thinkingLevel': 'minimal'});
    expect(config(lite, GeminiThinking.balanced)['thinkingConfig'],
        {'thinkingLevel': 'low'});
    expect(config(lite, GeminiThinking.quality)['thinkingConfig'],
        {'thinkingLevel': 'high'});
    expect(config(flash, GeminiThinking.speed)['thinkingConfig'],
        {'thinkingLevel': 'low'});
    expect(config(flash, GeminiThinking.quality)['thinkingConfig'],
        {'thinkingLevel': 'high'});
    expect(config(lite, GeminiThinking.speed)['maxOutputTokens'], 2000);
    expect(config(lite, GeminiThinking.balanced)['maxOutputTokens'], 9168);
    expect(config(lite, GeminiThinking.quality)['maxOutputTokens'], 25552);
    expect(GeminiThinking.parse('quality'), GeminiThinking.quality);
    expect(GeminiThinking.parse(null), GeminiThinking.speed);
  });

  test('cost at paid prices', () {
    final lite = geminiModelFor('gemini-3.5-flash-lite');
    expect(lite.cost(1000000, 1000000), closeTo(2.80, 1e-9));
    expect(geminiModelFor('nope').id, geminiModels.first.id);
  });
}
