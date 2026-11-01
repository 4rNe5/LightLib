// Study features: the word book's review schedule, its record and
// Anki export, the questions asked of the translation engine and their
// answers, the bundled lists (JLPT levels, Korean readings of kanji), a
// book's difficulty, and the word tools' download.

// Dart imports:
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// Package imports:
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/services/study/book_difficulty.dart';
import 'package:openlib/services/study/japanese_tools.dart';
import 'package:openlib/services/study/study_assistant.dart';
import 'package:openlib/services/study/study_data.dart';
import 'package:openlib/services/study/study_settings.dart';
import 'package:openlib/services/study/study_store.dart';
import 'package:openlib/services/translation/book_glossary.dart';
import 'package:openlib/services/translation/translator.dart';

class _Engine implements Translator {
  _Engine(this.answer);
  final String? Function(String prompt) answer;
  final List<String> prompts = [];
  final List<String?> heads = [];
  final List<TranslationPriority> priorities = [];

  @override
  String? get deviceLabel => 'GPU';
  @override
  int get batchSize => 1;
  @override
  Future<void> load() async {}
  @override
  Future<String> translate(String text,
          {required String targetLanguage,
          String? sourceLanguage,
          String? context,
          String? following,
          TranslationPriority priority =
              TranslationPriority.background}) async =>
      text;
  @override
  Future<List<String>> translateBatch(List<String> texts,
          {required String targetLanguage,
          String? sourceLanguage,
          List<String> before = const [],
          List<String?> beforeTranslations = const [],
          Map<String, String> readings = const {},
          BookGlossary glossary = BookGlossary.empty,
          TranslationPriority priority = TranslationPriority.background,
          void Function(int index, String translation)? onEach}) async =>
      texts;
  @override
  Future<String?> complete(String prompt,
      {required int maxTokens,
      TranslationPriority priority = TranslationPriority.background,
      String? head}) async {
    prompts.add(prompt);
    heads.add(head);
    priorities.add(priority);
    return answer(prompt);
  }

  @override
  Future<void> dispose() async {}
}

