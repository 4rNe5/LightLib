// What a `CloudTranslator` asks of an engine that is not on the phone
// (Gemini, Claude): one request answered with text, and the reader's
// choices for that engine. Each engine keeps its own key, models and
// count of what it used; the translator, its checks and its corrections
// are the same for all.

// Project imports:
import 'package:openlib/services/translation/gemini/gemini_api.dart';

/// Sends one request and gives the answer. The result and the errors are
/// Gemini's types, which every engine's client answers in: a refusal is a
/// [GeminiBlockKind], a failure a [GeminiError] of one of its kinds.
abstract class CloudClient {
  /// [schema]: the JSON the answer has to be (a JSON Schema as Gemini
  /// takes it; a client turns it into its own engine's form).
  /// [paragraphs]: how many paragraphs the request translates, for the
  /// day's count.
  Future<GeminiResult> generate({
    required String system,
    required String user,
    Map<String, Object?>? schema,
    int? maxOutputTokens,
    int paragraphs,
  });
}

/// The reader's choices for one engine, and its count.
abstract class CloudSettings {
  /// What the status line calls it ("Gemini", "Claude").
  String get engineLabel;

  /// Nothing more can be asked for now: the day's quota, or the credit,
  /// is used up.
  bool get exhausted;

  /// When the engine cannot translate, the model on the phone does.
  bool get deviceFallback;

  /// Requests that may be in flight at once for a book.
  int get concurrency;

  /// Paragraphs that read word for word are sent once more.
  bool get polish;

  void recordOnDevice(int paragraphs);
  void recordBlocked(GeminiBlockKind kind, int paragraphs);
}
