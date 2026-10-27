// Google's Gemini API (generateContent over REST): the models the app
// offers, the request a translation sends, and what comes back - text,
// a block, or an error such as a used-up quota.

// Dart imports:
import 'dart:convert';

/// A Gemini model the app offers, with its paid price per million tokens
/// (input, output including thinking) and its free-tier limits as last
/// measured; the real ones are read from the API's answers.
class GeminiModel {
  const GeminiModel({
    required this.id,
    required this.label,
    required this.inputPrice,
    required this.outputPrice,
    required this.freeRpm,
    required this.freeRpd,
    this.thinkingLevels = const ['minimal', 'low', 'high'],
  });

  final String id;
  final String label;

  /// US dollars per million tokens.
  final double inputPrice;
  final double outputPrice;

  /// Free tier: requests per minute and per day (indicative).
  final int freeRpm;
  final int freeRpd;

  /// The thinking levels for speed first, balance and quality first
  /// (thinking tokens are billed as output and take time).
  final List<String> thinkingLevels;

  String thinkingLevel(GeminiThinking mode) => thinkingLevels[mode.index];

  /// Output room on top of the answer for [mode]'s thinking (it counts
  /// toward the output limit, and a cut-off answer is lost).
  static int thinkingRoom(GeminiThinking mode) => switch (mode) {
        GeminiThinking.speed => 1024,
        GeminiThinking.balanced => 8192,
        GeminiThinking.quality => 24576,
      };

  /// What [input] and [output] tokens cost, in US dollars.
  double cost(int input, int output) =>
      (input * inputPrice + output * outputPrice) / 1e6;
}

const geminiModels = <GeminiModel>[
  GeminiModel(
      id: 'gemini-3.5-flash-lite',
      label: 'Gemini 3.5 Flash-Lite',
      inputPrice: 0.30,
      outputPrice: 2.50,
      freeRpm: 15,
      freeRpd: 500),
  GeminiModel(
      id: 'gemini-3.1-flash-lite',
      label: 'Gemini 3.1 Flash-Lite',
      inputPrice: 0.25,
      outputPrice: 1.50,
      freeRpm: 15,
      freeRpd: 500),
  GeminiModel(
      id: 'gemini-3-flash-preview',
      label: 'Gemini 3 Flash',
      inputPrice: 0.50,
      outputPrice: 3.00,
      freeRpm: 5,
      freeRpd: 20),
  GeminiModel(
      id: 'gemini-3.8-flash',
      label: 'Gemini 3.8 Flash',
      inputPrice: 0.75,
      outputPrice: 3.75,
      freeRpm: 5,
      freeRpd: 20,
      // 3.8 Flash refuses "minimal".
      thinkingLevels: ['low', 'medium', 'high']),
];

GeminiModel geminiModelFor(String? id) => geminiModels
    .firstWhere((m) => m.id == id, orElse: () => geminiModels.first);

/// How much the model thinks before it answers: least for speed, most
/// for quality.
enum GeminiThinking {
  speed,
  balanced,
  quality;

  static GeminiThinking parse(Object? name) => GeminiThinking.values
      .firstWhere((t) => t.name == name, orElse: () => GeminiThinking.speed);
}

/// The categories the API lets a caller set a threshold for.
enum GeminiHarm {
  harassment('HARM_CATEGORY_HARASSMENT'),
  hate('HARM_CATEGORY_HATE_SPEECH'),
  sexual('HARM_CATEGORY_SEXUALLY_EXPLICIT'),
  dangerous('HARM_CATEGORY_DANGEROUS_CONTENT');

  const GeminiHarm(this.apiName);
  final String apiName;
}

/// How much of a category the API blocks. Protections the API applies
/// whatever is set (such as child safety) are not among these.
enum GeminiBlock {
  off('OFF'),
  onlyHigh('BLOCK_ONLY_HIGH'),
  mediumAndAbove('BLOCK_MEDIUM_AND_ABOVE'),
  lowAndAbove('BLOCK_LOW_AND_ABOVE');

  const GeminiBlock(this.apiName);
  final String apiName;

  static GeminiBlock parse(Object? name) => GeminiBlock.values
      .firstWhere((b) => b.name == name, orElse: () => GeminiBlock.off);
}

/// The schema of a translation answer: exactly [count] strings.
Map<String, Object?> translationSchema(int count) => {
      'type': 'object',
      'properties': {
        'translations': {
          'type': 'array',
          'items': {'type': 'string'},
          'minItems': count,
          'maxItems': count,
        },
      },
      'required': ['translations'],
    };

/// The two ways the REST API has named structured output: the current
/// `responseFormat` and the older `responseMimeType`/`responseJsonSchema`.
enum GeminiSchemaStyle { responseFormat, legacy }

