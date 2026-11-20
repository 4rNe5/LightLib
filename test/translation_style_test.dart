// A narration's tense read off its sentence endings, and the style
// checks built on it. The sentences are made up; the endings are the
// kinds the owner's three books (translated with Gemini 3.5 Flash) are
// full of.

// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/services/translation/translation_qa.dart';
import 'package:openlib/services/translation/translation_style.dart';

void main() {
  test('how a narration sentence ends', () {
    const cases = {
      '그는 문을 열었다.': KoreanEnding.past,
      '하늘이 파랬다.': KoreanEnding.past,
      '손님이 카운터에 선다.': KoreanEnding.actionPresent,
      '두 사람은 건배를 한다.': KoreanEnding.actionPresent,
      '그가 손을 뻗는다.': KoreanEnding.actionPresent,
      '심장이 아프다.': KoreanEnding.statePresent,
      '택시가 멈춰 서 있다.': KoreanEnding.statePresent,
      '잘 모르겠다.': KoreanEnding.statePresent,
      '옷은 어제 그대로다.': KoreanEnding.statePresent,
      '그건 정말 아꼈다는 증거다.': KoreanEnding.statePresent,
      '결국 그렇게 된 것이다.': KoreanEnding.explains,
      '그래서 떠난 거다.': KoreanEnding.explains,
      '분명 실망할 것이다.': KoreanEnding.guess,
      '촬영이 결정되었다고 한다.': KoreanEnding.hearsay,
      '눈치챈 모양이다.': KoreanEnding.hearsay,
      '감사합니다.': KoreanEnding.polite,
      '그런가요.': KoreanEnding.polite,
      '정말일까.': KoreanEnding.other,
    };
    cases.forEach((sentence, ending) {
      expect(koreanEnding(sentence), ending, reason: sentence);
    });
    expect(japaneseEndsInPast('ドアを開けた。'), isTrue);
    expect(japaneseEndsInPast('彼は静かだった。'), isTrue);
    expect(japaneseEndsInPast('手を伸ばす。'), isFalse);
  });

  test('a slip of tense: one present sentence among past ones', () {
    final sources = ['彼は席に着いた。', 'しずくが手を伸ばす。', '二人は笑った。', '「行こう」', '胸が痛い。'];
    final slips = tenseSlips(sources, [
      '그는 자리에 앉았다.',
      '시즈쿠가 손을 뻗는다.',
      '두 사람은 웃었다.',
      '“가자.”',
      '가슴이 아프다.',
    ]);
    expect(slips, {1});
    // Told right: nothing to send back. How things are (아프다) is no slip.
    expect(
        tenseSlips(sources, [
          '그는 자리에 앉았다.',
          '시즈쿠가 손을 뻗었다.',
          '두 사람은 웃었다.',
          '“가자.”',
          '가슴이 아프다.',
        ]),
        isEmpty);
    // A scene told in the present, sentence after sentence, is left as
    // the translation has it.
    expect(
        tenseSlips(['歩く。', '手を伸ばす。', '笑う。'],
            ['걷는다.', '손을 뻗는다.', '웃는다.']),
        isEmpty);
    // The paragraph before counts as a neighbour.
    expect(
        tenseSlips(['手を伸ばす。', '彼は笑った。'], ['손을 뻗는다.', '그는 웃었다.'],
            before: ['그는 자리에 앉았다.']),
        {0});
    // The book says 〜た and the translation the present: a slip wherever
    // it stands.
    expect(tenseSlips(['彼は手を伸ばした。'], ['그는 손을 뻗는다.']), {0});
    // Speech is not narration.
    expect(tenseSlips(['「行く」', '彼は笑った。'], ['“간다.”', '그는 웃었다.']), isEmpty);
    // Untranslated paragraphs are skipped.
    expect(tenseSlips(['歩いた。', '笑う。'], [null, '웃는다.']), isEmpty);
  });

  test('그녀 for 彼女, and word-for-word constructions', () {
    expect(leansOnShe('彼女は笑った。', '그녀는 웃었다.'), isTrue);
    expect(leansOnShe('彼女の手を彼女は見た。', '시즈쿠는 그녀의 손과 그녀를 보았다.'), isTrue);
    // Once, in the middle of a sentence: ordinary Korean.
    expect(leansOnShe('俺は彼女を見た。', '나는 그녀를 보았다.'), isFalse);
    expect(leansOnShe('彼女は笑った。', '시즈쿠는 웃었다.'), isFalse);
    // Not from 彼女: the translation's own word.
    expect(leansOnShe('しずくは笑った。', '그녀는 웃었다.'), isFalse);

    expect(stiffness('그는 문을 열었다.'), 0);
    expect(readsStiff('그는 걷고 있었다.'), isFalse);
    expect(readsStiff('이상하다고 생각했지만, 그녀는 웃고 있었고, 나는 잠들어 버렸다.'), isTrue);
    expect(readsStiff('나에게 있어서 그것은 가지 않으면 안 되는 길이었다.'), isTrue);
  });

  test('a paragraph is held to a style only where told to', () {
    const source = 'しずくが手を伸ばす。';
    const draft = '시즈쿠가 손을 뻗는다.';
    expect(checkTranslation(source, draft), isEmpty);
    expect(checkTranslation(source, draft, also: {QaIssue.tenseSlip}),
        [QaIssue.tenseSlip]);
    expect(
        checkTranslation(source, '시즈쿠가 손을 뻗었다.',
            also: {QaIssue.tenseSlip}),
        isEmpty);
    expect(
        checkTranslation('彼女は笑った。', '그녀는 웃었다.', also: {QaIssue.pronoun}),
        [QaIssue.pronoun]);
    expect(checkTranslation('彼女は笑った。', '그녀는 웃었다.'), isEmpty);
    // A second answer that mends the style and breaks the sense is not
    // the better one.
    expect(refinedIsBetter(const [QaIssue.tenseSlip], const []), isTrue);
    expect(
        refinedIsBetter(const [QaIssue.tenseSlip], const [QaIssue.tooShort]),
        isFalse);
    expect(
        refinedIsBetter(const [QaIssue.pronoun], const [QaIssue.glossaryMiss]),
        isFalse);
  });

  test('the request to mend a style says what, and who is spoken of', () {
    final prompt = refinementPrompt(
      style: 'STYLE',
      source: '彼女は笑った。',
      draft: '그녀는 웃었다.',
      issues: const [QaIssue.pronoun, QaIssue.tenseSlip],
      context: const ['시즈쿠가 문을 열었다.'],
    );
    expect(prompt, contains('The story just before'));
    expect(prompt, contains('시즈쿠가 문을 열었다.'));
    expect(prompt, contains('Write the name of the woman meant'));
    expect(prompt, contains('End that sentence in the past'));
  });

  test('a habit, a general fact, a feeling in the present is the book\'s '
      'own tense, not a slip', () {
    // Each between two past-tense sentences, as the book has it.
    const around = ('그는 자리에 앉았다.', '두 사람은 가게를 나왔다.');
    Set<int> slips(String source, String korean) => tenseSlips(
        ['彼は席に着いた。', source, '二人は店を出た。'],
        [around.$1, korean, around.$2]);
    for (final (source, korean) in const [
      ('彼女はいつも俺をからかってくる。', '그녀는 나를 자주 놀리곤 한다.'),
      ('味はその都度変わる。', '맛은 그때마다 매번 달라진다.'),
      ('それも事実かもしれない。', '그것도 사실일지 모른다.'),
      ('俺は彼のことが好きだ。', '나는 그를 좋아한다.'),
      ('それは疾患のことだ。', '그것은 질환을 뜻한다.'),
      ('誰にも言わないでほしい。', '아무에게도 말하지 않았으면 한다.'),
      ('そんな気がする。', '그런 기분이 든다.'),
      ('気をつけなければならない。', '조심해야 한다.'),
      ('その気持ちはよく分かる。', '그 마음은 잘 안다.'),
    ]) {
      expect(slips(source, korean), isEmpty, reason: korean);
      expect(hasActionPresent(source, korean), isFalse, reason: korean);
    }
    // What happens there and then is told in the past.
    for (final (source, korean) in const [
      ('しずくが手を伸ばす。', '시즈쿠가 손을 뻗는다.'),
      ('カップをテーブルの上に置く。', '컵을 테이블 위에 놓는다.'),
      ('風が駆け抜ける。', '바람이 스쳐 지나간다.'),
    ]) {
      expect(slips(source, korean), {1}, reason: korean);
      expect(hasActionPresent(source, korean), isTrue, reason: korean);
    }
    // The book's sentence is in the past: whatever it says, the Korean
    // changed the tense.
    expect(slips('俺は彼のことが好きだった。', '나는 그를 좋아한다.'), {1});
  });
}
