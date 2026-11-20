// Checks on a finished translation, and the request that fixes one that
// fails them: text left in the source script, a model repeating itself,
// sentences missing or added, a name not written as the book's glossary
// says. Only a paragraph that fails is sent again. After the QA scanner
// and refinement passes of Glossarion
// (github.com/Shirochi-stack/Glossarion, AGPL-3.0).

// Project imports:
import 'package:openlib/services/translation/book_glossary.dart';
import 'package:openlib/services/translation/paragraph_text.dart';
import 'package:openlib/services/translation/translation_style.dart';

enum QaIssue {
  leftoverSource,
  repetition,
  tooShort,
  tooLong,
  glossaryMiss,
  speechLevel,

  /// A narration sentence told in the present among past-tense ones
  /// ([tenseSlips]): looked for only where the sentences around say so.
  tenseSlip,

  /// 그녀 where Korean names the person or leaves the subject out.
  pronoun,

  /// Thick with word-for-word constructions.
  stiff,
}

/// The checks that read a translation's style and not its faithfulness.
/// Which of them a request makes is the engine's to say: they send
/// paragraphs back for a second answer.
const styleChecks = {QaIssue.tenseSlip, QaIssue.pronoun, QaIssue.stiff};

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
  Set<QaIssue> also = const {},
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
  if (targetLanguage == 'Korean') {
    // [also]: the style checks this paragraph is held to. A slip of
    // tense is found among its neighbours ([tenseSlips]); here it means
    // the paragraph must tell nothing done in the present.
    if (also.contains(QaIssue.tenseSlip) &&
        hasActionPresent(source, translation)) {
      issues.add(QaIssue.tenseSlip);
    }
    if (also.contains(QaIssue.pronoun) && leansOnShe(source, translation)) {
      issues.add(QaIssue.pronoun);
    }
    if (also.contains(QaIssue.stiff) && readsStiff(translation)) {
      issues.add(QaIssue.stiff);
    }
  }
  return issues;
}

/// The glossary's people and places [source] names that [translation]
/// does not write as the glossary says, letter for letter (any word of
/// the name counts: a translation may call 石井和希 just 카즈키). A name
/// with a space put inside it (준 타로 for 준타로) is not that name.
List<GlossaryEntry> missedNames(
    String source, String translation, BookGlossary glossary) {
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
    if (!parts.any(translation.contains)) missed.add(e);
  }
  return missed;
}

// ---------------------------------------------------------------------------
// The glossary's names, written as it says
// ---------------------------------------------------------------------------

/// A model's answer made ready to show: polished ([polishTranslation]),
/// and for Korean the glossary's names written as the glossary writes
/// them ([enforceGlossary]).
String finishTranslation(String answer, String source, String targetLanguage,
    BookGlossary glossary) {
  final polished = polishTranslation(answer, source, targetLanguage);
  return targetLanguage == 'Korean'
      ? enforceGlossary(source, polished, glossary)
      : polished;
}

final _hangulWord = RegExp(r'[가-힣]+');
final _cjk = RegExp(r'[\u3400-\u4DBF\u4E00-\u9FFF]');
final _cjkOnly = RegExp(r'^[\u3400-\u4DBF\u4E00-\u9FFF々]+$');

/// What follows a name in a Korean word: nothing, or a particle.
const _particles = {
  '', '은', '는', '이', '가', '을', '를', '의', '와', '과', '도', '에', '야',
  '아', '랑', '로', '만', '여', '씨', '군', '양', '님', '쨩', '짱', '에게',
  '한테', '께서', '이랑', '이는', '이가', '이를', '이도', '이와', '이의', '이야',
  '으로', '처럼', '보다', '까지', '부터', '만큼', '이나', '이라', '라고',
  '이라고', '라는', '이라는', '에게서', '한테서', '에게는', '에게도', '한테는',
  '한테도', '에는', '에도', '와는', '과는', '로는', '선배', '였다', '이다',
  '이었다', '답게', '다운', '마저', '조차', '뿐', '밖에', '하고', '에게만',
};

/// One-syllable particles a name's last syllable may be mistaken for.
const _shortParticles = {
  '은', '는', '이', '가', '을', '를', '의', '와', '과', '도', '에', '야', '아',
  '랑', '로', '만', '여',
};