/// A generateContent request body.
Map<String, Object?> geminiRequest({
  required String system,
  required String user,
  required GeminiModel model,
  required Map<GeminiHarm, GeminiBlock> safety,
  Map<String, Object?>? schema,
  GeminiSchemaStyle schemaStyle = GeminiSchemaStyle.responseFormat,
  bool thinking = true,
  GeminiThinking thinkingMode = GeminiThinking.speed,
  int? maxOutputTokens,
}) {
  final config = <String, Object?>{
    if (maxOutputTokens != null)
      'maxOutputTokens': (maxOutputTokens +
              (thinking ? GeminiModel.thinkingRoom(thinkingMode) - 1024 : 0))
          .clamp(256, 65536),
    if (thinking)
      'thinkingConfig': {'thinkingLevel': model.thinkingLevel(thinkingMode)},
    if (schema != null)
      ...switch (schemaStyle) {
        GeminiSchemaStyle.responseFormat => {
            'responseFormat': {
              'text': {'mimeType': 'APPLICATION_JSON', 'schema': schema},
            },
          },
        GeminiSchemaStyle.legacy => {
            'responseMimeType': 'application/json',
            'responseJsonSchema': schema,
          },
      },
  };
  return {
    'systemInstruction': {
      'parts': [
        {'text': system}
      ]
    },
    'contents': [
      {
        'role': 'user',
        'parts': [
          {'text': user}
        ],
      }
    ],
    'safetySettings': [
      for (final h in GeminiHarm.values)
        {
          'category': h.apiName,
          'threshold': (safety[h] ?? GeminiBlock.off).apiName,
        },
    ],
    if (config.isNotEmpty) 'generationConfig': config,
  };
}

/// Why an answer did not come.
enum GeminiBlockKind {
  /// One of the categories the caller sets ([GeminiHarm]).
  safety,

  /// What the API always refuses, whatever is set (its prohibited-use
  /// policy, a blocklist, personal data).
  prohibited,

  /// Too close to existing text (recitation), or no reason given.
  other,
}

GeminiBlockKind? _blockKind(String? reason) => switch (reason) {
      null ||
      '' ||
      'STOP' ||
      'MAX_TOKENS' ||
      'FINISH_REASON_UNSPECIFIED' ||
      'BLOCK_REASON_UNSPECIFIED' =>
        null,
      'SAFETY' || 'IMAGE_SAFETY' => GeminiBlockKind.safety,
      'PROHIBITED_CONTENT' ||
      'BLOCKLIST' ||
      'SPII' ||
      'IMAGE_PROHIBITED_CONTENT' =>
        GeminiBlockKind.prohibited,
      _ => GeminiBlockKind.other,
    };

/// A generateContent answer.
class GeminiResult {
  const GeminiResult({
    required this.text,
    this.finishReason,
    this.block,
    this.promptTokens = 0,
    this.outputTokens = 0,
    this.thoughtTokens = 0,
  });

  final String text;
  final String? finishReason;

  /// Set when the prompt or the answer was blocked.
  final GeminiBlockKind? block;
  final int promptTokens;
  final int outputTokens;
  final int thoughtTokens;

  /// Output as billed: the answer and the thinking.
  int get billedOutput => outputTokens + thoughtTokens;

  factory GeminiResult.fromJson(Map<String, Object?> json) {
    final usage = json['usageMetadata'];
    int count(String key) =>
        usage is Map && usage[key] is num ? (usage[key] as num).toInt() : 0;
    final feedback = json['promptFeedback'];
    final promptBlock = _blockKind(
        feedback is Map ? feedback['blockReason']?.toString() : null);
    final candidates = json['candidates'];
    final first =
        candidates is List && candidates.isNotEmpty ? candidates.first : null;
    final finish = first is Map ? first['finishReason']?.toString() : null;
    final buffer = StringBuffer();
    final content = first is Map ? first['content'] : null;
    final parts = content is Map ? content['parts'] : null;
    if (parts is List) {
      for (final part in parts) {
        // Thought summaries are not the answer.
        if (part is Map && part['text'] is String && part['thought'] != true) {
          buffer.write(part['text']);
        }
      }
    }
    var block = promptBlock ?? _blockKind(finish);
    // No candidate at all and no reason: blocked without saying why.
    if (block == null && first == null) block = GeminiBlockKind.other;
    return GeminiResult(
      text: buffer.toString(),
      finishReason: finish,
      block: block,
      promptTokens: count('promptTokenCount'),
      outputTokens: count('candidatesTokenCount'),
      thoughtTokens: count('thoughtsTokenCount'),
    );
  }
}

/// The translations in a structured answer; null where the answer is not
/// [count] strings.
List<String>? parseTranslations(String text, int count) {
  var body = text.trim();
  // Some answers come fenced as a code block.
  final fence = RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$').firstMatch(body);
  if (fence != null) body = fence.group(1)!;
  Object? data;
  try {
    data = jsonDecode(body);
  } catch (_) {
    return null;
  }
  final list = data is Map ? data['translations'] : data;
  if (list is! List || list.length != count) return null;
  final out = <String>[];
  for (final item in list) {
    if (item is! String) return null;
    out.add(item.trim());
  }
  return out;
}

enum GeminiErrorKind {
  /// Too many requests: wait [GeminiError.retryAfter] and send again.
  rateLimited,

  /// The day's requests are used up (until midnight Pacific time).
  quotaExhausted,

  /// The key is wrong, revoked, or lacks access.
  badKey,

