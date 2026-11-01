// Meanings of words in their sentence, and explanations of sentences,
// asked of the translation engine the reader uses (Gemini or the model on
// the phone) and kept, so each is asked once. No dictionary is bundled:
// the meaning comes with the context it was met in.

// Dart imports:
import 'dart:convert';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Project imports:
import 'package:openlib/services/logger.dart';
import 'package:openlib/services/study/study_store.dart';
import 'package:openlib/services/translation/translator.dart';

@immutable
class WordQuery {
  const WordQuery({
    required this.base,
    this.surface = '',
    this.reading = '',
    this.sentence = '',
    this.pos = '',
    this.level = 0,
  });

  /// The dictionary form (食べる).
  final String base;

  /// As written in the book (食べ).
  final String surface;

  /// The dictionary form's reading, in hiragana.
  final String reading;
  final String sentence;

  /// kuromoji's part of speech (名詞, 動詞, ...).
  final String pos;

  /// JLPT 5..1, 0 when on no list.
  final int level;
}

@immutable
class WordMeaning {
  const WordMeaning({required this.meaning, this.other = const [], this.note = ''});
  final String meaning;
  final List<String> other;
  final String note;

  Map<String, Object> toJson() =>
      {'meaning': meaning, 'other': other, 'note': note};

  factory WordMeaning.fromJson(Map<String, dynamic> j) => WordMeaning(
        meaning: '${j['meaning'] ?? ''}'.trim(),
        other: [
          for (final o in (j['other'] is List ? j['other'] as List : const []))
            if ('$o'.trim().isNotEmpty) '$o'.trim(),
        ],
        note: '${j['note'] ?? ''}'.trim(),
      );
}

@immutable
class ExplainedWord {
  const ExplainedWord(this.word, this.reading, this.meaning);
  final String word;
  final String reading;
  final String meaning;
}

@immutable
class GrammarPoint {
  const GrammarPoint(this.pattern, this.explanation);
  final String pattern;
  final String explanation;
}

@immutable
class SentenceExplanation {
  const SentenceExplanation({
    required this.translation,
    this.words = const [],
    this.grammar = const [],
    this.nuance = '',
  });
  final String translation;
  final List<ExplainedWord> words;
  final List<GrammarPoint> grammar;
  final String nuance;

  Map<String, Object> toJson() => {
        'translation': translation,
        'words': [
          for (final w in words)
            {'word': w.word, 'reading': w.reading, 'meaning': w.meaning},
        ],
        'grammar': [
          for (final g in grammar)
            {'pattern': g.pattern, 'explanation': g.explanation},
        ],
        'nuance': nuance,
      };

  factory SentenceExplanation.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> maps(Object? v) => [
          for (final x in (v is List ? v : const []))
            if (x is Map) Map<String, dynamic>.from(x),
        ];
    String s(Object? v) => '${v ?? ''}'.trim();
    return SentenceExplanation(
      translation: s(j['translation']),
      words: [
        for (final w in maps(j['words']))
          if (s(w['word']).isNotEmpty)
            ExplainedWord(s(w['word']), s(w['reading']), s(w['meaning'])),
      ],
      grammar: [
        for (final g in maps(j['grammar']))
          if (s(g['pattern']).isNotEmpty)
            GrammarPoint(s(g['pattern']), s(g['explanation'])),
      ],
      nuance: s(j['nuance']),
    );
  }
}

// ---------------------------------------------------------------------------
// Prompts and answers
// ---------------------------------------------------------------------------

/// The instructions every word request shares (sent apart, read once
/// where the engine keeps them).
String wordPromptHead(String targetLanguage) =>
    'You explain Japanese words to a $targetLanguage-speaking reader of a '
    'Japanese novel. Give the meaning the word has in the sentence it was '
    'met in, in natural $targetLanguage, as a dictionary would put it: a '
    'few words, no full sentence. Answer with JSON only, in this shape:\n'
    '{"meaning": "the meaning in this sentence", '
    '"other": ["other common meanings, at most 3"], '
    '"note": "one short note on nuance or usage, or an empty string"}\n'
    'Write every value in $targetLanguage.';

String wordPrompt(WordQuery q, String targetLanguage) {
  final head = wordPromptHead(targetLanguage);
  final written = q.surface.isNotEmpty && q.surface != q.base
      ? ' (written in the book as ${q.surface})'
      : '';
  final reading = q.reading.isNotEmpty ? ', read ${q.reading}' : '';
  return '$head\n\nWord: ${q.base}$written$reading\n'
      'Sentence: ${q.sentence.isEmpty ? q.base : q.sentence}';
}

