// Sending requests to the Claude API (Messages): waiting as long as the
// API says when it asks to, retried when the service fails or is
// overloaded, and counted in today's use. The counterpart of
// `gemini_client.dart`.

// Dart imports:
import 'dart:async';
import 'dart:math' as math;

// Package imports:
import 'package:dio/dio.dart';

// Project imports:
import 'package:openlib/services/logger.dart';
import 'package:openlib/services/translation/claude/claude_api.dart';
import 'package:openlib/services/translation/claude/claude_settings.dart';
import 'package:openlib/services/translation/cloud_engine.dart';
import 'package:openlib/services/translation/gemini/gemini_api.dart';

class ClaudeClient implements CloudClient {
  ClaudeClient({
    Dio? dio,
    ClaudeSettings? settings,
    Future<void> Function(Duration)? sleep,
  })  : _dio = dio ?? Dio(),
        _settings = settings ?? ClaudeSettings.instance,
        _sleep = sleep ?? Future<void>.delayed;

  static final ClaudeClient shared = ClaudeClient();

  static const _url = 'https://api.anthropic.com/v1/messages';
  static const _version = '2023-06-01';

  final Dio _dio;
  final ClaudeSettings _settings;
  final Future<void> Function(Duration) _sleep;
  final AppLogger _logger = AppLogger();

  /// [model], [apiKey] and [workspace] default to the reader's choices.
  @override
  Future<GeminiResult> generate({
    required String system,
    required String user,
    Map<String, Object?>? schema,
    int? maxOutputTokens,
    int paragraphs = 0,
    ClaudeModel? model,
    String? apiKey,
    String? workspace,
  }) async {
    final m = model ?? _settings.model;
    final key = apiKey ?? _settings.apiKey;
    final space = workspace ?? _settings.workspace;
    if (key.isEmpty) {
      throw const GeminiError(GeminiErrorKind.badKey, 'No API key');
    }
    final body = claudeRequest(
      system: system,
      user: user,
      model: m,
      schema: schema,
      thinking: _settings.thinking,
      maxOutputTokens: maxOutputTokens,
    );
    var attempt = 0;
    while (true) {
      attempt++;
      final started = DateTime.now();
      GeminiError error;
      try {
        // (Outcomes are logged below, never the key or the text.)
        final response = await _dio.post<Object?>(
          _url,
          data: body,
          options: Options(
            headers: {
              'x-api-key': key,
              'anthropic-version': _version,
              if (space.isNotEmpty) 'anthropic-workspace-id': space,
            },
            contentType: 'application/json',
            responseType: ResponseType.json,
            sendTimeout: const Duration(seconds: 60),
            receiveTimeout: const Duration(minutes: 6),
            validateStatus: (_) => true,
          ),
        );
        final status = response.statusCode ?? 0;
        if (status == 200 && response.data is Map) {
          final json = Map<String, Object?>.from(response.data as Map);
          final result = claudeResult(json);
          final cached = claudeCachedTokens(json);
          _settings.recordRequest(result,
              paragraphs: paragraphs, model: m, cached: cached);
          _logger.info('Claude request', tag: 'Claude', metadata: {
            'model': m.id,
            'paragraphs': paragraphs,
            'ms': DateTime.now().difference(started).inMilliseconds,
            'promptTokens': result.promptTokens,
            'cachedTokens': cached,
            'outputTokens': result.outputTokens,
            'thoughtTokens': result.thoughtTokens,
            if (result.block != null) 'block': result.block!.name,
            if (result.finishReason != null && result.finishReason != 'STOP')
              'finish': result.finishReason,
          });
          return result;
        }
        error = claudeError(status, response.data,
            retryAfter: response.headers.value('retry-after'));
      } on DioException catch (e) {
        error = GeminiError(GeminiErrorKind.network, e.message ?? '$e');
      }

      switch (error.kind) {
        case GeminiErrorKind.quotaExhausted:
          _settings.recordLimit(error, model: m);
          _logger.warning('Claude credit used up', tag: 'Claude');
          throw error;
        case GeminiErrorKind.rateLimited:
          if (attempt > 6) throw error;
          final wait =
              error.retryAfter ?? Duration(seconds: math.min(60, 5 * attempt));
          _logger.info('Claude asked to wait',
              tag: 'Claude', metadata: {'ms': wait.inMilliseconds});
          await _sleep(wait > const Duration(minutes: 2)
              ? const Duration(minutes: 2)
              : wait);
        case GeminiErrorKind.server || GeminiErrorKind.network:
          if (attempt > 4) throw error;
          await _sleep(Duration(seconds: 2 << attempt));
        case GeminiErrorKind.badRequest || GeminiErrorKind.badKey:
          _logger.warning('Claude request refused',
              tag: 'Claude',
              metadata: {'status': error.status, 'kind': error.kind.name});
          throw error;
      }
    }
  }

  /// One small request, to see whether [apiKey] works ([workspace]: for
  /// a key that is not tied to one).
  Future<GeminiResult> test(
          {required String apiKey, String? workspace, ClaudeModel? model}) =>
      generate(
        system: 'Answer with one word.',
        user: 'Say OK.',
        maxOutputTokens: 16,
        model: model,
        apiKey: apiKey,
        workspace: workspace,
      );
}
