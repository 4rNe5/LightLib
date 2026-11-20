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

  test(
      'one person, one spelling: a full name and a pet form are written '
      'with the name as the list has it', () {
    final text = [
      for (var i = 0; i < 3; i++) ...[
        '高森結奈は笑った。高森が言い、結奈も頷く。',
        '「結奈りん」と沙羅は呼んだ。「沙羅ちん」と結奈が返す。',
        '風宮佑樹が来た。風宮は黙っていた。',
        '天田照人は走る。天田が叫び、照人は止まった。',
        '神坂しずくは神坂の家にいる。しずくは眠い。',
      ],
    ].join('\n');
    final BookSurvey survey = (
      candidates: const [
        // The book spells these: ゆな alone, the whole of 天田照人.
        GlossaryCandidate(source: '結奈', count: 9, example: '', reading: 'ゆな'),
        GlossaryCandidate(source: '風宮', count: 6, example: '', reading: 'かざみや'),
        GlossaryCandidate(
            source: '天田照人', count: 3, example: '', reading: 'あまだてるひと'),
        GlossaryCandidate(
            source: 'しずく', count: 6, example: '', girlHonorifics: 3),
      ],
      places: const [],
      narration: Narration.thirdPerson,
      hero: null,
      text: text,
    );
    final entries = parseBookAnalysis([
      jsonEncode({
        'entries': [
          // Read ゆいな inside the longer entries, against the book.
          {
            'src': '高森結奈',
            'reading': 'たかもりゆいな',
            'kind': 'person',
            'ko': '타카모리 유이나'
          },
          {'src': '高森', 'reading': 'たかもり', 'kind': 'person', 'ko': '타카모리'},
          {'src': '結奈', 'reading': 'ゆな', 'kind': 'person', 'ko': '유나'},
          {'src': '結奈りん', 'reading': 'ゆいなりん', 'kind': 'nickname', 'ko': '유이나린'},
          {'src': '沙羅', 'reading': 'さら', 'kind': 'person', 'ko': '사라'},
          {'src': '沙羅ちん', 'reading': 'さらちん', 'kind': 'nickname', 'ko': '사라 친'},
          // The family name read another way in the full name.
          {
            'src': '風宮佑樹',
            'reading': 'かぜみやゆうき',
            'kind': 'person',
            'ko': '카제미야 유키'
          },
          {'src': '風宮', 'reading': 'かざみや', 'kind': 'person', 'ko': '카자미야'},
          // The book spells the full name; the given name alone was a guess.
          {
            'src': '天田照人',
            'reading': 'あまだあきと',
            'kind': 'person',
            'ko': '아마다 아키토'
          },
          {'src': '天田', 'reading': 'あまだ', 'kind': 'person', 'ko': '아마다'},
          {'src': '照人', 'reading': 'あきと', 'kind': 'person', 'ko': '아키토'},
          // A family name and a name in hiragana: a full name, not a pet form.
          {
            'src': '神坂しずく',
            'reading': 'かみさかしずく',
            'kind': 'person',
            'ko': '카미사카 시즈쿠'
          },
          {'src': '神坂', 'reading': 'かみさか', 'kind': 'person', 'ko': '카미사카'},
          {'src': 'しずく', 'reading': 'しずく', 'kind': 'person', 'ko': '시즈쿠'},
        ]
      }),
    ], survey);
    final by = {
      for (final e in mergeGlossary(BookGlossary.empty, entries).entries)
        e.source: e.target,
    };
    expect(by['結奈'], '유나');
    expect(by['高森結奈'], '타카모리 유나');
    expect(by['結奈りん'], '유나린');
    expect(by['沙羅ちん'], '사라친');
    expect(by['風宮佑樹'], '카자미야 유키');
    expect(by['天田照人'], '아마다 테루히토');
    expect(by['照人'], '테루히토');
    expect(by['神坂しずく'], '카미사카 시즈쿠');
  });

  test(
      'a glossary made before that rule is set right by it, the reader\'s '
      'own entries followed and never changed', () {
    final text = [
      for (var i = 0; i < 3; i++) '高森結奈は笑った。高森が言い、結奈も頷く。「結奈りん」と呼ばれた。',
    ].join('\n');
    final BookSurvey survey = (
      candidates: const [
        GlossaryCandidate(
            source: '高森結奈', count: 3, example: '', familyLength: 2),
        GlossaryCandidate(source: '高森', count: 6, example: ''),
        GlossaryCandidate(source: '結奈', count: 9, example: ''),
        GlossaryCandidate(source: '結奈りん', count: 3, example: ''),
      ],
      places: const [],
      narration: Narration.thirdPerson,
      hero: null,
      text: text,
    );
    GlossaryEntry name(String source, String target,
            {bool edited = false, String? family}) =>
        GlossaryEntry(
            source: source,
            target: target,
            kind: GlossaryKind.person,
            edited: edited,
            family: family);
    final old = BookGlossary(entries: [
      name('高森結奈', '타카모리 유이나', family: '高森'),
      name('高森', '타카모리'),
      // The reader's word.
      name('結奈', '유나', edited: true),
      name('結奈りん', '유이나린'),
    ], complete: true, version: 2);
    final now = upgradeGlossary(old, survey);
    final by = {for (final e in now.entries) e.source: e};
    expect(now.version, BookGlossary.currentVersion);
    expect(by['高森結奈']!.target, '타카모리 유나');
    expect(by['結奈りん']!.target, '유나린');
    expect(by['結奈']!.target, '유나');
    expect(by['結奈']!.edited, isTrue);

    // A full name the engine cut itself, which the book never shortens:
    // still two words after the glossary is gone through again.
    final cut = upgradeGlossary(
        BookGlossary(entries: [
          name('岸本和葉', '키시모토 카즈하', family: ''),
        ], complete: true, version: 2),
        (
          candidates: const [
            GlossaryCandidate(source: '岸本和葉', count: 4, example: ''),
          ],
          places: const [],
          narration: Narration.thirdPerson,
          hero: null,
          text: '岸本和葉が来た。',
        ));
    expect(cut.entries.single.target, '키시모토 카즈하');

    // The reader set the full name too: it stands as set.
    final kept = upgradeGlossary(
        BookGlossary(entries: [
          name('高森結奈', '다카모리 유이나', edited: true, family: '高森'),
          name('高森', '타카모리'),
          name('結奈', '유나'),
        ], complete: true, version: 2),
        survey);
    expect(
        kept.entries.firstWhere((e) => e.source == '高森結奈').target, '다카모리 유이나');
  });

  test('what someone is, is not who: a title many share is no name, nor '
      'is a way of addressing', () {
    final text = [
      for (var i = 0; i < 3; i++) ...[
        '青の魔女は笑った。「魔女さん」と呼ばれて魔女は振り向く。',
        '花の魔女と地獄の魔女が魔女集会に来た。',
        '「しずくちゃん」「ちゃん付けはやめて」としずくは言った。',
        '青の騎士団が来た。騎士団は強い。',
      ],
    ].join('\n');
    final BookSurvey survey = (
      candidates: const [
        GlossaryCandidate(source: '魔女', count: 12, example: '', girlHonorifics: 3),
        GlossaryCandidate(source: 'しずく', count: 6, example: '', girlHonorifics: 3),
      ],
      places: const [],
      narration: Narration.firstPerson,
      hero: null,
      text: text,
    );
    final entries = parseBookAnalysis([
      jsonEncode({
        'entries': [
          // "The" witch, to the engine: one of the book's many.
          {'src': '魔女', 'reading': '', 'kind': 'person', 'ko': '푸른 마녀', 'gender': 'female'},
          {'src': '青の魔女', 'reading': '', 'kind': 'nickname', 'ko': '푸른 마녀', 'gender': 'female'},
          {'src': 'ちゃん', 'reading': '', 'kind': 'person', 'ko': '찬'},
          {'src': 'しずく', 'reading': 'しずく', 'kind': 'person', 'ko': '시즈쿠'},
          // Written as the longer entry is: that one's translation.
          {'src': '騎士団', 'reading': '', 'kind': 'organisation', 'ko': '푸른 기사단'},
          {'src': '青の騎士団', 'reading': '', 'kind': 'organisation', 'ko': '푸른 기사단'},
        ]
      }),
    ], survey);
    final by = {
      for (final e in mergeGlossary(BookGlossary.empty, entries).entries)
        e.source: e.target,
    };
    expect(by.containsKey('魔女'), isFalse);
    expect(by.containsKey('ちゃん'), isFalse);
    expect(by.containsKey('騎士団'), isFalse);
    expect(by.keys.toSet(), {'青の魔女', 'しずく', '青の騎士団'});
  });

  test('a glossary that lists what someone is as who: set right without '
      'a model, the reader\'s own word kept, nothing brought back by the '
      'series', () {
    final text = [
      for (var i = 0; i < 3; i++)
        '青の魔女は笑った。魔女は振り向く。「しずくちゃん」としずくは言った。',
    ].join('\n');
    final BookSurvey survey = (
      candidates: const [
        GlossaryCandidate(source: '魔女', count: 6, example: ''),
        GlossaryCandidate(source: 'しずく', count: 6, example: '', girlHonorifics: 3),
      ],
      places: const [],
      narration: Narration.firstPerson,
      hero: null,
      text: text,
    );
    GlossaryEntry name(String source, String target, {bool edited = false}) =>
        GlossaryEntry(
            source: source,
            target: target,
            kind: GlossaryKind.person,
            edited: edited);
    final now = upgradeGlossary(
        BookGlossary(entries: [
          name('魔女', '푸른마녀'),
          name('ちゃん', '찬'),
          name('しずく', '시즈쿠'),
        ], complete: true, version: 3),
        survey);
    expect(now.version, BookGlossary.currentVersion);
    expect(now.entries.map((e) => e.source), ['しずく']);

    final set = upgradeGlossary(
        BookGlossary(entries: [
          name('魔女', '마녀', edited: true),
          name('しずく', '시즈쿠'),
        ], complete: true, version: 3),
        survey);
    expect(set.entries.firstWhere((e) => e.source == '魔女').target, '마녀');

    // Another volume, not gone through again yet, still lists them.
    final other = BookGlossary(entries: [
      name('魔女', '푸른마녀'),
      name('ちゃん', '찬'),
    ], complete: true, version: 3);
    expect(inheritSeries(now, [other], text).entries.map((e) => e.source),
        ['しずく']);
    // What the reader set there is taken as before.
    final theirs = BookGlossary(
        entries: [name('魔女', '마녀', edited: true)],
        complete: true,
        version: 3);
    expect(
        inheritSeries(now, [theirs], text)
            .entries
            .firstWhere((e) => e.source == '魔女')
            .target,
        '마녀');
  });

  test('a description someone goes by is words: as the engine translated '
      'it, not spelled from its reading and not joined', () {
    final text = [
      for (var i = 0; i < 3; i++)
        '青の魔女と八王子の魔女が来た。オコジョ教授は入間の魔法使いに会う。'
            '神坂しずくも来た。神坂は笑い、しずくは頷く。',
    ].join('\n');
    final BookSurvey survey = (
      candidates: const [
        GlossaryCandidate(source: 'しずく', count: 6, example: '', girlHonorifics: 3),
      ],
      places: const [],
      narration: Narration.firstPerson,
      hero: null,
      text: text,
    );
    final entries = parseBookAnalysis([
      jsonEncode({
        'entries': [
          {'src': '青の魔女', 'reading': 'あおのまじょ', 'kind': 'nickname', 'ko': '푸른 마녀', 'gender': 'female'},
          {'src': '八王子の魔女', 'reading': 'はちおうじのまじょ', 'kind': 'person', 'ko': '하치오지의 마녀'},
          {'src': 'オコジョ教授', 'reading': 'おこじょきょうじゅ', 'kind': 'person', 'ko': '오코조 교수'},
          {'src': '入間の魔法使い', 'reading': 'いるまのまほうつかい', 'kind': 'nickname', 'ko': '이루마의  마법사'},
          // A real full name is still two names, by its parts.
          {'src': '神坂しずく', 'reading': 'かみさかしずく', 'kind': 'person', 'ko': '카미사카 시즈쿠'},
          {'src': '神坂', 'reading': 'かみさか', 'kind': 'person', 'ko': '카미사카'},
          {'src': 'しずく', 'reading': 'しずく', 'kind': 'person', 'ko': '시즈쿠'},
        ]
      }),
    ], survey);
    final by = {
      for (final e in mergeGlossary(BookGlossary.empty, entries).entries)
        e.source: e,
    };
    expect(by['青の魔女']!.target, '푸른 마녀');
    expect(by['青の魔女']!.gender, GlossaryGender.female);
    expect(by['八王子の魔女']!.target, '하치오지의 마녀');
    expect(by['オコジョ教授']!.target, '오코조 교수');
    expect(by['入間の魔法使い']!.target, '이루마의 마법사');
    expect(by['神坂しずく']!.target, '카미사카 시즈쿠');
    expect(isTitle('純太郎'), isFalse);
    expect(isTitle('ののか'), isFalse);
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