String explainPromptHead(String targetLanguage, int level) =>
    'You explain sentences from Japanese novels to a $targetLanguage-'
    'speaking learner at about JLPT N$level. Answer with JSON only, in this '
    'shape:\n'
    '{"translation": "a natural translation", '
    '"words": [{"word": "dictionary form", "reading": "hiragana", '
    '"meaning": "its meaning here"}], '
    '"grammar": [{"pattern": "the form, e.g. 〜てしまう", '
    '"explanation": "what it does in this sentence"}], '
    '"nuance": "tone, register or what is implied, in one or two sentences"}\n'
    'List only the words and grammar a learner at that level may not know: '
    'at most 6 words and 4 grammar points. Write every explanation in '
    '$targetLanguage.';

String explainPrompt(String sentence, String targetLanguage, int level,
        {String before = ''}) =>
    '${explainPromptHead(targetLanguage, level)}\n\n'
    '${before.isNotEmpty ? 'The sentence before (context only): $before\n' : ''}'
    'Sentence: $sentence';

/// The JSON object in an answer (fenced, or with words around it).
Map<String, dynamic>? answerJson(String? answer) {
  if (answer == null) return null;
  final start = answer.indexOf('{');
  final end = answer.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  try {
    final v = jsonDecode(answer.substring(start, end + 1));
    return v is Map ? Map<String, dynamic>.from(v) : null;
  } catch (_) {
    return null;
  }
}

WordMeaning? parseWordAnswer(String? answer) {
  final j = answerJson(answer);
  if (j != null) {
    final m = WordMeaning.fromJson(j);
    return m.meaning.isEmpty ? null : m;
  }
  // Not JSON: a short plain answer is still a meaning.
  final text = (answer ?? '')
      .replaceAll(RegExp(r'```\w*'), '')
      .trim()
      .split('\n')
      .first
      .trim();
  if (text.isEmpty || text.length > 80) return null;
  return WordMeaning(meaning: text);
}

SentenceExplanation? parseExplanation(String? answer) {
  final j = answerJson(answer);
  if (j == null) return null;
  final e = SentenceExplanation.fromJson(j);
  return e.translation.isEmpty && e.words.isEmpty && e.grammar.isEmpty
      ? null
      : e;
}

// ---------------------------------------------------------------------------
// The assistant
// ---------------------------------------------------------------------------

class StudyAssistant {
  StudyAssistant({
    required this.translator,
    required this.targetLanguage,
    required this.targetCode,
    StudyStore? store,
  }) : store = store ?? StudyStore.instance;

  /// The engine to ask (made when first needed).
  final Future<Translator?> Function() translator;

  /// The language explanations are in (English name, e.g. Korean).
  final String targetLanguage;
  final String targetCode;
  final StudyStore store;
  final AppLogger _logger = AppLogger();

  String _wordKey(WordQuery q) =>
      'w\u0001$targetCode\u0001${q.base}\u0001${q.reading}\u0001${q.sentence}';
  String _explainKey(String sentence, int level) =>
      'e\u0001$targetCode\u0001$level\u0001$sentence';

  /// A meaning already asked for, if any.
  WordMeaning? knownMeaning(WordQuery q) {
    final v = store.answer(_wordKey(q));
    return v is Map ? WordMeaning.fromJson(Map<String, dynamic>.from(v)) : null;
  }

  SentenceExplanation? knownExplanation(String sentence, int level) {
    final v = store.answer(_explainKey(sentence, level));
    return v is Map
        ? SentenceExplanation.fromJson(Map<String, dynamic>.from(v))
        : null;
  }

  Future<WordMeaning?> meaning(WordQuery q) async {
    await store.load();
    store.count(const StudyDay(looked: 1));
    final known = knownMeaning(q);
    if (known != null) return known;
    final t = await translator();
    if (t == null) return null;
    final watch = Stopwatch()..start();
    final answer = await t.complete(wordPrompt(q, targetLanguage),
        maxTokens: 160,
        priority: TranslationPriority.visible,
        head: wordPromptHead(targetLanguage));
    final m = parseWordAnswer(answer);
    _logger.info('Word looked up', tag: 'Study', metadata: {
      'ms': watch.elapsedMilliseconds,
      'ok': m != null,
    });
    if (m != null) store.keepAnswer(_wordKey(q), m.toJson());
    return m;
  }

  Future<SentenceExplanation?> explain(String sentence,
      {int level = 4, String before = ''}) async {
    await store.load();
    store.count(const StudyDay(explained: 1));
    final known = knownExplanation(sentence, level);
    if (known != null) return known;
    final t = await translator();
    if (t == null) return null;
    final watch = Stopwatch()..start();
    final answer = await t.complete(
        explainPrompt(sentence, targetLanguage, level, before: before),
        maxTokens: 700,
        priority: TranslationPriority.visible,
        head: explainPromptHead(targetLanguage, level));
    final e = parseExplanation(answer);
    _logger.info('Sentence explained', tag: 'Study', metadata: {
      'ms': watch.elapsedMilliseconds,
      'ok': e != null,
    });
    if (e != null) store.keepAnswer(_explainKey(sentence, level), e.toJson());
    return e;
  }
}
