// The glossary's names written as the glossary writes them: what a
// translation got nearly right is set right without asking the model
// again, and only that. The cases are the owner's three books (Gemini
// 3.5 Flash): 준 타로 120 times for 준타로, 시즈크 54 times for 시즈쿠.

// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/services/translation/book_glossary.dart';
import 'package:openlib/services/translation/translation_qa.dart';
import 'package:openlib/services/translation/translation_repair.dart';

void main() {
  const g = BookGlossary(complete: true, entries: [
    GlossaryEntry(source: '純太郎', target: '준타로', gender: GlossaryGender.male),
    GlossaryEntry(source: '純', target: '준', gender: GlossaryGender.male),
    GlossaryEntry(source: 'しずく', target: '시즈쿠', gender: GlossaryGender.female),
    GlossaryEntry(source: '結奈', target: '유나', gender: GlossaryGender.female),
    GlossaryEntry(source: '沙奈', target: '사나', gender: GlossaryGender.female),
    GlossaryEntry(source: '風宮', target: '카자미야'),
    GlossaryEntry(source: '雪', target: '유키', gender: GlossaryGender.female),
    GlossaryEntry(source: '雪乃', target: '유키노', gender: GlossaryGender.female),
    GlossaryEntry(source: '天田照人', target: '아마다 테루히토', family: '天田'),
    GlossaryEntry(source: '上野', target: '우에노', kind: GlossaryKind.place),
    GlossaryEntry(source: '晴也', target: '하루야', gender: GlossaryGender.male),
    GlossaryEntry(source: '脇役', target: '모브', kind: GlossaryKind.term),
  ]);
  String fix(String source, String translation) =>
      enforceGlossary(source, translation, g);

  test('a space inside a name', () {
    expect(fix('純太郎は笑った。', '준 타로는 웃었다.'), '준타로는 웃었다.');
    expect(fix('「純太郎、行こう」', '“준 타로, 가자.”'), '“준타로, 가자.”');
    expect(fix('純太郎の手', '준 타로의 손'), '준타로의 손');
    // Written right already.
    expect(fix('純太郎は笑った。', '준타로는 웃었다.'), '준타로는 웃었다.');
    // His short name is another name, and stays.
    expect(fix('「純くん」と純太郎は呼ばれた。', '“준 군.” 하고 준타로는 불렸다.'),
        '“준 군.” 하고 준타로는 불렸다.');
  });

  test('a letter off, a long vowel', () {
    expect(fix('しずくは笑った。', '시즈크는 웃었다.'), '시즈쿠는 웃었다.');
    expect(fix('しずくの声', '시즈크의 목소리'), '시즈쿠의 목소리');
    expect(fix('結奈が来た。', '유우나가 왔다.'), '유나가 왔다.');
    expect(fix('沙奈と話した。', '사아나와 이야기했다.'), '사나와 이야기했다.');
    final changes = <(String, String)>[];
    enforceGlossary('しずくと結奈', '시즈크와 유우나', g, changes: changes);
    expect(changes, [('시즈크', '시즈쿠'), ('유우나', '유나')]);
  });

  test('only names the source has, only whole words', () {
    // No 結奈 in the source: the word is something else.
    expect(fix('彼女は笑った。', '유우나는 웃었다.'), '유우나는 웃었다.');
    // 카자미 with its particle is not 카자미야 misspelled (the model read
    // the name another way: that is for the name check to send back).
    expect(fix('風宮の話', '카자미의 이야기'), '카자미의 이야기');
    // Another name of the glossary is never "corrected" into this one.
    expect(fix('雪と雪乃', '유키와 유키노'), '유키와 유키노');
    expect(fix('雪乃は雪を見た。', '유키노는 유키를 보았다.'), '유키노는 유키를 보았다.');
    // An everyday word next to a name it resembles.
    expect(fix('晴也は一日を過ごした。', '하루야는 하루가 지나도록 있었다.'),
        '하루야는 하루가 지나도록 있었다.');
    // A term is the translation's to word.
    expect(fix('脇役だ。', '모부다.'), '모부다.');
  });

  test('a name left in kanji, a full name written as one word', () {
    expect(fix('上野で降りた。', '上野에서 내렸다.'), '우에노에서 내렸다.');
    expect(fix('天田照人は黙った。', '아마다테루히토는 입을 다물었다.'),
        '아마다 테루히토는 입을 다물었다.');
    expect(fix('天田照人は黙った。', '테루히토는 입을 다물었다.'),
        '테루히토는 입을 다물었다.');
  });

  test('the name check: letter for letter', () {
    List<String> missed(String source, String translation) =>
        [for (final e in missedNames(source, translation, g)) e.source];
    // It used to pass: the check looked past spaces.
    expect(missed('純太郎は笑った。', '준 타로는 웃었다.'), ['純太郎']);
    expect(missed('純太郎は笑った。', '준타로는 웃었다.'), isEmpty);
    expect(missed('しずくは笑った。', '시즈크는 웃었다.'), ['しずく']);
    // The name read another way.
    expect(missed('風宮は笑った。', '후자미는 웃었다.'), ['風宮']);
    expect(missed('上野で降りた。', '상노에서 내렸다.'), ['上野']);
    // A full name may be called by one of its words.
    expect(missed('天田照人は黙った。', '테루히토는 입을 다물었다.'), isEmpty);
    // What can be set right is, before anything is sent back.
    expect(
        checkTranslation(
            '純太郎は笑った。',
            finishTranslation('준 타로는 웃었다.', '純太郎は笑った。', 'Korean', g),
            glossary: g),
        isEmpty);
  });

  test('other languages are left as they are', () {
    expect(finishTranslation('Jun Taro laughed.', '純太郎は笑った。', 'English', g),
        'Jun Taro laughed.');
  });

  test('translations made before are set right with the glossary', () {
    final made = {
      '純太郎は笑った。': '준 타로는 웃었다.',
      'しずくは頷いた。': '시즈크는 고개를 끄덕였다.',
      '空は青かった。': '하늘은 파랬다.',
      '結奈が来た。': '유나가 왔다.',
    };
    final fixed = repairedNames(
        ['純太郎は笑った。', 'しずくは頷いた。', '空は青かった。', '結奈が来た。', '未翻訳。'],
        (source) => made[source],
        g);
    expect(fixed, {
      '純太郎は笑った。': '준타로는 웃었다.',
      'しずくは頷いた。': '시즈쿠는 고개를 끄덕였다.',
    });
  });

  test('a name half left in kanji is written out', () {
    const g = BookGlossary(complete: true, version: 2, entries: [
      GlossaryEntry(source: '上野', target: '우에노', reading: 'うえの', kind: GlossaryKind.place),
      GlossaryEntry(source: '純太郎', target: '준타로', reading: 'じゅんたろう'),
      GlossaryEntry(source: '天田照人', target: '아마다 테루히토', family: '天田'),
    ]);
    final changes = <(String, String)>[];
    String fix(String source, String t) =>
        enforceGlossary(source, t, g, changes: changes);
    expect(fix('上野に行った。', '上노에 갔다.'), '우에노에 갔다.');
    expect(fix('上野に行った。', '우에野에 갔다.'), '우에노에 갔다.');
    expect(fix('純太郎は頷いた。', '준太郎는 끄덕였다.'), '준타로는 끄덕였다.');
    expect(fix('純太郎は頷いた。', '純타로는 끄덕였다.'), '준타로는 끄덕였다.');
    expect(fix('天田照人が来た。', '天田 테루히토가 왔다.'), '아마다 테루히토가 왔다.');
    expect(changes.first, ('上노', '우에노'));
    expect(fix('天田照人が来た。', '아마다照人이 왔다.'), '아마다 테루히토이 왔다.');
    // The kanji alone, and a word that only begins like the name's end.
    expect(fix('上野に行った。', '上 노래를 불렀다.'), '上 노래를 불렀다.');
    // A kanji the name does not begin with is not this name: left for
    // the check that asks again.
    expect(fix('上野の下に行った。', '下노에 갔다.'), '下노에 갔다.');
    // Not in this paragraph's source: not touched.
    expect(fix('空は青かった。', '上노는 파랬다.'), '上노는 파랬다.');
  });
}
