// Sending requests to the Gemini API: paced under the per-minute limit,
// waiting as long as the API says when it asks to, retried when the
// service fails, and counted in today's use.

// Dart imports:
import 'dart:async';
import 'dart:math' as math;

// Package imports:
import 'package:dio/dio.dart';

// Project imports:
import 'package:openlib/services/logger.dart';
import 'package:openlib/services/translation/gemini/gemini_api.dart';
import 'package:openlib/services/translation/gemini/gemini_settings.dart';

class GeminiClient {
  GeminiClient({
    Dio? dio,
    GeminiSettings? settings,
    Future<void> Function(Duration)? sleep,
  })  : _dio = dio ?? Dio(),
        _settings = settings ?? GeminiSettings.instance,
        _sleep = sleep ?? Future<void>.delayed;

  /// One client for the app, so every request counts toward one pace.
  static final GeminiClient shared = GeminiClient();

  static const _base = 'https://generativelanguage.googleapis.com/v1beta';

  final Dio _dio;
  final GeminiSettings _settings;
  final Future<void> Function(Duration) _sleep;
  final AppLogger _logger = AppLogger();

  /// Request starts in the last minute, for pacing under the limit.
  final List<DateTime> _starts = [];

  /// How the server names structured output, once learned.
  static GeminiSchemaStyle schemaStyle = GeminiSchemaStyle.responseFormat;

  /// Models that refused a thinking setting (sent without one after).
  static final Set<String> _noThinking = {};

  /// Requests a minute to stay under: the limit the API named, else the
  /// free tier's for [model] (a paid key goes faster once one is seen).
  int _perMinute(GeminiModel model) {
    final u = _settings.usage;
    if (u.minuteLimit != null && u.minuteLimit! > 0) return u.minuteLimit!;
    return u.freeTier == false ? 60 : model.freeRpm;
  }

  Future<void> _pace(GeminiModel model) async {
    while (true) {
      final now = DateTime.now();
      _starts
          .removeWhere((t) => now.difference(t) >= const Duration(minutes: 1));
      if (_starts.length < _perMinute(model)) {
        _starts.add(now);
        return;
      }
      final wait = const Duration(minutes: 1) - now.difference(_starts.first);
      await _sleep(wait + const Duration(milliseconds: 50));
    }
  }

  /// One generateContent request. Throws [GeminiError] when it cannot be
  /// answered (the day's quota, a bad key, a refused request, no
  /// connection after retries).
  Future<GeminiResult> generate({
    required String system,
    required String user,
    Map<String, Object?>? schema,
    int? maxOutputTokens,
    int paragraphs = 0,
    GeminiModel? model,
    String? apiKey,
  }) async {
    final m = model ?? _settings.model;
    final key = apiKey ?? _settings.apiKey;
    if (key.isEmpty) {
      throw const GeminiError(GeminiErrorKind.badKey, 'No API key');
    }
    var attempt = 0;
    var adjusted = 0;
    while (true) {
      attempt++;
      await _pace(m);
      final body = geminiRequest(
        system: system,
        user: user,
        model: m,
        safety: _settings.safety,
        schema: schema,
        schemaStyle: schemaStyle,
        thinking: !_noThinking.contains(m.id),
        maxOutputTokens: maxOutputTokens,
      );
      GeminiError error;
      try {
        final response = await _dio.post<Object?>(
          '$_base/models/${m.id}:generateContent',
          data: body,
          options: Options(
            headers: {'x-goog-api-key': key},
            contentType: 'application/json',
            responseType: ResponseType.json,
            sendTimeout: const Duration(seconds: 60),
            receiveTimeout: const Duration(minutes: 4),
            validateStatus: (_) => true,
          ),
        );
        final status = response.statusCode ?? 0;
        if (status == 200 && response.data is Map) {
          final result = GeminiResult.fromJson(
              Map<String, Object?>.from(response.data as Map));
          _settings.recordRequest(result, paragraphs: paragraphs);
          return result;
        }
        error = GeminiError.fromResponse(status, response.data);
      } on DioException catch (e) {
        error = GeminiError(GeminiErrorKind.network, e.message ?? '$e');
      }

      switch (error.kind) {
        case GeminiErrorKind.quotaExhausted:
          _settings.recordLimit(error);
          _logger.warning('Gemini quota used up for today',
              tag: 'Gemini',
              metadata: {'quota': error.quotaId, 'limit': error.quotaLimit});
          throw error;
        case GeminiErrorKind.rateLimited:
          _settings.recordLimit(error);
          if (attempt > 6) throw error;
          final wait =
              error.retryAfter ?? Duration(seconds: math.min(60, 5 * attempt));
          _logger.info('Gemini asked to wait',
              tag: 'Gemini', metadata: {'ms': wait.inMilliseconds});
          await _sleep(wait > const Duration(minutes: 2)
              ? const Duration(minutes: 2)
              : wait);
        case GeminiErrorKind.server || GeminiErrorKind.network:
          if (attempt > 4) throw error;
          await _sleep(Duration(seconds: 2 << attempt));
        case GeminiErrorKind.badRequest:
          // A field this server version does not know: send it the other
          // way once.
          final msg = error.message.toLowerCase();
          if (adjusted < 2 &&
              schema != null &&
              (msg.contains('responseformat') ||
                  msg.contains('response_format') ||
                  msg.contains('responsejsonschema') ||
                  msg.contains('response_json_schema'))) {
            adjusted++;
            schemaStyle = schemaStyle == GeminiSchemaStyle.responseFormat
                ? GeminiSchemaStyle.legacy
                : GeminiSchemaStyle.responseFormat;
            attempt--;
            continue;
          }
          if (adjusted < 2 &&
              msg.contains('thinking') &&
              !_noThinking.contains(m.id)) {
            adjusted++;
            _noThinking.add(m.id);
            attempt--;
            continue;
          }
          throw error;
        case GeminiErrorKind.badKey:
          throw error;
      }
    }
  }

  /// A small request that shows whether [apiKey] works with [model].
  Future<GeminiResult> test({required String apiKey, GeminiModel? model}) =>
      generate(
        system: 'Answer with one word.',
        user: 'Say OK.',
        maxOutputTokens: 16,
        model: model,
        apiKey: apiKey,
      );
}
