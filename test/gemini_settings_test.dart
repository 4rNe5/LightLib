// Today's Gemini use: kept per quota day, limits carried over.

// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/services/translation/gemini/gemini_api.dart';
import 'package:openlib/services/translation/gemini/gemini_settings.dart';

void main() {
  test('a new quota day starts at zero and keeps the limits', () {
    const saved = GeminiUsage(
        day: '2026-10-26',
        requests: 400,
        promptTokens: 9,
        exhausted: true,
        dailyLimit: 500,
        freeTier: true);
    final same = GeminiUsage.fromJson(saved.toJson(), '2026-10-26');
    expect(same.requests, 400);
    expect(same.exhausted, isTrue);
    final next = GeminiUsage.fromJson(saved.toJson(), '2026-10-27');
    expect(next.requests, 0);
    expect(next.exhausted, isFalse);
    expect(next.dailyLimit, 500);
    expect(next.freeTier, isTrue);
    expect(GeminiUsage.fromJson('garbage', '2026-10-27').requests, 0);
  });

  test('safety settings read back, unknown values off', () {
    final s = GeminiSettings.decodeSafety(
        '{"sexual":"onlyHigh","hate":"nonsense"}');
    expect(s[GeminiHarm.sexual], GeminiBlock.onlyHigh);
    expect(s[GeminiHarm.hate], GeminiBlock.off);
    expect(GeminiSettings.decodeSafety(null)[GeminiHarm.dangerous],
        GeminiBlock.off);
  });

  test('a limit error records the tier, the limit and a used-up day', () {
    final settings = GeminiSettings.instance
      ..debugSet(usage: GeminiUsage(day: quotaDay(DateTime.now())));
    settings.recordLimit(const GeminiError(
        GeminiErrorKind.quotaExhausted, 'q',
        quotaId: 'GenerateRequestsPerDayPerProjectPerModel-FreeTier',
        quotaLimit: 500,
        freeTier: true));
    expect(settings.usage.exhausted, isTrue);
    expect(settings.usage.dailyLimit, 500);
    expect(settings.usage.freeTier, isTrue);
  });

  test('a token limit is not taken for a request limit', () {
    final settings = GeminiSettings.instance
      ..debugSet(usage: GeminiUsage(day: quotaDay(DateTime.now())));
    settings.recordLimit(const GeminiError(GeminiErrorKind.rateLimited, 't',
        quotaId: 'GenerateContentInputTokensPerModelPerMinute-FreeTier',
        quotaLimit: 250000,
        freeTier: true));
    expect(settings.usage.minuteLimit, isNull);
    expect(settings.usage.freeTier, isTrue);
  });

  group('each model its own count', () {
    final lite = geminiModelFor('gemini-3.5-flash-lite');
    final flash = geminiModelFor('gemini-3.5-flash');
    final today = quotaDay(DateTime.now());
    const answer = GeminiResult(text: 'x', promptTokens: 1000, outputTokens: 200);

    test('a request counts for the model that answered it; choosing '
        'another model shows that one\'s', () {
      final settings = GeminiSettings.instance
        ..debugSet(model: lite, usageBy: const {});
      for (var i = 0; i < 37; i++) {
        settings.recordRequest(answer, paragraphs: 80);
      }
      expect(settings.usage.requests, 37);
      expect(settings.usageOf(flash).requests, 0);

      // 3.5 Flash now: its own day starts at nothing, with its own limit.
      settings.debugSet(model: flash);
      expect(settings.usage.requests, 0);
      expect(settings.usage.promptTokens, 0);
      settings
        ..recordRequest(answer, paragraphs: 80)
        ..recordRequest(answer, paragraphs: 80);
      expect(settings.usage.requests, 2);
      expect(settings.usage.promptTokens, 2000);
      expect(settings.usage.outputTokens, 400);
      // At its own price.
      expect(settings.model.cost(settings.usage.promptTokens,
          settings.usage.outputTokens), closeTo(0.0066, 1e-9));
      expect(settings.otherModelsToday.keys.single.id, lite.id);
      expect(settings.otherModelsToday.values.single.requests, 37);

      // Back again: what Flash-Lite used is still there.
      settings.debugSet(model: lite);
      expect(settings.usage.requests, 37);
      expect(settings.usage.promptTokens, 37000);
      expect(settings.otherModelsToday.keys.single.id, flash.id);
    });

    test('a request named for another model than the one chosen', () {
      final settings = GeminiSettings.instance
        ..debugSet(model: lite, usageBy: const {});
      settings.recordRequest(answer, model: flash);
      expect(settings.usage.requests, 0);
      expect(settings.usageOf(flash).requests, 1);
    });

    test('one model\'s day used up leaves another\'s to go on', () {
      final settings = GeminiSettings.instance
        ..debugSet(model: flash, usageBy: const {});
      settings.recordLimit(const GeminiError(
          GeminiErrorKind.quotaExhausted, 'q',
          quotaId: 'GenerateRequestsPerDayPerProjectPerModel-FreeTier',
          quotaLimit: 20,
          freeTier: true));
      expect(settings.usage.exhausted, isTrue);
      expect(settings.usage.dailyLimit, 20);
      settings.debugSet(model: lite);
      expect(settings.usage.exhausted, isFalse);
      expect(settings.usage.dailyLimit, isNull);
      // The tier is the key's: known from the other model's limit.
      expect(settings.usage.freeTier, isNull);
      expect(settings.freeTier, isTrue);
    });

    test('saved by model; what an earlier version saved is the chosen '
        'model\'s', () {
      final old = GeminiUsage(day: today, requests: 12, promptTokens: 345)
          .toJson();
      final migrated = GeminiSettings.decodeUsage(old, today, lite);
      expect(migrated.keys, [lite.id]);
      expect(migrated[lite.id]!.requests, 12);

      final saved = {
        'v': 2,
        'models': {
          lite.id: GeminiUsage(day: today, requests: 37).toJson(),
          flash.id: GeminiUsage(
                  day: '2000-01-01', requests: 20, exhausted: true, dailyLimit: 20)
              .toJson(),
        },
      };
      final read = GeminiSettings.decodeUsage(saved, today, lite);
      expect(read[lite.id]!.requests, 37);
      // Another day's: the count starts again, the limit it learned stays.
      expect(read[flash.id]!.requests, 0);
      expect(read[flash.id]!.exhausted, isFalse);
      expect(read[flash.id]!.dailyLimit, 20);
      expect(GeminiSettings.decodeUsage('garbage', today, lite), isEmpty);
      expect(GeminiSettings.decodeUsage(null, today, lite), isEmpty);
    });
  });
}
