// The study sheets and the word book: a word's meaning from the engine
// and adding it, the settings sheet, the difficulty sheet, review.

// Dart imports:
import 'dart:async';
import 'dart:io';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/study/book_difficulty.dart';
import 'package:openlib/services/study/study_assistant.dart';
import 'package:openlib/services/study/study_settings.dart';
import 'package:openlib/services/study/study_store.dart';
import 'package:openlib/ui/components/study_sheets.dart';
import 'package:openlib/ui/study_page.dart';

Widget _app(Widget child) => MaterialApp(
      locale: const Locale('ko'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

class _Assistant implements StudyAssistant {
  _Assistant(this.answer);
  final Completer<WordMeaning?> answer;
  int asked = 0;

  @override
  Future<WordMeaning?> meaning(WordQuery q) {
    asked++;
    return answer.future;
  }

  @override
  WordMeaning? knownMeaning(WordQuery q) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory dir;
  final store = StudyStore.instance;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('study_ui');
    store.debugReset();
    store.directory = () async => dir;
  });
  tearDown(() {
    store.debugReset();
    dir.deleteSync(recursive: true);
  });

  testWidgets('word sheet: reading, level, Korean kanji readings, meaning, add',
      (tester) async {
    await tester.runAsync(() => store.load());
    final answer = Completer<WordMeaning?>();
    final assistant = _Assistant(answer);
    await tester.pumpWidget(_app(WordSheet(
      query: const WordQuery(
          base: '監視',
          surface: '監視',
          reading: 'かんし',
          sentence: '運営に監視されている。',
          pos: '名詞',
          level: 1),
      assistant: assistant,
      book: 'Book',
      targetCode: 'ko',
      onExplain: (_) {},
    )));
    await tester.pump();
    expect(find.text('かんし'), findsOneWidget);
    expect(find.text('N1'), findsOneWidget);
    expect(find.text('뜻을 찾는 중…'), findsOneWidget);
    expect(assistant.asked, 1);

    // Added before the meaning came: the card takes it when it does.
    await tester.tap(find.byKey(const ValueKey('studyAdd')));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
    expect(store.has('監視', 'かんし'), isTrue);
    expect(find.text('단어장에 있음'), findsOneWidget);

    answer.complete(const WordMeaning(meaning: '감시', other: ['감독']));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
    expect(find.byKey(const ValueKey('studyMeaning')), findsOneWidget);
    expect(find.text('감시'), findsOneWidget);
    expect(find.textContaining('감독'), findsOneWidget);
    expect(store.card('監視', 'かんし')!.meaning, '감시');
    expect(find.text('문장 해설'), findsOneWidget);
    // The store's save timer.
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('word sheet without an engine says how to get one',
      (tester) async {
    await tester.pumpWidget(_app(const WordSheet(
      query: WordQuery(base: '扉', reading: 'とびら'),
      assistant: null,
      book: 'Book',
      targetCode: 'ko',
    )));
    await tester.pump();
    expect(find.textContaining('번역(휴대폰 모델이나 Gemini)을 설정'), findsOneWidget);
  });

  testWidgets('settings sheet changes the layout, furigana and level',
      (tester) async {
    StudySettings.instance.debugSet(const StudySettingsData());
    await tester.pumpWidget(_app(const StudySettingsSheet(
        japanese: true, translating: true)));
    await tester.pump();
    await tester.tap(find.text('원문 아래'));
    await tester.pump();
    expect(StudySettings.instance.value.layout, TranslationLayout.below);
    await tester.tap(find.text('내 수준 이상'));
    await tester.pump();
    expect(StudySettings.instance.value.furigana, FuriganaMode.hard);
    await tester.tap(find.byKey(const ValueKey('studyLevel2')));
    await tester.pump();
    expect(StudySettings.instance.value.level, 2);
    expect(find.byKey(const ValueKey('studyToolsDownload')), findsOneWidget);

    // A book in another language: no Japanese settings.
    await tester.pumpWidget(_app(const StudySettingsSheet(
        japanese: false, translating: true)));
    await tester.pump();
    expect(find.byKey(const ValueKey('studyFurigana')), findsNothing);
    expect(find.byKey(const ValueKey('studyLayout')), findsOneWidget);
  });

  testWidgets('difficulty sheet: progress, then shares and words to add',
      (tester) async {
    await tester.runAsync(() => store.load());
    StudySettings.instance.debugSet(const StudySettingsData(level: 4));
    final progress = ValueNotifier<double>(0.4);
    final result = Completer<BookDifficulty?>();
    final added = <String>[];
    await tester.pumpWidget(_app(DifficultySheet(
      progress: progress,
      result: result.future,
      book: 'Book',
      names: const {'幽鬼'},
      onAdded: (w) => added.addAll(w.map((x) => x.base)),
    )));
    expect(find.text('책을 읽는 중… 40%'), findsOneWidget);
    result.complete(const BookDifficulty(
      tokens: 100,
      unique: 10,
      byLevel: {
        5: LevelCount(60, 5),
        4: LevelCount(20, 3),
        1: LevelCount(20, 2),
      },
      words: [
        BookWord('運営', 'うんえい', 1, 56, '運営が言った。'),
        BookWord('幽鬼', 'ゆうき', 0, 300),
        BookWord('食べる', 'たべる', 5, 30),
      ],
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('JLPT 단어의 20%가 N4보다 어렵습니다'), findsOneWidget);
    expect(find.textContaining('運営', findRichText: true), findsOneWidget);
    expect(find.textContaining('幽鬼', findRichText: true), findsNothing);
    await tester.tap(find.byKey(const ValueKey('studyAddAll')));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
    expect(store.has('運営', 'うんえい'), isTrue);
    expect(store.card('運営', 'うんえい')!.sentence, '運営が言った。');
    expect(added, ['運営']);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('word book and review: show, answer, done', (tester) async {
    await tester.runAsync(() async {
      await store.load();
      await store.add(word: '扉', reading: 'とびら', meaning: '문', sentence: '扉を開けた。');
    });
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ko'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const StudyPage(),
    ));
    await tester.pump();
    expect(find.text('단어 1개'), findsOneWidget);
    expect(find.text('새 카드'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('studyReview')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('studyCardWord')), findsOneWidget);
    expect(find.byKey(const ValueKey('studyCardMeaning')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('studyShowAnswer')));
    await tester.pump();
    expect(find.text('문'), findsOneWidget);
    // Easy graduates it (4 days): the session ends.
    await tester.tap(find.byKey(const ValueKey('studyGrade-easy')));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
    expect(find.byKey(const ValueKey('studyReviewDone')), findsOneWidget);
    expect(store.card('扉', 'とびら')!.interval, 4);
    await tester.pump(const Duration(seconds: 1));
  });
}