  /// The request itself was refused (an unknown field, a bad value).
  badRequest,

  /// The service failed or is overloaded: try again a little later.
  server,

  /// No connection.
  network,
}

/// A failed request, read from the API's error body.
class GeminiError implements Exception {
  const GeminiError(
    this.kind,
    this.message, {
    this.status,
    this.retryAfter,
    this.quotaId,
    this.quotaLimit,
    this.freeTier,
  });

  final GeminiErrorKind kind;
  final String message;
  final int? status;
  final Duration? retryAfter;

  /// Which quota ran out (for example
  /// `GenerateRequestsPerDayPerProjectPerModel-FreeTier`) and its limit.
  final String? quotaId;
  final int? quotaLimit;

  /// Whether the quota is the free tier's; null when the error says not.
  final bool? freeTier;

  bool get perDay => quotaId != null && quotaId!.contains('PerDay');
  bool get perMinute => quotaId != null && quotaId!.contains('PerMinute');

  /// An error from HTTP [status] and its JSON [body] (`{"error": ...}`).
  factory GeminiError.fromResponse(int status, Object? body) {
    Map? error;
    if (body is String) {
      try {
        body = jsonDecode(body);
      } catch (_) {}
    }
    if (body is Map && body['error'] is Map) error = body['error'] as Map;
    final message = error?['message']?.toString() ?? 'HTTP $status';
    final apiStatus = error?['status']?.toString();
    Duration? retry;
    String? quotaId;
    int? limit;
    bool? free;
    final details = error?['details'];
    if (details is List) {
      for (final d in details) {
        if (d is! Map) continue;
        final type = d['@type']?.toString() ?? '';
        if (type.endsWith('RetryInfo')) {
          final m = RegExp(r'^([\d.]+)s$')
              .firstMatch(d['retryDelay']?.toString() ?? '');
          if (m != null) {
            retry = Duration(
                milliseconds: (double.parse(m.group(1)!) * 1000).round());
          }
        } else if (type.endsWith('QuotaFailure')) {
          final violations = d['violations'];
          if (violations is List && violations.isNotEmpty) {
            // The day's quota counts first: waiting a minute will not help.
            Map? v;
            for (final x in violations) {
              if (x is Map && '${x['quotaId']}'.contains('PerDay')) v = x;
            }
            v ??= violations.first is Map ? violations.first as Map : null;
            quotaId = v?['quotaId']?.toString();
            limit = int.tryParse('${v?['quotaValue']}');
            final metric = '${v?['quotaMetric']}$quotaId'.toLowerCase();
            free = metric.contains('free_tier') || metric.contains('freetier');
          }
        }
      }
    }
    final GeminiErrorKind kind;
    if (status == 429 || apiStatus == 'RESOURCE_EXHAUSTED') {
      kind = quotaId != null && quotaId.contains('PerDay')
          ? GeminiErrorKind.quotaExhausted
          : GeminiErrorKind.rateLimited;
    } else if (status == 401 ||
        status == 403 ||
        apiStatus == 'PERMISSION_DENIED' ||
        apiStatus == 'UNAUTHENTICATED' ||
        message.contains('API key')) {
      kind = GeminiErrorKind.badKey;
    } else if (status >= 500) {
      kind = GeminiErrorKind.server;
    } else {
      kind = GeminiErrorKind.badRequest;
    }
    return GeminiError(kind, message,
        status: status,
        retryAfter: retry,
        quotaId: quotaId,
        quotaLimit: limit,
        freeTier: free);
  }

  @override
  String toString() => 'GeminiError(${kind.name}, $status): $message';
}

/// The current time in the US Pacific time zone, where the API's daily
/// quotas reset at midnight (daylight saving time from the second Sunday
/// of March to the first Sunday of November, at 2 a.m.).
DateTime pacificTime(DateTime now) {
  final utc = now.toUtc();
  DateTime nthSunday(int year, int month, int n) {
    final first = DateTime.utc(year, month, 1);
    final offset = (DateTime.sunday - first.weekday) % 7;
    return DateTime.utc(year, month, 1 + offset + 7 * (n - 1));
  }

  final year = utc.year;
  // 2 a.m. local: 10:00 UTC in March (from PST), 9:00 UTC in November.
  final dstStart = nthSunday(year, 3, 2).add(const Duration(hours: 10));
  final dstEnd = nthSunday(year, 11, 1).add(const Duration(hours: 9));
  final dst = !utc.isBefore(dstStart) && utc.isBefore(dstEnd);
  return utc.add(Duration(hours: dst ? -7 : -8));
}

/// The quota day [now] falls in, as yyyy-mm-dd in Pacific time.
String quotaDay(DateTime now) {
  final p = pacificTime(now);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${p.year}-${two(p.month)}-${two(p.day)}';
}

/// When the quota day of [now] ends, in local time.
DateTime quotaResetAt(DateTime now) {
  final p = pacificTime(now);
  final offset = p.difference(now.toUtc());
  final midnight = DateTime.utc(p.year, p.month, p.day + 1);
  return midnight.subtract(offset).toLocal();
}