class _Files implements HttpClientAdapter {
  _Files(this.files);
  final Map<String, List<int>> files;
  final List<String> asked = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    final url = options.uri.toString();
    asked.add(url);
    final data = files[url];
    if (data == null) return ResponseBody.fromString('', 404);
    return ResponseBody.fromBytes(data, 200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  final t0 = DateTime(2026, 11, 1, 9);

  StudyCard card({double interval = 0, int step = 0, int reps = 0}) =>
      StudyCard(
        id: StudyCard.idFor('食べる', 'たべる'),
        word: '食べる',
        reading: 'たべる',
        added: t0,
        due: t0,
        interval: interval,
        step: step,
        reps: reps,
      );

  group('review schedule', () {
    test('new cards step through 1 and 10 minutes, then a day', () {
      final again = schedule(card(), ReviewGrade.again, t0);
      expect(again.due, t0.add(const Duration(minutes: 1)));
      expect(again.learning, isTrue);
      final good = schedule(card(), ReviewGrade.good, t0);
      expect(good.step, 1);
      expect(good.due, t0.add(const Duration(minutes: 10)));
      final graduated = schedule(good, ReviewGrade.good, t0);
      expect(graduated.interval, 1);
      expect(graduated.due, t0.add(const Duration(days: 1)));
      final easy = schedule(card(), ReviewGrade.easy, t0);
      expect(easy.interval, 4);
    });

    test('reviews grow by the ease; a lapse relearns and lowers it', () {
      final c = card(interval: 10, reps: 3);
      final good = schedule(c, ReviewGrade.good, t0);
      expect(good.interval, closeTo(25, 0.01));
      expect(good.due, t0.add(const Duration(days: 25)));
      final easy = schedule(c, ReviewGrade.easy, t0);
      expect(easy.interval, greaterThan(good.interval));
      expect(easy.ease, closeTo(2.65, 1e-9));
      final hard = schedule(c, ReviewGrade.hard, t0);
      expect(hard.interval, closeTo(12, 0.01));
      final lapse = schedule(c, ReviewGrade.again, t0);
      expect(lapse.learning, isTrue);
      expect(lapse.lapses, 1);
      expect(lapse.ease, closeTo(2.3, 1e-9));
      expect(lapse.due, t0.add(const Duration(minutes: 10)));
      // The ease never falls under 1.3.
      var low = c;
      for (var i = 0; i < 10; i++) {
        low = schedule(low.copyWith(interval: 5), ReviewGrade.again, t0);
      }
      expect(low.ease, 1.3);
    });
  });

  group('study store', () {
    late Directory dir;
    late StudyStore store;
    var now = t0;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('study');
      now = t0;
      store = StudyStore(directory: () async => dir)..now = () => now;
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('adds, reviews and keeps cards, answers and days on disk', () async {
      await store.add(
          word: '食べる',
          reading: 'たべる',
          meaning: '먹다',
          sentence: 'パンを食べる。',
          book: 'Book',
          level: 5);
      await store.add(word: '扉', reading: 'とびら', level: 0);
      expect(store.cards.length, 2);
      expect(store.due().length, 2);
      // Adding again updates the meaning, not the count.
      await store.add(word: '扉', reading: 'とびら', meaning: '문');
      expect(store.cards.length, 2);
      expect(store.card('扉', 'とびら')!.meaning, '문');
      expect(store.dayAt(now).added, 2);

      await store.review(StudyCard.idFor('食べる', 'たべる'), ReviewGrade.easy);
      expect(store.due().map((c) => c.word), ['扉']);
      store.keepAnswer('k', {'meaning': 'x'});
      store.count(const StudyDay(chars: 120, looked: 2));
      await store.save();

      final again = StudyStore(directory: () async => dir)..now = () => now;
      await again.load();
      expect(again.cards.map((c) => c.word).toSet(), {'食べる', '扉'});
      final eaten = again.card('食べる', 'たべる')!;
      expect(eaten.interval, 4);
      expect(eaten.sentence, 'パンを食べる。');
      expect(again.answer('k'), {'meaning': 'x'});
      expect(again.dayAt(now).chars, 120);
      expect(again.dayAt(now).reviewed, 1);

      // Four days on, it is due again.
      now = t0.add(const Duration(days: 4, minutes: 1));
      again.now = () => now;
      expect(again.due().map((c) => c.word), contains('食べる'));
    });

    test('streak counts days in a row up to today or yesterday', () async {
      store.count(const StudyDay(looked: 1));
      now = t0.add(const Duration(days: 1));
      store.count(const StudyDay(reviewed: 1));
      now = t0.add(const Duration(days: 2));
      expect(store.streak, 2); // nothing yet today
      store.count(const StudyDay(explained: 1));
      expect(store.streak, 3);
      now = t0.add(const Duration(days: 5));
      expect(store.streak, 0);
      final week = store.recent(7);
      expect(week.length, 7);
      expect(week.last.$1, DateTime(2026, 11, 6));
      expect(week.where((d) => d.$2.active).length, 3);
    });

    test('new cards are limited per review, due ones come first', () async {
      for (var i = 0; i < 25; i++) {
        await store.add(word: 'w$i');
      }
      final reviewed = StudyCard.idFor('w0', '');
      await store.review(reviewed, ReviewGrade.easy);
      now = t0.add(const Duration(days: 5));
      final due = store.due(newLimit: 10);
      expect(due.first.id, reviewed);
      expect(due.length, 11);
    });
  });

  test('Anki export: tab separated with a header Anki reads', () {
    final c = StudyCard(
      id: 'x',
      word: '扉',
      reading: 'とびら',
      meaning: '문\t짝',
      sentence: '扉を開けた。\n次',
      book: 'Book',
      level: 2,
      added: t0,
      due: t0,
    );
    final text = ankiExport([c]);
    final lines = text.trim().split('\n');
    expect(lines.first, '#separator:tab');
    expect(lines, contains('#tags column:7'));
    final row = lines.last.split('\t');
    expect(row, ['扉', 'とびら', '문 짝', '扉を開けた。<br>次', '', 'Book', 'LightLib JLPT_N2']);
  });

  group('questions and answers', () {
    test('word prompts carry the word, its form, reading and sentence', () {
      const q = WordQuery(
          base: '言い残す',
          surface: '言い残し',
          reading: 'いいのこす',
          sentence: 'とぶっきらぼうに言い残していった。');
      final prompt = wordPrompt(q, 'Korean');
      expect(prompt, startsWith(wordPromptHead('Korean')));
      expect(prompt, contains('Word: 言い残す (written in the book as 言い残し), read いいのこす'));
      expect(prompt, contains('Sentence: とぶっきらぼうに言い残していった。'));
      expect(explainPrompt('文。', 'Korean', 3, before: '前。'),
          allOf(contains('JLPT N3'), contains('context only): 前。'), endsWith('Sentence: 文。')));
    });

    test('answers are read from JSON, fenced or not, or as a short line', () {
      expect(
          parseWordAnswer('```json\n{"meaning": "남기다", "other": ["말을 남기다", ""], "note": ""}\n```')!
              .toJson(),
          {'meaning': '남기다', 'other': ['말을 남기다'], 'note': ''});
      expect(parseWordAnswer('먹다')!.meaning, '먹다');
      expect(parseWordAnswer('{"meaning": ""}'), isNull);
      expect(parseWordAnswer(''), isNull);
      expect(parseWordAnswer('x' * 200), isNull);

      final e = parseExplanation('Here: {"translation": "문을 열었다.", '
          '"words": [{"word": "扉", "reading": "とびら", "meaning": "문"}, {"word": ""}], '
          '"grammar": [{"pattern": "〜た", "explanation": "과거"}], "nuance": "담담하다"} done')!;
      expect(e.translation, '문을 열었다.');
      expect(e.words.single.word, '扉');
      expect(e.grammar.single.pattern, '〜た');
      expect(e.nuance, '담담하다');
      expect(parseExplanation('not json'), isNull);
      // Round trip through the store's JSON.
      expect(SentenceExplanation.fromJson(e.toJson()).toJson(), e.toJson());
    });

    test('the assistant asks once, on screen priority, and keeps the answer',
        () async {
      final dir = Directory.systemTemp.createTempSync('study');
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = StudyStore(directory: () async => dir);
      final engine = _Engine((p) => p.contains('JLPT')
          ? '{"translation": "번역", "words": [], "grammar": [], "nuance": ""}'
          : '{"meaning": "문", "other": [], "note": ""}');
      final assistant = StudyAssistant(
          translator: () async => engine,
          targetLanguage: 'Korean',
          targetCode: 'ko',
          store: store);
      const q = WordQuery(base: '扉', reading: 'とびら', sentence: '扉を開けた。');
      expect(assistant.knownMeaning(q), isNull);
      expect((await assistant.meaning(q))!.meaning, '문');
      expect((await assistant.meaning(q))!.meaning, '문');
      expect(engine.prompts.length, 1);
      expect(engine.priorities.single, TranslationPriority.visible);
      expect(engine.heads.single, wordPromptHead('Korean'));
      expect(assistant.knownMeaning(q)!.meaning, '문');
      // Another sentence is another question.
      await assistant.meaning(const WordQuery(base: '扉', reading: 'とびら', sentence: '別。'));
      expect(engine.prompts.length, 2);

      expect((await assistant.explain('扉を開けた。', level: 4))!.translation, '번역');
      await assistant.explain('扉を開けた。', level: 4);
      expect(engine.prompts.length, 3);
      expect(store.dayAt(DateTime.now()).looked, 3);
      expect(store.dayAt(DateTime.now()).explained, 2);
    });

    test('no engine, no answer', () async {
      final dir = Directory.systemTemp.createTempSync('study');
      addTearDown(() => dir.deleteSync(recursive: true));
      final assistant = StudyAssistant(
          translator: () async => null,
          targetLanguage: 'Korean',
          targetCode: 'ko',
          store: StudyStore(directory: () async => dir));
      expect(await assistant.meaning(const WordQuery(base: '扉')), isNull);
    });
  });

  group('bundled lists', () {
    test('the shipped files: JLPT levels and Korean readings', () {
      final jlpt = File('assets/study/jlpt.tsv').readAsStringSync();
      final hanja = File('assets/study/hanja_ko.tsv').readAsStringSync();
      final lines = jlpt.trim().split('\n');
      expect(lines.length, greaterThan(7500));
      final data = StudyData.instance..parse(hanja, jlpt);
      expect(data.levelOf('食べる'), 5);
      expect(data.levelOf('大丈夫'), 5);
      expect(data.levelOf('監視'), 1);
      // Kana-written words by their reading.
      expect(data.levelOf('たべる'), 5);
      expect(data.levelOf('ゲームセンター的な'), 0);
      expect(data.hanjaReading('大'), '대·다·태');
      expect(data.hanjaOf('質問'), [('質', '질·지'), ('問', '문')]);
      expect(data.sinoKorean('質問'), '질문');
      expect(data.sinoKorean('食べる'), isNull);
      expect(StudyData.hiragana('タベル'), 'たべる');
      expect(jlptLabel(3), 'N3');
      expect(jlptLabel(0), '');
    });
  });

  test('book difficulty: shares, harder words without names', () {
    final d = BookDifficulty.fromJson(jsonDecode(jsonEncode({
      'tokens': 100,
      'unique': 50,
      'byLevel': {
        '5': {'tokens': 50, 'unique': 10},
        '4': {'tokens': 20, 'unique': 10},
        '3': {'tokens': 10, 'unique': 10},
        '1': {'tokens': 10, 'unique': 10},
        '0': {'tokens': 10, 'unique': 10},
      },
      'words': [
        {'base': '運営', 'reading': 'うんえい', 'level': 1, 'count': 56},
        {'base': '幽鬼', 'reading': 'ゆうき', 'level': 0, 'count': 305},
        {'base': '里', 'reading': 'さと', 'level': 0, 'count': 309},
        {'base': '毒茸', 'reading': 'どくきのこ', 'level': 0, 'count': 83},
        {'base': '扉', 'reading': 'とびら', 'level': 3, 'count': 27},
        {'base': '一回', 'reading': 'いっかい', 'level': 3, 'count': 1},
        {'base': '食べる', 'reading': 'たべる', 'level': 5, 'count': 40},
      ],
    })) as Map<String, dynamic>);
    expect(d.share(5), 0.5);
    // Listed words only: (10 + 10) of 90 are above N4.
    expect(d.harderShare(4), closeTo(20 / 90, 1e-9));
    final hard = d.frequentHarder(4, names: {'幽鬼'});
    expect(hard.map((w) => w.base), ['運営', '扉', '毒茸']);
    expect(BookDifficulty.fromJson(d.toJson()).toJson(), d.toJson());
  });

  test('study settings round trip and clamp the level', () {
    const s = StudySettingsData(
        layout: TranslationLayout.hidden,
        furigana: FuriganaMode.hard,
        level: 3,
        wordTap: true);
    expect(StudySettingsData.fromJson(s.toJson()), s);
    expect(s.needsTools, isTrue);
    expect(const StudySettingsData().needsTools, isFalse);
    expect(s.copyWith(level: 9).level, 5);
    expect(StudySettingsData.fromJson({'layout': 'nope'}).layout,
        TranslationLayout.replace);
  });

  group('word tools', () {
    late Directory dir;
    final a = utf8.encode('first file');
    final b = utf8.encode('second');
    final files = [
      ToolFile('a.dat.gz', a.length, sha256.convert(a).toString()),
      ToolFile('b.dat.gz', b.length, sha256.convert(b).toString()),
    ];

    setUp(() => dir = Directory.systemTemp.createTempSync('tools'));
    tearDown(() => dir.deleteSync(recursive: true));

    JapaneseTools tools(_Files server) => JapaneseTools(
          directory: () async => dir,
          dio: Dio()..httpClientAdapter = server,
          files: files,
          mirrors: const ['https://one/', 'https://two/'],
        );

    test('downloads every file, the second mirror when the first fails',
        () async {
      final server = _Files({
        'https://one/a.dat.gz': a,
        // A wrong file on the first mirror is passed over.
        'https://one/b.dat.gz': utf8.encode('wrong!'),
        'https://two/b.dat.gz': b,
      });
      final t = tools(server);
      expect(await t.installed(), isFalse);
      expect(await t.download(), isTrue);
      expect(t.phase, ToolsPhase.ready);
      expect(t.progress, 1);
      expect(await t.read('a.dat.gz'), Uint8List.fromList(a));
      expect(await t.read('../etc/passwd'), isNull);
      final again = tools(_Files({}));
      expect(await again.installed(), isTrue);
    });

    test('a file no mirror has right fails the download', () async {
      final t = tools(_Files({'https://one/a.dat.gz': a}));
      expect(await t.download(), isFalse);
      expect(t.phase, ToolsPhase.failed);
      expect(t.error, contains('b.dat.gz'));
      // What arrived is kept for the next try.
      expect(File('${dir.path}/a.dat.gz').existsSync(), isTrue);
    });

    test('the published dictionary is about 18 MB in 12 files', () {
      expect(kuromojiFiles.length, 12);
      expect(kuromojiBytes, 17791956);
      expect(kuromojiMirrors.first, startsWith('https://'));
    });
  });
}
