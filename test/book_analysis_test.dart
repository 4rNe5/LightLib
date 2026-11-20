// The book read whole by Gemini (its answers checked against the book),
// and what a series' other volumes settled carried over.

// Dart imports:
import 'dart:convert';

// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/services/translation/book_glossary.dart';
import 'package:openlib/services/translation/series_glossary.dart';

void main() {
  final text = [
    for (var i = 0; i < 3; i++) ...[
      '風宮は笑った。風宮が言う。',
      'しずくは聖剣を抜いた。聖剣が光る。',
      '結奈りんと呼ばれて結奈は怒った。',
      '栄華高校の門をくぐる。',
      'クラスのみんなが見ていた。',
    ],
    '一度きりの言葉。',
  ].join('\n');
  final BookSurvey survey = (
    candidates: const [
      GlossaryCandidate(source: '結奈', count: 6, example: '', reading: 'ゆな'),
      GlossaryCandidate(source: 'しずく', count: 3, example: '', girlHonorifics: 3),
    ],
    places: const [],
    narration: Narration.thirdPerson,
    hero: null,
    text: text,
  );
  String answer(List<Map<String, String>> entries) =>
      jsonEncode({'entries': entries});

  test('names the book has, written as the book has them', () {
    final entries = parseBookAnalysis([
      answer([
        // No furigana, no honorific: only reading the book finds it.
        {'src': '風宮', 'reading': 'かざみや', 'kind': 'person', 'ko': '후자미', 'gender': 'male', 'speech': 'casual, blunt'},
        // The book reads it ゆな: not the engine's 유우나.
        {'src': '結奈', 'reading': 'ゆうな', 'kind': 'person', 'ko': '유우나', 'gender': 'female', 'speech': '-'},
        // "A drop" to the engine; the girl called しずくちゃん to the book.
        {'src': 'しずく', 'reading': 'しずく', 'kind': 'term', 'ko': '물방울', 'gender': '-', 'speech': '-'},
        {'src': '結奈りん', 'reading': 'ゆなりん', 'kind': 'nickname', 'ko': '유나링', 'gender': 'female', 'speech': '-'},
        {'src': '栄華高校', 'reading': 'えいがこうこう', 'kind': 'organisation', 'ko': '에이카 고교', 'gender': '-', 'speech': '-'},
        {'src': '聖剣', 'reading': 'せいけん', 'kind': 'item', 'ko': '성검', 'gender': '-', 'speech': '-'},
      ]),
      'not json',
      answer([
        // Said again by a later part of the book: the first stands.
        {'src': '風宮', 'reading': 'ふうみや', 'kind': 'person', 'ko': '후미야'},
        // Not in the book, in it once, an everyday loanword, no Korean.
        {'src': '山田', 'reading': 'やまだ', 'kind': 'person', 'ko': '야마다'},
        {'src': '一度', 'reading': 'いちど', 'kind': 'term', 'ko': '한 번'},
        {'src': 'クラス', 'reading': 'クラス', 'kind': 'term', 'ko': '반'},
        {'src': '門', 'reading': 'もん', 'kind': 'place', 'ko': '문'},
        {'src': '聖剣', 'reading': 'せいけん', 'kind': 'item', 'ko': '聖剣'},
      ]),
    ], survey);
    final by = {for (final e in entries) e.source: e};
    expect(by.keys.toSet(), {'風宮', '結奈', 'しずく', '結奈りん', '栄華高校', '聖剣'});
    expect(by['風宮']!.target, '카자미야');
    expect(by['風宮']!.reading, 'かざみや');
    expect(by['風宮']!.gender, GlossaryGender.male);
    expect(by['風宮']!.speech, 'casual, blunt');
    expect(by['結奈']!.target, '유나');
    expect(by['しずく']!.target, '시즈쿠');
    expect(by['しずく']!.kind, GlossaryKind.person);
    // Called 〜ちゃん in the book.
    expect(by['しずく']!.gender, GlossaryGender.female);
    expect(by['結奈りん']!.target, '유나린');
    expect(by['結奈りん']!.kind, GlossaryKind.person);
    expect(by['栄華高校']!.target, '에이가 고등학교');
    expect(by['栄華高校']!.kind, GlossaryKind.place);
    expect(by['聖剣']!.target, '성검');
    expect(by['聖剣']!.kind, GlossaryKind.term);
  });

  test('names as an engine lists them, kept as names are kept here', () {
    final text = [
      for (var i = 0; i < 3; i++) ...[
        '神坂しずくは笑った。神坂は頷き、しずくも頷いた。',
        '「純くん」と呼ばれて純太郎は振り向いた。純は黙っていた。',
        '岸本和葉が宿直室に入る。',
        '玲子さんは喫茶メロウの前に立った。玲子は笑う。',
        '御影は横浜駅で降りた。',
      ],
    ].join('\n');
    final BookSurvey survey = (
      candidates: const [
        GlossaryCandidate(source: 'しずく', count: 6, example: '', girlHonorifics: 4),
        GlossaryCandidate(source: '純', count: 6, example: '', boyHonorifics: 3),
        GlossaryCandidate(source: '純太郎', count: 3, example: '', reading: 'じゅんたろう'),
        GlossaryCandidate(source: 'イルカ', count: 7, example: ''),
        GlossaryCandidate(source: 'アキラ', count: 9, example: '', girlHonorifics: 5),
        GlossaryCandidate(source: '噂', count: 9, example: '', reading: 'うわさ'),
      ],
      places: const [],
      narration: Narration.firstPerson,
      hero: null,
      text: text,
    );
    final entries = parseBookAnalysis([
      jsonEncode({
        'entries': [
          {'src': '神坂しずく', 'reading': 'かみさかしずく', 'kind': 'person', 'ko': '카미사카 시즈쿠'},
          {'src': '神坂', 'reading': 'かみさか', 'kind': 'person', 'ko': '카미사카'},
          {'src': 'しずく', 'reading': 'しずく', 'kind': 'person', 'ko': '시즈쿠'},
          // With how they are addressed: the name alone is the entry.
          {'src': 'しずくちゃん', 'reading': 'しずくちゃん', 'kind': 'nickname', 'ko': '시즈쿠 양'},
          {'src': '純くん', 'reading': 'じゅんくん', 'kind': 'nickname', 'ko': '준 군'},
          {'src': '玲子さん', 'reading': 'れいこさん', 'kind': 'nickname', 'ko': '레이코 씨'},
          {'src': '玲子', 'reading': 'れいこ', 'kind': 'person', 'ko': '레이코'},
          // A given name of three kanji, cut by mistake: never two names.
          {'src': '純太郎', 'reading': 'じゅんたろう', 'kind': 'person', 'ko': '준 타로'},
          // A full name the book never shortens: the engine's cut stands.
          {'src': '岸本和葉', 'reading': 'きしもとかずは', 'kind': 'person', 'ko': '키시모토 카즈하'},
          // Kana slipped into the Korean: the reading tells.
          {'src': '御影', 'reading': 'みかげ', 'kind': 'person', 'ko': '미카げ'},
          // Translated, not spelled: an ordinary word, in its Korean.
          {'src': '宿直室', 'reading': 'しゅくちょくしつ', 'kind': 'place', 'ko': '숙직실'},
          {'src': '喫茶メロウ', 'reading': 'きっさめろう', 'kind': 'organisation', 'ko': '카페 멜로우'},
          {'src': '横浜駅', 'reading': 'よこはまえき', 'kind': 'place', 'ko': '요코하마 역'},
        ]
      }),
    ], survey);
    final glossary = mergeGlossary(BookGlossary.empty, entries);
    final by = {for (final e in glossary.entries) e.source: e};
    expect(by.keys.toSet(), {
      '神坂しずく', '神坂', 'しずく', '玲子', '純太郎', '岸本和葉', '御影',
      '宿直室', '喫茶メロウ', '横浜駅',
    });
    expect(by['神坂しずく']!.target, '카미사카 시즈쿠');
    expect(by['神坂しずく']!.family, '神坂');
    expect(by['純太郎']!.target, '준타로');
    expect(by['岸本和葉']!.target, '키시모토 카즈하');
    expect(by['御影']!.target, '미카게');
    expect(by['宿直室']!.target, '숙직실');
    expect(by['宿直室']!.kind, GlossaryKind.term);
    expect(by['喫茶メロウ']!.target, '카페 멜로우');
    expect(by['横浜駅']!.target, '요코하마 역');
    expect(by['横浜駅']!.kind, GlossaryKind.place);
    // Made again from what was saved: the same.
    final again = BookGlossary.decode(glossary.encode());
    expect(tidyNames(again.entries).map((e) => e.target),
        glossary.entries.map((e) => e.target));

    // What is still asked: the people the reading left out, and not a
    // katakana word nobody is addressed by.
    expect(unnamedCandidates(survey, entries).map((c) => c.source),
        ['純', 'アキラ', '噂']);
    // No reading: everything is asked, as before.
    expect(unnamedCandidates(survey, const []).length, 6);
  });

  test('the book in parts, cut between paragraphs', () {
    final chunks = bookAnalysisChunks(
        [for (var i = 0; i < 10; i++) 'あ' * 40].join('\n'),
        size: 100);
    expect(chunks.length, 5);
    expect(chunks.every((c) => c.trim().split('\n').length == 2), isTrue);
    expect(bookAnalysisChunks('あ\nい', size: 100), ['あ\nい\n']);
    expect(
        bookAnalysisChunks([for (var i = 0; i < 50; i++) 'あ' * 90].join('\n'),
                size: 100, most: 3)
            .length,
        3);
  });

  test('what another volume settled carries over', () {
    const mine = BookGlossary(complete: true, entries: [
      // Volume 1 gives 風宮 no furigana: the model read it wrong.
      GlossaryEntry(source: '風宮', target: '후자미'),
      GlossaryEntry(source: '結奈', target: '유나', reading: 'ゆな'),
      GlossaryEntry(source: '凜', target: '링', edited: true),
    ]);
    const volume2 = BookGlossary(complete: true, entries: [
      GlossaryEntry(source: '風宮', target: '카자미야', reading: 'かざみや'),
      // This book reads the name itself: its own way stands.
      GlossaryEntry(source: '結奈', target: '유우나'),
      // The reader's choice here is not undone by another volume.
      GlossaryEntry(source: '凜', target: '린', reading: 'りん'),
      GlossaryEntry(source: '小野井', target: '오노이', reading: 'おのい'),
      // Not in this book.
      GlossaryEntry(source: '高森', target: '타카모리', reading: 'たかもり'),
      // A term is each book's own.
      GlossaryEntry(source: '聖剣', target: '성검', kind: GlossaryKind.term),
    ]);
    final now = inheritSeries(
        mine, [volume2], '風宮と結奈と凜と小野井が聖剣を見た。');
    final target = {for (final e in now.entries) e.source: e.target};
    expect(target, {
      '風宮': '카자미야',
      '結奈': '유나',
      '凜': '링',
      '小野井': '오노이',
    });
    // Nothing to take: the same glossary.
    expect(identical(inheritSeries(now, [volume2], '風宮'), now), isTrue);
  });

  test('the other volumes of a series, by title', () {
    const titles = {
      'a1.epub': 'なぜかＳ級美女達の話題に俺があがる件',
      'a2.epub': 'なぜかＳ級美女達の話題に俺があがる件２【電子特別版】',
      'a5.epub': 'なぜかS級美女達の話題に俺があがる件5【電子特別版】 (角川スニーカー文庫)',
      'b1.epub': '俺がシフトの時だけバイト先の喫茶店に来る、クラスの美少女モデル様',
      'b2.epub': '俺がシフトの時だけバイト先の喫茶店に来る、クラスの美少女モデル様 2 (GA文庫)',
      'c.epub': '死亡遊戯で飯を食う。 10 (MF文庫J)',
    };
    expect(sameSeries('a1.epub', titles).toSet(), {'a2.epub', 'a5.epub'});
    expect(sameSeries('b2.epub', titles), ['b1.epub']);
    expect(sameSeries('c.epub', titles), isEmpty);
    expect(sameSeries('missing.epub', titles), isEmpty);
  });
}
