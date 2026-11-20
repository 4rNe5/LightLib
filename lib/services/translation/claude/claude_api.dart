// The Claude API as the app uses it: the models offered, a Messages
// request for a translation (the instructions kept read between
// requests, the answer held to a JSON schema), and what a response or an
// error says. No Flutter and no I/O here.

// Dart imports:
import 'dart:convert';

// Project imports:
import 'package:openlib/services/translation/gemini/gemini_api.dart';

/// How a model is asked to answer without thinking first.
enum ClaudeQuiet {
  /// `thinking: {type: disabled}` (at effort `high` or below).
  disabled,

  /// `thinking: {type: between_tools}`: no thinking before the answer.
  betweenTools,

  /// It always thinks as much as the effort has it think.
  never,
}

class ClaudeModel {
  const ClaudeModel({
    required this.id,
    required this.label,
    required this.inputPrice,
    required this.outputPrice,
    required this.cacheReadShare,
    required this.quiet,
  });

  final String id;
  final String label;

  /// US dollars per million tokens (requests of up to 100,000 tokens).
  final double inputPrice;
  final double outputPrice;

  /// What a token read from the cache costs, as a share of [inputPrice].
  final double cacheReadShare;
  final ClaudeQuiet quiet;

  /// What [input] tokens (of them [cached] read from the cache) and
  /// [output] tokens cost, in US dollars.
  double cost(int input, int output, {int cached = 0}) =>
      ((input - cached) * inputPrice +
          cached * inputPrice * cacheReadShare +
          output * outputPrice) /
      1e6;
}

/// The models offered for translation, the one a reader starts with
/// first. Prices: platform.claude.com/docs/en/models/overview.
/// The order is what a comparison on a book found (CLAUDE.md, "Claude"):
/// Sonnet read best, for about one and a half times what Gemini 3.5
/// Flash costs; Haiku read about as well as that Flash for a tenth of
/// it; Opus did not read better than Sonnet for twice Sonnet's price.
const claudeModels = <ClaudeModel>[
  ClaudeModel(
      id: 'claude-sonnet-5-5',
      label: 'Claude Sonnet 5.5',
      inputPrice: 2,
      outputPrice: 10,
      cacheReadShare: 0.05,
      quiet: ClaudeQuiet.betweenTools),
  ClaudeModel(
      id: 'claude-haiku-5-5',
      label: 'Claude Haiku 5.5',
      inputPrice: 0.10,
      outputPrice: 0.50,
      cacheReadShare: 0.10,
      quiet: ClaudeQuiet.disabled),
  ClaudeModel(
      id: 'claude-opus-5-5',
      label: 'Claude Opus 5.5',
      inputPrice: 4,
      outputPrice: 20,
      cacheReadShare: 0.05,
      quiet: ClaudeQuiet.never),
];

ClaudeModel claudeModelFor(String? id) => claudeModels
    .firstWhere((m) => m.id == id, orElse: () => claudeModels.first);

const _unsupported = {
  'minItems',
  'maxItems',
  'minimum',
  'maximum',
  'minLength',
  'maxLength',
  'pattern',
  'format',
};

/// [schema] (as the app writes one for Gemini) in the form Claude's
/// structured output takes: every object closed
/// (`additionalProperties: false`), no size or range constraints.
Object? claudeSchema(Object? schema) {
  if (schema is List) return [for (final v in schema) claudeSchema(v)];
  if (schema is! Map) return schema;
  final out = <String, Object?>{
    for (final e in schema.entries)
      if (!_unsupported.contains(e.key)) '${e.key}': claudeSchema(e.value),
  };
  if (out['type'] == 'object') out['additionalProperties'] = false;
  return out;
}

/// The effort a thinking choice asks for: least for speed, the most
/// that is worth its tokens for quality.
String claudeEffort(GeminiThinking mode) => switch (mode) {
      GeminiThinking.speed => 'low',
      GeminiThinking.balanced => 'medium',
      GeminiThinking.quality => 'high',
    };

