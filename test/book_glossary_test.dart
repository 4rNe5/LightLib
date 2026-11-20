// A book's glossary: candidates from its text, the model's answer read
// into entries, names spelled from their readings, the reader's edits
// kept, and only the entries a request needs sent with it.

// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/services/translation/book_glossary.dart';
import 'package:openlib/services/translation/glossary_service.dart';
import 'package:openlib/services/translation/translation_models.dart';
import 'package:openlib/services/translation/translation_qa.dart';

void main() {
  test('names spelled from their kana the way editions write them', () {
    expect(kanaToHangul('かずき'), '카즈키');
    expect(kanaToHangul('しょうた'), '쇼타');
    expect(kanaToHangul('ゆうき'), '유키');
    expect(kanaToHangul('いっせい'), '잇세이');
    expect(kanaToHangul('けんた'), '켄타');
    expect(kanaToHangul('りょうま'), '료마');
    expect(kanaToHangul('ヒダカ'), '히다카');
    expect(kanaToHangul('じゅんいち'), '준이치');
  });

  test('candidates: furigana names, names before honorifics, katakana', () {
    final paragraphs = [
      for (var i = 0; i < 4; i++) '「和希くん、おはよう」と命が言った。',
      for (var i = 0; i < 5; i++) 'シャーロットさんは笑った。',
      '天田は黙っていた。天田は笑った。',
      '「命、行こう」',
      '彼女の瞳が揺れた。瞳は潤んでいた。',
    ];
    final c = glossaryCandidates(
        paragraphs,
        {'和希': 'かずき', '命': 'みこと', '天田': 'あまだ', '鞄': 'かばん', '瞳': 'ひとみ'});
    // (鞄 is never in the text: no candidate.)
    final sources = [for (final x in c) x.source];
    expect(sources, containsAll(['和希', 'シャーロット', '天田']));
    // One kanji with a name-like reading is a candidate when someone is
    // called by it (「命、」); 瞳 is only ever an eye.
    expect(sources, contains('命'));
    expect(sources, isNot(contains('瞳')));
    expect(sources, isNot(contains('鞄')));
    expect(c.firstWhere((x) => x.source == '和希').reading, 'かずき');
    expect(c.first.example, isNotEmpty);
  });

  test('candidates: no katakana pronouns, no verb stems, one-kanji names',
      () {
    final paragraphs = [
      for (var i = 0; i < 5; i++) '「ワタシはシエスタの助手よ。アナタは誰？」',
      for (var i = 0; i < 4; i++) '「ありがとう、唯ちゃん」と彼女は呟いた。',
      'シエスタ',
    ];
    final c = glossaryCandidates(paragraphs, {'呟': 'つぶや'});
    final sources = [for (final x in c) x.source];
    expect(sources, containsAll(['シエスタ', '唯']));
    expect(sources, isNot(contains('ワタシ')));
    expect(sources, isNot(contains('アナタ')));
    // 呟 is always 呟いた: a verb, not a name.
    expect(sources, isNot(contains('呟')));
    // The example says more than the bare word.
    expect(c.firstWhere((x) => x.source == 'シエスタ').example,
        'named: 「ワタシはシエスタの助手よ。アナタは誰？」');
    // A line the next sentence gives to the person shows how they talk.
    final said = glossaryCandidates([
      for (var i = 0; i < 3; i++) ...['「おはようございます、藤宮さん」', '真昼は小さく微笑んだ。'],
    ], {'真昼': 'まひる'});
    expect(said.firstWhere((x) => x.source == '真昼').example,
        'says: 「おはようございます、藤宮さん」 / story: 真昼は小さく微笑んだ。');
    expect(c.firstWhere((x) => x.source == '唯').girlHonorifics, 4);
    // 藤宮 of 藤宮周 is called as 周 is: 周くん, so a boy.
    final family = glossaryCandidates([
      for (var i = 0; i < 3; i++) '「周くん、おはよう」と藤宮周は言われた。藤宮は笑った。',
    ], {'周': 'あまね', '藤宮': 'ふじみや'});
    expect(family.firstWhere((x) => x.source == '藤宮').boyHonorifics, 3);
  });

  test('the model sorts and names them; a far-off name yields to the reading',
      () {
    final candidates = [
      const GlossaryCandidate(source: '石井和希', reading: 'いしいかずき', count: 9, example: ''),
      const GlossaryCandidate(source: '氷高', reading: 'ひだか', count: 9, example: '', girlHonorifics: 3),
      const GlossaryCandidate(source: '脇役', reading: 'モブ', count: 9, example: ''),
      const GlossaryCandidate(source: 'スマホ', count: 3, example: ''),
      const GlossaryCandidate(source: 'ラブコメ', count: 30, example: ''),
      const GlossaryCandidate(source: 'ニコニコ', count: 30, example: ''),
      const GlossaryCandidate(source: 'ユズ', count: 9, example: ''),
      const GlossaryCandidate(source: '眼差', reading: 'まなざ', count: 9, example: ''),
      const GlossaryCandidate(source: '風靡', reading: 'ふうび', count: 9, example: ''),
      const GlossaryCandidate(source: '夏凪', reading: 'なつなぎ', count: 9, example: ''),
    ];
    final entries = parseGlossaryAnswer(
        '[1] 이시이 카즈키 | person | male | casual, cheerful\n'
        '[2] 히다카 미코토 씨 | person | male\n'
        '[3] 모브 | term | -\n'
        '[4] 스마트폰 | term | -\n'
        '[5] 러브코미디 | term | -\n'
        '[6] 방긋방긋 | term | -\n'
        '[7] 유즈 | person | female\n'
        '[8] 눈빛 | term | -\n'
        '[9] 풍미 | person | female\n'
        '[10] 나쓰나기 | person | female\n'
        'noise',
        candidates);
    final bySource = {for (final e in entries) e.source: e};
    expect(bySource['石井和希']!.target, '이시이 카즈키');
    expect(bySource['石井和希']!.gender, GlossaryGender.male);
    expect(bySource['石井和希']!.speech, 'casual, cheerful');
    expect(bySource['石井和希']!.promptLine,
        '石井和希 = 이시이 카즈키 (male, speaks: casual, cheerful)');
    // Two syllables off the reading: the reading wins.
    expect(bySource['氷高']!.target, '히다카');
    // Called 〜ちゃん three times: female, whatever the model said.
    expect(bySource['氷高']!.gender, GlossaryGender.female);
    expect(bySource['脇役']!.kind, GlossaryKind.term);
    // A loanword used now and then, or a word with its usual reading
    // (眼差 まなざ), needs no fixed form.
    expect(bySource.containsKey('スマホ'), isFalse);
    expect(bySource['ユズ']!.target, '유즈');
    expect(bySource.containsKey('眼差'), isFalse);
    // A loanword is left to the translation, however often it comes.
    expect(bySource.containsKey('ラブコメ'), isFalse);
    expect(bySource.containsKey('ニコニコ'), isFalse);
    // The kanji's meaning, not its reading: the reading wins. So it does
    // over the model's own spelling of the same reading: names are
    // written one way (つ is 츠), whatever the model prefers.
    expect(bySource['風靡']!.target, '후비');
    expect(bySource['夏凪']!.target, '나츠나기');
  });

  test('full names split after the family name; edits survive a remake', () {
    final made = mergeGlossary(BookGlossary.empty, const [
      GlossaryEntry(source: '天田', target: '아마다', kind: GlossaryKind.person),
      GlossaryEntry(
          source: '天田照人',
          target: '아마다테루히토',
          kind: GlossaryKind.person,
          family: '天田'),
    ]);
    expect(made.entries.firstWhere((e) => e.source == '天田照人').target,
        '아마다 테루히토');
    expect(made.version, BookGlossary.currentVersion);
    final family = tidyNames(const [
      GlossaryEntry(source: '氷高', target: '히다카', kind: GlossaryKind.person,
          gender: GlossaryGender.male),
      GlossaryEntry(source: '氷高命', target: '히다카 미코토', kind: GlossaryKind.person,
          gender: GlossaryGender.female),
    ]);
    expect(family.first.gender, GlossaryGender.female);
    final edited = BookGlossary(entries: [
      ...made.entries,
      const GlossaryEntry(source: '和希', target: '가즈키', edited: true),
    ]);
    final again = mergeGlossary(edited, const [
      GlossaryEntry(source: '和希', target: '카즈키'),
    ]);
    expect(again.entries.firstWhere((e) => e.source == '和希').target, '가즈키');
    expect(again.entries.any((e) => e.source == '天田'), isTrue);
  });

  test('a short form of a given name is no family name: 준타로 stays whole',
      () {
    // The owner's book: 純くん is 純太郎, and the glossary cut his name
    // in two (준 타로) 120 times over.
    final tidy = tidyNames(const [
      GlossaryEntry(source: '純', target: '준'),
      GlossaryEntry(source: '純太郎', target: '준타로', reading: 'じゅんたろう'),
    ]);
    expect(tidy.last.target, '준타로');
    // Nor where the model itself wrote the space.
    const c = GlossaryCandidate(
        source: '純太郎', count: 147, example: '', reading: 'じゅんたろう');
    final parsed =
        parseGlossaryAnswer('[1] 준 타로 | person | male | casual', const [c]);
    expect(tidyNames(parsed).single.target, '준타로');
    // A full name the book shows to be two names keeps the model's cut,
    // with no entry for the family name to cut it by.
    const full = GlossaryCandidate(
        source: '石井和希',
        count: 9,
        example: '',
        reading: 'いしいかずき',
        familyLength: 2);
    final two = parseGlossaryAnswer('[1] 이시이 카즈키 | person | male', const [full]);
    expect(two.single.family, '石井');
    expect(tidyNames(two).single.target, '이시이 카즈키');
    // Saved and read back, it is still known as two names.
    expect(GlossaryEntry.fromJson(two.single.toJson())!.family, '石井');
  });

  test('candidates: where a full name is cut, the book tells', () {
    final book = [
      for (var i = 0; i < 4; i++) '「純くん、おはよう」と言われて純太郎は笑った。',
      for (var i = 0; i < 3; i++) '天田照人は黙っていた。「照人くん」と天田さんは呼ばれた。',
      for (var i = 0; i < 3; i++) '佐藤花子は教師だ。「佐藤さん」「佐藤先生」',
    ];
    final c = glossaryCandidates(book, {
      '純太郎': 'じゅんたろう',
      '天田照人': 'あまだてるひと',
      '佐藤花子': 'さとうはなこ',
    });
    int? cut(String source) =>
        c.firstWhere((x) => x.source == source).familyLength;
    // 太郎 is never used alone, and 純 is a pet name (純くん).
    expect(cut('純太郎'), isNull);
    // 照人 is used alone.
    expect(cut('天田照人'), 2);
    // 花子 never is, but 佐藤 is how she is formally addressed.
    expect(cut('佐藤花子'), 2);
  });

  test('candidates: a name written in hiragana; everyday loanwords left out',
      () {
    final book = [
      for (var i = 0; i < 5; i++) '「しずくちゃん、おはよう」しずくは笑った。しずくの声がした。',
      for (var i = 0; i < 6; i++) 'クラスでデートの話をした。たくさんのメッセージが来た。',
      for (var i = 0; i < 5; i++) 'シエスタは眠っている。みなさんも眠い。',
    ];
    final sources = [for (final x in glossaryCandidates(book, const {})) x.source];
    expect(sources, containsAll(['しずく', 'シエスタ']));
    // たくさん and みなさん are no one's name; クラス, デート and メッセージ
    // are words every story has.
    for (final word in ['たく', 'みな', 'クラス', 'デート', 'メッセージ']) {
      expect(sources, isNot(contains(word)), reason: word);
    }
    final shizuku = glossaryCandidates(book, const {})
        .firstWhere((x) => x.source == 'しずく');
    expect(shizuku.girlHonorifics, 5);
    // Her Korean needs no model: the book writes how she is called.
    final named = parseGlossaryAnswer('[1] 시즈크 | person | female', [shizuku]);
    expect(named.single.target, '시즈쿠');
  });

  test('names with a common noun at the end, and places Korean names itself',
      () {
    // The owner's book: 栄華高校 came out 에이가코코.
    expect(spellName('栄華高校', 'えいがこうこう'), '에이가 고등학교');
    expect(spellName('桜ヶ丘駅', 'さくらがおかえき'), '사쿠라가오카 역');
    expect(spellName('東京', 'とうきょう'), '도쿄');
    expect(spellName('結奈', 'ゆな'), '유나');
    // Nothing but the noun is not a name ending in it.
    expect(spellName('高校', 'こうこう'), '코코');
    const school = GlossaryCandidate(
        source: '栄華高校', count: 15, example: '', reading: 'えいがこうこう');
    expect(
        parseGlossaryAnswer('[1] 에이카 고등학교 | place | -', const [school])
            .single
            .target,
        '에이가 고등학교');
    // Well-known places the book gives no reading: found in the text,
    // no model asked. 石川先生 is a person, not the prefecture.
    final places = knownPlaces([
      '上野で降りた。上野に人が多い。',
      '東京に来た。東京から帰る。',
      '石川先生が来た。石川に行く石川先生は笑った。石川で会う。',
      '渋谷に一度だけ。',
      // An everyday word that is also a prefecture's name.
      '大分慣れた。大分に良くなった。大分で暮らす。',
    ]);
    expect({for (final p in places) p.source: p.target},
        {'上野': '우에노', '東京': '도쿄'});
    expect(places.every((p) => p.kind == GlossaryKind.place), isTrue);
  });

  test('a glossary made before is set right from the book, no model asked',
      () {
    final old = BookGlossary.fromJson({
      'version': 1,
      'complete': true,
      'narration': 'firstPerson',
      'entries': [
        {'source': '純', 'target': '준', 'kind': 'person', 'gender': 'male'},
        {'source': '純太郎', 'target': '준 타로', 'reading': 'じゅんたろう', 'kind': 'person', 'gender': 'male'},
        {'source': '栄華高校', 'target': '에이가코코', 'reading': 'えいがこうこう', 'kind': 'place', 'gender': 'unknown'},
        {'source': '結奈', 'target': '유우나', 'reading': 'ゆな', 'kind': 'person', 'gender': 'female'},
        {'source': '凜', 'target': '링', 'kind': 'person', 'gender': 'female', 'edited': true},
        {'source': '天田照人', 'target': '아마다 테루히토', 'reading': 'あまだてるひと', 'kind': 'person', 'gender': 'male'},
        {'source': '天田', 'target': '아마다', 'reading': 'あまだ', 'kind': 'person', 'gender': 'male'},
      ],
    });
    expect(old.version, 1);
    const survey = (
      candidates: [
        GlossaryCandidate(source: '純', count: 47, example: '', boyHonorifics: 43),
        GlossaryCandidate(source: '純太郎', count: 147, example: '', reading: 'じゅんたろう'),
        GlossaryCandidate(source: '栄華高校', count: 15, example: '', reading: 'えいがこうこう'),
        GlossaryCandidate(source: '結奈', count: 79, example: '', reading: 'ゆな'),
        GlossaryCandidate(source: '凜', count: 101, example: ''),
        GlossaryCandidate(source: '天田照人', count: 9, example: '', reading: 'あまだてるひと', familyLength: 2),
        GlossaryCandidate(source: '天田', count: 20, example: '', reading: 'あまだ'),
        GlossaryCandidate(source: 'しずく', count: 546, example: '', girlHonorifics: 45),
      ],
      places: [
        GlossaryEntry(source: '上野', target: '우에노', reading: 'うえの', kind: GlossaryKind.place),
      ],
      narration: Narration.firstPerson,
      hero: null,
      text: '',
    );
    final now = upgradeGlossary(old, survey);
    final target = {for (final e in now.entries) e.source: e.target};
    expect(now.version, BookGlossary.currentVersion);
    expect(now.complete, isTrue);
    expect(now.narration, Narration.firstPerson);
    expect(target['純太郎'], '준타로');
    expect(target['栄華高校'], '에이가 고등학교');
    expect(target['結奈'], '유나');
    // The reader's own choice is not touched.
    expect(target['凜'], '링');
    expect(target['天田照人'], '아마다 테루히토');
    expect(target['しずく'], '시즈쿠');
    expect(now.entries.firstWhere((e) => e.source == 'しずく').gender,
        GlossaryGender.female);
    expect(target['上野'], '우에노');
    // Twice changes nothing more.
    expect(upgradeGlossary(now, survey).encode(), now.encode());
  });

  test('a request gets the entries its text contains, longest first', () {
    const g = BookGlossary(entries: [
      GlossaryEntry(source: '和希', target: '카즈키', gender: GlossaryGender.male),
      GlossaryEntry(source: '石井和希', target: '이시이 카즈키'),
      GlossaryEntry(source: '命', target: '목숨', kind: GlossaryKind.term),
      GlossaryEntry(source: '周', target: '아마네'),
      GlossaryEntry(source: '月山', target: ''),
    ]);
    final hits = g.inTexts(['石井和希は命を守った。月山と周']);
    // A one-kanji word is left out; a one-kanji name goes, marked as one.
    expect([for (final e in hits) e.source], ['石井和希', '和希', '周']);
    expect(hits.last.promptLine, '周 = 아마네 (only where it is the name)');
    final prompt = batchTranslationPrompt(
      texts: ['「和希、命！」'],
      targetLanguage: 'Korean',
      sourceLanguage: 'Japanese',
      glossary: g.inTexts(['和希']),
      readings: const [MapEntry('和希', 'かずき'), MapEntry('天田', 'あまだ')],
    );
    expect(prompt, contains('和希 = 카즈키 (male)'));
    // A reading the glossary covers is not repeated as a hint.
    expect(prompt, isNot(contains('和希 = かずき')));
    expect(prompt, contains('天田 = あまだ'));
    expect(BookGlossary.decode(g.encode()).entries.length, 5);
  });

  test('the narration: first person, or third person following its hero',
      () {
    final first = bookNarration([
      for (var i = 0; i < 40; i++) '俺はため息をついた。夏凪が笑う。',
    ], ['夏凪']);
    expect(first.narration, Narration.firstPerson);
    final third = bookNarration([
      for (var i = 0; i < 40; i++) '周は首を傾げた。真昼がこちらを見る。真昼は笑った。',
      for (var i = 0; i < 5; i++) '周としては困る話だった。',
      '「俺は知らない」',
    ], ['真昼', '周']);
    expect(third.narration, Narration.thirdPerson);
    expect(third.hero, '周');
    final g = BookGlossary(
      entries: const [GlossaryEntry(source: '周', target: '아마네')],
      narration: third.narration,
      hero: third.hero,
    );
    expect(g.narrationNote, contains('こちら is 아마네'));
    final again = BookGlossary.decode(g.encode());
    expect(again.narration, Narration.thirdPerson);
    expect(again.hero, '周');
    // Merging keeps it; a short text tells nothing.
    expect(mergeGlossary(g, const []).hero, '周');
    expect(bookNarration(['周は笑った。'], ['周']).narration, Narration.unknown);
    // Third person, nobody clearly the hero: a note without a name.
    final nobody = bookNarration(
        [for (var i = 0; i < 40; i++) '周は首を傾げた。'], ['周']);
    expect(nobody.narration, Narration.thirdPerson);
    expect(nobody.hero, isNull);
    expect(BookGlossary(entries: const [], narration: nobody.narration)
        .narrationNote, contains('no 나 in narration'));
    final prompt = batchTranslationPrompt(
        texts: ['こちらを見る'], targetLanguage: 'Korean',
        sourceLanguage: 'Japanese', narration: g.narrationNote);
    expect(prompt, contains('following 周 (아마네)'));
    // The opening is the same for every batch of the book (kept read by
    // the runtime): the prompt starts with it.
    final head = batchPromptHead(
        texts: ['こちらを見る'], targetLanguage: 'Korean',
        sourceLanguage: 'Japanese', narration: g.narrationNote);
    expect(prompt.startsWith(head), isTrue);
    expect(head, isNot(contains('こちらを見る')));
    expect(
        batchTranslationPrompt(
                texts: ['別の段落'], targetLanguage: 'Korean',
                sourceLanguage: 'Japanese', narration: g.narrationNote)
            .startsWith(head),
        isTrue);
  });

  group('checks', () {
    const g = BookGlossary(entries: [
      GlossaryEntry(source: '和希', target: '카즈키', gender: GlossaryGender.male),
    ]);

    test('a good translation passes', () {
      expect(
          checkTranslation('「和希、おはよう！ 今日もいい天気だね」',
              '“카즈키, 좋은 아침! 오늘도 날씨 좋다”',
              glossary: g),
          isEmpty);
    });

    test('leftover Japanese, repetition, missing text, a wrong name', () {
      expect(checkTranslation('今日は晴れた。', '오늘은 晴れた.'),
          contains(QaIssue.leftoverSource));
      expect(
          checkTranslation('彼は笑った。そして走った。',
              '그는 웃었다 웃었다 웃었다 웃었다 웃었다'),
          contains(QaIssue.repetition));
      expect(
          checkTranslation('屋上のフェンスを越えると、荒々しい風が吹いていた。そして空は青かった。',
              '바람이 불었다.'),
          contains(QaIssue.tooShort));
      expect(checkTranslation('「和希、待って」', '“가즈키, 기다려”', glossary: g),
          [QaIssue.glossaryMiss]);
      // A sound the source repeats may repeat.
      expect(checkTranslation('ドンドンドンドン', '쿵쿵쿵쿵쿵쿵쿵쿵'), isEmpty);
      // Polite Japanese, casual Korean: the voice changed.
      expect(checkTranslation('「なんですか」', '“뭔데.”'), [QaIssue.speechLevel]);
      expect(checkTranslation('「なんですか」', '“뭔가요.”'), isEmpty);
      expect(checkTranslation('「駄目でしょ！」', '“안 되잖아!”'), isEmpty);
    });

    test('the fix request names the problems and the glossary', () {
      final prompt = refinementPrompt(
        style: 'STYLE',
        source: '「和希、待って」',
        draft: '“가즈키, 기다려”',
        issues: const [QaIssue.glossaryMiss],
        glossary: g.entries,
      );
      expect(prompt, startsWith('STYLE'));
      expect(prompt, contains('和希 = 카즈키 (male)'));
      expect(prompt, contains('“가즈키, 기다려”'));
      expect(prompt, contains('Names are not written as the glossary says'));
      expect(refinedIsBetter(const [QaIssue.glossaryMiss], const []), isTrue);
      expect(refinedIsBetter(const [QaIssue.tooShort],
          const [QaIssue.leftoverSource]), isFalse);
    });
  });

  test('the service makes, saves, edits and keeps removals on a remake',
      () async {
    final dir = Directory.systemTemp.createTempSync('glossary');
    addTearDown(() => dir.deleteSync(recursive: true));
    final service = GlossaryService.instance
      ..directory = () async => dir;
    final book = File('${dir.path}/book.epub');
    // Not an EPUB: no candidates, the glossary stays empty.
    book.writeAsBytesSync([1, 2, 3]);
    await service.save('b.epub', const BookGlossary(entries: [
      GlossaryEntry(source: '和希', target: '카즈키', kind: GlossaryKind.person),
      GlossaryEntry(source: '天田', target: '아마다', kind: GlossaryKind.person),
    ], complete: true));
    await service.updateEntry('b.epub',
        const GlossaryEntry(source: '和希', target: '가즈키', kind: GlossaryKind.person));
    await service.removeEntry('b.epub', '天田');
    final saved = BookGlossary.decode(
        File('${dir.path}/b.epub.json').readAsStringSync());
    final bySource = {for (final e in saved.entries) e.source: e};
    expect(bySource['和希']!.target, '가즈키');
    expect(bySource['和希']!.edited, isTrue);
    expect(bySource['天田']!.target, '');
    expect(saved.inTexts(['天田と和希']).map((e) => e.source), ['和希']);
    final again = mergeGlossary(saved, const [
      GlossaryEntry(source: '天田', target: '아마다', kind: GlossaryKind.person),
    ]);
    expect(again.entries.firstWhere((e) => e.source == '天田').target, '');
  });

  test('the book calls her しずくちゃん: a person, whatever kind of word '
      'the model took it for', () {
    const candidates = [
      GlossaryCandidate(source: 'しずく', count: 546, example: '', girlHonorifics: 45),
      GlossaryCandidate(source: 'アキラ', count: 16, example: '', boyHonorifics: 10),
      GlossaryCandidate(source: 'イルカ', count: 7, example: ''),
      GlossaryCandidate(source: '赤', count: 9, example: '', reading: 'あか', girlHonorifics: 9),
    ];
    final entries = parseGlossaryAnswer('''
[1] 시즈쿠 | term | - | casual, gentle
[2] 아키라 | term | - | -
[3] 돌고래 | term | - | -
[4] 아기 | term | - | -''', candidates);
    final by = {for (final e in entries) e.source: e};
    expect(by.keys.toSet(), {'しずく', 'アキラ'});
    expect(by['しずく']!.target, '시즈쿠');
    expect(by['しずく']!.kind, GlossaryKind.person);
    expect(by['しずく']!.gender, GlossaryGender.female);
    expect(by['しずく']!.speech, 'casual, gentle');
    expect(by['アキラ']!.kind, GlossaryKind.person);
    expect(by['アキラ']!.gender, GlossaryGender.male);
    // Translated, not spelled: the model's word for an ordinary word.
    expect(by.containsKey('赤'), isFalse);

    // A translation for a name written in hiragana is not its name.
    final drop = parseGlossaryAnswer('[1] 물방울 | term | - | -', candidates);
    expect(drop.single.target, '시즈쿠');
    expect(drop.single.kind, GlossaryKind.person);
  });

  test('names written in hiragana, from the book alone', () {
    const BookSurvey survey = (
      candidates: [
        GlossaryCandidate(source: 'しずく', count: 546, example: '', girlHonorifics: 45),
        GlossaryCandidate(source: '純', count: 194, example: '', boyHonorifics: 54),
        GlossaryCandidate(source: 'モデル', count: 42, example: ''),
      ],
      places: [],
      narration: Narration.firstPerson,
      hero: null,
      text: '',
    );
    final names = hiraganaNames(survey);
    expect(names.single.source, 'しずく');
    expect(names.single.target, '시즈쿠');
    expect(names.single.gender, GlossaryGender.female);
    expect(names.single.isName, isTrue);
  });
}
