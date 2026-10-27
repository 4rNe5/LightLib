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
}