/// A Messages request body. The instructions are marked to be kept read
/// (`cache_control`): every request of a book opens with the same ones.
Map<String, Object?> claudeRequest({
  required String system,
  required String user,
  required ClaudeModel model,
  Map<String, Object?>? schema,
  GeminiThinking thinking = GeminiThinking.speed,
  int? maxOutputTokens,
}) {
  final quiet = thinking == GeminiThinking.speed;
  return {
    'model': model.id,
    // Thinking counts toward the limit: room for it on top of the answer.
    'max_tokens': ((maxOutputTokens ?? 4096) +
            (quiet && model.quiet != ClaudeQuiet.never
                ? 0
                : GeminiModel.thinkingRoom(thinking)))
        .clamp(256, 128000),
    'system': [
      {
        'type': 'text',
        'text': system,
        'cache_control': {'type': 'ephemeral'},
      },
    ],
    'messages': [
      {'role': 'user', 'content': user},
    ],
    'output_config': {
      'effort': claudeEffort(thinking),
      if (schema != null)
        'format': {'type': 'json_schema', 'schema': claudeSchema(schema)},
    },
    if (quiet && model.quiet == ClaudeQuiet.disabled)
      'thinking': {'type': 'disabled'},
    if (quiet && model.quiet == ClaudeQuiet.betweenTools)
      'thinking': {'type': 'between_tools'},
  };
}

/// What a 200 response says. A refusal (`stop_reason: refusal`) is the
/// API declining under its own policy: [GeminiBlockKind.prohibited], as
/// with Gemini, and the paragraph is kept as written.
GeminiResult claudeResult(Map<String, Object?> json) {
  final content = json['content'];
  final text = StringBuffer();
  if (content is List) {
    for (final block in content) {
      if (block is Map && block['type'] == 'text') text.write(block['text']);
    }
  }
  final usage = json['usage'];
  int n(String k) =>
      usage is Map && usage[k] is num ? (usage[k] as num).toInt() : 0;
  final details = usage is Map ? usage['output_tokens_details'] : null;
  final thought = details is Map && details['thinking_tokens'] is num
      ? (details['thinking_tokens'] as num).toInt()
      : 0;
  final stop = json['stop_reason']?.toString();
  return GeminiResult(
    text: text.toString(),
    finishReason: switch (stop) {
      'end_turn' || 'stop_sequence' => 'STOP',
      'max_tokens' => 'MAX_TOKENS',
      _ => stop,
    },
    block: stop == 'refusal' ? GeminiBlockKind.prohibited : null,
    // Read from the cache or written to it, a token of the prompt still.
    promptTokens: n('input_tokens') +
        n('cache_read_input_tokens') +
        n('cache_creation_input_tokens'),
    outputTokens: (n('output_tokens') - thought).clamp(0, 1 << 31),
    thoughtTokens: thought,
  );
}

/// The tokens of a response read from the cache (billed at a fraction).
int claudeCachedTokens(Map<String, Object?> json) {
  final usage = json['usage'];
  return usage is Map && usage['cache_read_input_tokens'] is num
      ? (usage['cache_read_input_tokens'] as num).toInt()
      : 0;
}

/// What an error response says ([retryAfter]: its `retry-after` header,
/// in seconds). A key that does not work or may not use the workspace is
/// [GeminiErrorKind.badKey]; no credit left is
/// [GeminiErrorKind.quotaExhausted] (nothing more goes until the reader
/// adds some).
GeminiError claudeError(int status, Object? body, {String? retryAfter}) {
  Object? json = body;
  if (json is String) {
    try {
      json = jsonDecode(json);
    } catch (_) {
      json = null;
    }
  }
  final error =
      json is Map && json['error'] is Map ? json['error'] as Map : null;
  final type = error?['type']?.toString() ?? '';
  final message = error?['message']?.toString() ?? 'HTTP $status';
  final seconds = double.tryParse(retryAfter ?? '');
  final GeminiErrorKind kind;
  if (message.toLowerCase().contains('credit balance') ||
      type == 'billing_error') {
    kind = GeminiErrorKind.quotaExhausted;
  } else if (status == 401 ||
      status == 403 ||
      type == 'authentication_error' ||
      type == 'permission_error' ||
      message.contains('anthropic-workspace-id') ||
      message.startsWith('Workspace ')) {
    kind = GeminiErrorKind.badKey;
  } else if (status == 429 || type == 'rate_limit_error') {
    kind = GeminiErrorKind.rateLimited;
  } else if (status >= 500 ||
      type == 'overloaded_error' ||
      type == 'api_error') {
    kind = GeminiErrorKind.server;
  } else {
    kind = GeminiErrorKind.badRequest;
  }
  return GeminiError(kind, message,
      status: status,
      retryAfter: seconds == null
          ? null
          : Duration(milliseconds: (seconds * 1000).round()));
}