(int, int, int)? _jamo(String ch) {
  final c = ch.codeUnitAt(0) - 0xAC00;
  if (c < 0 || c >= 11172) return null;
  return (c ~/ 588, (c ~/ 28) % 21, c % 28);
}

/// [s] without long vowels: a bare vowel that only repeats the vowel of
/// the syllable before it (유우나 → 유나, 사아나 → 사나, 코우 → 코).
String _squash(String s) {
  final out = StringBuffer();
  String? last;
  for (final ch in s.split('')) {
    final j = _jamo(ch);
    final p = last == null ? null : _jamo(last);
    if (j != null && p != null && j.$1 == 11 && j.$3 == 0 && p.$3 == 0) {
      final same = p.$2 == j.$2;
      final ou = (p.$2 == 8 || p.$2 == 12) && j.$2 == 13; // 오/요 + 우
      final yu = p.$2 == 17 && j.$2 == 13; // 유 + 우
      final ya = p.$2 == 2 && j.$2 == 0; // 야 + 아
      final ei = p.$2 == 5 && j.$2 == 20; // 에 + 이
      if (same || ou || yu || ya || ei) continue;
    }
    out.write(ch);
    last = ch;
  }
  return out.toString();
}

/// How many jamo two words of the same length differ in (2 = two or
/// more).
int _jamoApart(String a, String b) {
  if (a.length != b.length) return 2;
  var n = 0;
  for (var i = 0; i < a.length; i++) {
    if (a[i] == b[i]) continue;
    final x = _jamo(a[i]), y = _jamo(b[i]);
    if (x == null || y == null) return 2;
    n += (x.$1 != y.$1 ? 1 : 0) + (x.$2 != y.$2 ? 1 : 0) + (x.$3 != y.$3 ? 1 : 0);
    if (n > 1) return 2;
  }
  return n;
}

