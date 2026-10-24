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
    // The kanji's meaning, not its reading: the reading wins. A spelling
    // a syllable apart is the model's to keep.
    expect(bySource['風靡']!.target, '후비');
    expect(bySource['夏凪']!.target, '나쓰나기');
  });

  test('full names split after the family name; edits survive a remake', () {
    final made = mergeGlossary(BookGlossary.empty, const [
      GlossaryEntry(source: '天田', target: '아마다', kind: GlossaryKind.person),
      GlossaryEntry(source: '天田照人', target: '아마다테루히토', kind: GlossaryKind.person),
    ]);
    expect(made.entries.firstWhere((e) => e.source == '天田照人').target,
        '아마다 테루히토');
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
}
