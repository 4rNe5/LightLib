// Checks on a finished translation, and the request that fixes one that
// fails them: text left in the source script, a model repeating itself,
// sentences missing or added, a name not written as the book's glossary
// says. Only a paragraph that fails is sent again. After the QA scanner
// and refinement passes of Glossarion
// (github.com/Shirochi-stack/Glossarion, AGPL-3.0).

// Project imports:
import 'package:openlib/services/translation/book_glossary.dart';
import 'package:openlib/services/translation/paragraph_text.dart';

enum QaIssue {
  leftoverSource,
  repetition,
  tooShort,
  tooLong,
  glossaryMiss,
  speechLevel,
}

final _space = RegExp(r'\s+');
final _punctuation = RegExp(r'[\s「」『』（）()“”"‘’…―─、。，,.!?！？~〜～・]');
final _repeat = RegExp(r'(.{2,24}?)\1{3,}', dotAll: true);

/// What is wrong with [translation] of [source], if anything. [glossary]
/// is the book's glossary; [targetLanguage] the language it should be in.
List<QaIssue> checkTranslation(
  String source,
  String translation, {
  String targetLanguage = 'Korean',
  BookGlossary glossary = BookGlossary.empty,
}) {
  final issues = <QaIssue>[];
  if (translation.trim().isEmpty) return const [QaIssue.tooShort];
  if (leftoverSourceScript(translation, targetLanguage).isNotEmpty) {
    issues.add(QaIssue.leftoverSource);
  }
  // A sound repeated in the source (ドンドンドンドン) may repeat in the
  // translation too.
  if (_repeat.hasMatch(translation.replaceAll(_punctuation, '')) &&
      !_repeat.hasMatch(source.replaceAll(_punctuation, ''))) {
    issues.add(QaIssue.repetition);
  }
  // Japanese and its Korean translation run about as long, letter for
  // letter (0.7-1.2 in a reference light-novel translation); far outside
  // that, sentences were dropped or invented.
  final from = source.replaceAll(_punctuation, '').length;
  final to = translation.replaceAll(_punctuation, '').length;
  if (targetLanguage == 'Korean' && from >= 12) {
    final ratio = to / from;
    if (ratio < 0.45) issues.add(QaIssue.tooShort);
    if (ratio > 2.2) issues.add(QaIssue.tooLong);
  }
  if (missedNames(source, translation, glossary).isNotEmpty) {
    issues.add(QaIssue.glossaryMiss);
  }
  if (targetLanguage == 'Korean' && lostPoliteness(source, translation)) {
    issues.add(QaIssue.speechLevel);
  }
  return issues;
}

/// The glossary's people and places [source] names that [translation]
/// does not write as the glossary says (any part of the name counts: a
/// translation may call 石井和希 just 카즈키).
List<GlossaryEntry> missedNames(
    String source, String translation, BookGlossary glossary) {
  final bare = translation.replaceAll(_space, '');
  final missed = <GlossaryEntry>[];
  // A one-kanji name (周) is often another word in the same text (周り).
  final named = glossary
      .inTexts([source])
      .where((e) => e.isName && e.source.runes.length > 1)
      .toList();
  for (final e in named) {
    // A longer entry already covers this one (天田照人 contains 天田).
    if (named.any((o) => o != e && o.source.contains(e.source))) continue;
    final parts = e.target.split(_space).where((p) => p.isNotEmpty);
    if (!parts.any(bare.contains)) missed.add(e);
  }
  return missed;
}

final _politeJapanese = RegExp(r'です|ます|ません|ましょう|ください|ございま');
final _politeKorean = RegExp(r'요|니다|니까|세요|십시오|죠');

/// A line of dialogue spoken politely (です, ます) that came back in
/// casual Korean: the speaker's voice changed.
bool lostPoliteness(String source, String translation) {
  final s = source.trim();
  if (!s.startsWith('「') || !_politeJapanese.hasMatch(s)) return false;
  return !_politeKorean.hasMatch(translation);
}

/// A request to fix [draft], the translation of [source] that failed
/// [issues]. [style] is the instructions the first request had.
String refinementPrompt({
  required String style,
  required String source,
  required String draft,
  required List<QaIssue> issues,
  List<GlossaryEntry> glossary = const [],
  String targetLanguage = 'Korean',
}) {
  final b = StringBuffer(style.trim())..writeln();
  if (glossary.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Names and terms in this book (write them exactly like this):');
    for (final e in glossary) {
      b.writeln(e.promptLine);
    }
  }
  b
    ..writeln()
    ..writeln('Japanese:')
    ..writeln(source)
    ..writeln()
    ..writeln('A draft $targetLanguage translation:')
    ..writeln(draft)
    ..writeln()
    ..writeln('Problems with the draft:');
  for (final issue in issues) {
    b.writeln('- ${_problem(issue, targetLanguage)}');
  }
  b
    ..writeln()
    ..writeln('Write the corrected $targetLanguage translation of the Japanese: '
        'one paragraph, the translation only.');
  return b.toString().trimRight();
}

/// What [issue] means, said to the model.
String qaProblem(QaIssue issue, String targetLanguage) =>
    _problem(issue, targetLanguage);

String _problem(QaIssue issue, String targetLanguage) => switch (issue) {
      QaIssue.leftoverSource =>
        'Japanese text is left untranslated; every word must be $targetLanguage.',
      QaIssue.repetition => 'It repeats the same words over and over.',
      QaIssue.tooShort => 'Parts of the Japanese are missing; translate all of it.',
      QaIssue.tooLong => 'It adds text that is not in the Japanese.',
      QaIssue.glossaryMiss =>
        'Names are not written as the glossary says; use exactly those forms.',
      QaIssue.speechLevel =>
        'The speaker talks politely (です, ます) but the draft is casual; '
            'use polite Korean (존댓말: ~요, ~니다).',
    };

/// Which of two translations to keep: the one with fewer problems, the
/// first on a tie.
bool refinedIsBetter(List<QaIssue> before, List<QaIssue> after) {
  int weight(List<QaIssue> issues) => issues.fold(
      0, (n, i) => n + (i == QaIssue.leftoverSource ? 3 : i == QaIssue.repetition ? 3 : 1));
  return weight(after) < weight(before);
}