/// [translation] with the glossary's names written as the glossary
/// writes them, where the translation wrote a near miss: a space inside
/// the name (준 타로), a long vowel (유우나), a letter off (시즈크 for
/// 시즈쿠), or the name left in kanji, whole (上野) or in part (上노).
/// Only names [source] has, only whole words (with their particle), and
/// never a word that is another name of the glossary. What it changed is
/// in [changes], if given.
String enforceGlossary(
    String source, String translation, BookGlossary glossary,
    {List<(String, String)>? changes}) {
  if (translation.isEmpty || glossary.isEmpty) return translation;
  final named = glossary
      .inTexts([source], limit: 60)
      .where((e) => e.isName && e.target.trim().isNotEmpty)
      .toList();
  if (named.isEmpty) return translation;
  var text = translation;
  void note(String from, String to) => changes?.add((from, to));

  // The name copied as it stands in the book (上野 left in the Korean).
  for (final e in named) {
    if (_cjk.hasMatch(e.source) && text.contains(e.source)) {
      note(e.source, e.target);
      text = text.replaceAll(e.source, e.target);
    }
  }

  // Half of it copied, the rest written out (上노 for 上野 → 우에노,
  // 준太郎, 天田 테루히토): kanji in a Korean sentence is never meant,
  // and what stands right beside it is the rest of this very name.
  for (final e in named) {
    if (!_cjk.hasMatch(text)) break;
    final src = e.source;
    if (src.length < 2 || src.runes.length != src.length) continue;
    if (!_cjkOnly.hasMatch(src)) continue;
    final target = e.target.trim();
    for (final written in {target, target.replaceAll(_space, '')}) {
      for (var k = src.length - 1; k >= 1; k--) {
        for (var n = written.length - 1; n >= 1; n--) {
          for (final half in [
            '${src.substring(0, k)}${written.substring(written.length - n)}',
            '${written.substring(0, n)}${src.substring(k)}',
          ]) {
            if (half.trim() != half || !text.contains(half)) continue;
            note(half, target);
            text = text.replaceAll(half, target);
          }
        }
      }
    }
  }

  // Every form a name is written in: the glossary's own words, so that
  // one name is never "corrected" into another (유키 into 유키노).
  final taken = <String>{
    for (final e in glossary.entries)
      if (e.target.isNotEmpty) ...[
        e.target,
        ...e.target.split(_space).where((p) => p.isNotEmpty),
      ],
  };
  bool isParticle(String rest) => _particles.contains(rest);

  for (final e in named) {
    final target = e.target.trim();
    final words = target.split(_space).where((p) => p.isNotEmpty).toList();
    // A full name written as one word (아마다테루히토).
    if (words.length > 1) {
      final joined = words.join();
      text = text.replaceAllMapped(
          RegExp('(?<![가-힣])${RegExp.escape(joined)}'), (m) {
        note(joined, target);
        return target;
      });
    }
    for (final form in words) {
      if (form.length < 2 || !_hangulWord.hasMatch(form)) continue;
      // A space inside it. Two syllables apart are too easily two words.
      if (form.length >= 3) {
        final spaced = RegExp('(?<![가-힣])'
            '${form.split('').map(RegExp.escape).join(r'\s?')}');
        text = text.replaceAllMapped(spaced, (m) {
          final found = m.group(0)!;
          if (found == form) return found;
          note(found, form);
          return form;
        });
      }
      // One word, a long vowel or a letter off.
      text = text.replaceAllMapped(_hangulWord, (m) {
        final word = m.group(0)!;
        if (word.startsWith(form)) return word;
        // Another name with its particle: not this one misspelled.
        for (final other in taken) {
          if (other != form &&
              word.startsWith(other) &&
              isParticle(word.substring(other.length))) {
            return word;
          }
        }
        for (var n = form.length + 2; n >= form.length - 1 && n >= 2; n--) {
          if (n > word.length) continue;
          final cand = word.substring(0, n);
          final rest = word.substring(n);
          if (!isParticle(rest) || taken.contains(cand)) continue;
          final longVowel =
              cand.length > form.length && _squash(cand) == _squash(form);
          // 카자미의 is 카자미 and a particle, not 카자미야 misspelled.
          final cutShort = cand.length == form.length &&
              cand.substring(0, n - 1) == form.substring(0, n - 1) &&
              _shortParticles.contains(cand[n - 1]);
          final letterOff = form.length >= 3 &&
              !cutShort &&
              _jamoApart(cand, form) == 1;
          if (longVowel || letterOff) {
            note(cand, form);
            return '$form$rest';
          }
        }
        return word;
      });
    }
  }
  return text;
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
  List<String> context = const [],
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
  if (context.isNotEmpty) {
    b
      ..writeln()
      ..writeln('The story just before (who is spoken of; do not translate '
          'it again):');
    context.forEach(b.writeln);
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
      QaIssue.tenseSlip =>
        'The narration around it is in the past tense, but a sentence here '
            'tells what happens in the scene in the present (-ㄴ다/-는다). '
            'End that sentence in the past (-었다/-았다/-했다). A habit, a '
            'general fact, and what someone feels, knows or wishes stay in '
            'the present where the Japanese has them so. Change nothing '
            'else.',
      QaIssue.pronoun =>
        '그녀 stands where Korean names the person or leaves the subject '
            'out. Write the name of the woman meant, if the story just '
            'before makes plain who she is, or drop the subject; keep 그녀 '
            'only where neither reads well. Change nothing else.',
      QaIssue.stiff =>
        'It reads word for word (-고 있었다, -라고 생각했다, -어 버렸다, '
            '~에 대해 and the like). Say the same in natural Korean, keeping '
            'the meaning, every name, the tense and each speaker\'s speech '
            'level.',
    };

/// Which of two translations to keep: the one with fewer problems, the
/// first on a tie.
bool refinedIsBetter(List<QaIssue> before, List<QaIssue> after) {
  // A fault of faithfulness outweighs one of style: a second answer that
  // tells the tense right but drops a sentence is not the better one.
  int weight(List<QaIssue> issues) => issues.fold(
      0,
      (n, i) =>
          n +
          (i == QaIssue.leftoverSource || i == QaIssue.repetition
              ? 6
              : styleChecks.contains(i)
                  ? 1
                  : 2));
  return weight(after) < weight(before);
}
