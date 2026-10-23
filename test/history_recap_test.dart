// Search history, reading activity and the library's reading record:
// the database rows behind them, the recap arithmetic, the backup round
// trip, and the recap cards / recent-search pills on narrow screens.

// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/backup_service.dart';
import 'package:openlib/services/database.dart';
import 'package:openlib/services/library_organization.dart';
import 'package:openlib/services/reading_recap.dart';
import 'package:openlib/services/search_history.dart';
import 'package:openlib/ui/components/library_recap.dart';
import 'package:openlib/ui/search_page.dart';

class _FakePathProvider extends PathProviderPlatform {
  Future<String> _dir(String name) async {
    final dir = Directory('/tmp/openlib_history_recap_test/$name');
    await dir.create(recursive: true);
    return dir.path;
  }

  @override
  Future<String?> getApplicationSupportPath() => _dir('support');
  @override
  Future<String?> getApplicationDocumentsPath() => _dir('documents');
  @override
  Future<String?> getTemporaryPath() => _dir('temp');
  @override
  Future<String?> getLibraryPath() => _dir('library');
}

LibraryBook _book(String id,
        {ReadingStatus status = ReadingStatus.unread, BookGenre? genre}) =>
    LibraryBook(
      book: MyBook(
        id: id,
        title: 'Book $id',
        author: 'A',
        thumbnail: null,
        link: '',
        publisher: null,
        info: null,
        format: 'epub',
        description: null,
      ),
      status: status,
      genre: genre,
    );

/// Pumps, letting real database work run, until [done] or a generous
/// limit (slow CI runners need more than a fixed few frames).
Future<void> pumpUntil(WidgetTester tester, bool Function() done,
    {int max = 60}) async {
  for (var i = 0; i < max && !done(); i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
}

void main() {
  setUpAll(() {
    final stale = Directory('/tmp/openlib_history_recap_test');
    if (stale.existsSync()) stale.deleteSync(recursive: true);
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    PathProviderPlatform.instance = _FakePathProvider();
  });

  final db = MyLibraryDb.instance;

  group('search history (database)', () {
    setUp(() => db.clearSearchHistory());

    test('newest first, one entry per query regardless of case', () async {
      final t = DateTime(2026, 10, 1, 12);
      await db.addSearchHistory('Re:Zero', t);
      await db.addSearchHistory('overlord', t.add(const Duration(minutes: 1)));
      await db.addSearchHistory(
          '  re:zero ', t.add(const Duration(minutes: 2)));
      await db.addSearchHistory('   ', t.add(const Duration(minutes: 3)));
      expect(await db.getSearchHistory(), ['re:zero', 'overlord']);
    });

    test('keeps only the newest ${MyLibraryDb.searchHistoryLimit}', () async {
      final t = DateTime(2026, 1, 1);
      for (var i = 0; i < MyLibraryDb.searchHistoryLimit + 7; i++) {
        await db.addSearchHistory('q$i', t.add(Duration(seconds: i)));
      }
      final all = await db.getSearchHistory();
      expect(all.length, MyLibraryDb.searchHistoryLimit);
      expect(all.first, 'q${MyLibraryDb.searchHistoryLimit + 6}');
      expect(all, isNot(contains('q6')));
      expect(all, contains('q7'));
    });

    test('delete one, clear all', () async {
      await db.addSearchHistory('a');
      await db.addSearchHistory('b');
      await db.deleteSearchHistory('a');
      expect(await db.getSearchHistory(), ['b']);
      await db.clearSearchHistory();
      expect(await db.getSearchHistory(), isEmpty);
    });

    test('matchingHistory: contains, case-insensitive, not the query itself',
        () {
      const history = [
        'Overlord 3',
        'overlord',
        'Re:Zero',
        'Lord of Mysteries'
      ];
      expect(matchingHistory(history, 'LORD'),
          ['Overlord 3', 'overlord', 'Lord of Mysteries']);
      expect(matchingHistory(history, 'overlord'), ['Overlord 3']);
      expect(matchingHistory(history, '  '), isEmpty);
      expect(matchingHistory(history, 'lord', limit: 1), ['Overlord 3']);
    });
  });

  group('reading activity (database)', () {
    test('a reading day counts every position save that day', () async {
      final database = await db.database;
      await database.delete('readingdays');
      final day = DateTime(2026, 10, 20, 9);
      await db.recordReadingDay(day);
      await db.recordReadingDay(day.add(const Duration(hours: 5)));
      await db.recordReadingDay(DateTime(2026, 10, 21, 0, 5));
      expect(await db.getReadingDays(), {'2026-10-20': 2, '2026-10-21': 1});

      // saveBookState records today.
      await db.saveBookState('x.epub', 'epubcfi(/6/2)');
      final today = MyLibraryDb.dayKey(DateTime.now());
      expect((await db.getReadingDays())[today], greaterThanOrEqualTo(1));
    });

    test('finishing stamps a date; un-finishing and deleting clear it',
        () async {
      final when = DateTime(2026, 10, 5, 20);
      await db.setCompleted('done.epub', true, when);
      expect((await db.getCompletionDates())['done.epub'], when);
      await db.setCompleted('done.epub', false);
      expect((await db.getCompletionDates()).containsKey('done.epub'), isFalse);

      await db.setCompleted('gone.epub', true, when);
      await db.deleteBookState('gone.epub');
      expect((await db.getCompletionDates()).containsKey('gone.epub'), isFalse);
    });

    test('backup carries history, reading days and completions', () async {
      final database = await db.database;
      for (final t in ['searchhistory', 'readingdays', 'completions']) {
        await database.delete(t);
      }
      await db.addSearchHistory('kept query', DateTime(2026, 9, 1));
      await db.recordReadingDay(DateTime(2026, 9, 2));
      await db.setCompleted('kept.epub', true, DateTime(2026, 9, 3));

      final service = BackupService(database: db);
      final json = await service.createBackupJson();
      for (final t in ['searchhistory', 'readingdays', 'completions']) {
        await database.delete(t);
      }
      expect(await service.restoreBackupJson(json), isTrue);

      expect(await db.getSearchHistory(), ['kept query']);
      expect((await db.getReadingDays())['2026-09-02'], 1);
      expect(
          (await db.getCompletionDates())['kept.epub'], DateTime(2026, 9, 3));
    });
  });

  group('milestones', () {
    test('reached and next around the count', () {
      expect(Milestone.of(0).reached, 0);
      expect(Milestone.of(0).next, 1);
      expect(Milestone.of(4).reached, 3);
      expect(Milestone.of(4).next, 5);
      expect(Milestone.of(4).remaining(4), 1);
      expect(Milestone.of(4).progress(4), closeTo(0.8, 1e-9));
      expect(Milestone.of(10).reached, 10);
      expect(Milestone.of(10).next, 20);
      expect(Milestone.of(10).progress(10), closeTo(0.5, 1e-9));
      expect(Milestone.of(0).progress(0), 0);
      expect(Milestone.of(5000).next, isNull);
      expect(Milestone.of(5000).progress(5000), 1);
      expect(Milestone.of(5000).remaining(5000), 0);
    });
  });

  group('computeReadingRecap', () {
    final now = DateTime(2026, 10, 22, 21, 30);
    Map<String, int> days(List<String> keys) => {for (final k in keys) k: 1};

    test('streak counts back from today', () {
      final r = computeReadingRecap(
        books: [_book('a')],
        readingDays:
            days(['2026-10-22', '2026-10-21', '2026-10-20', '2026-10-18']),
        completionDates: const {},
        now: now,
      );
      expect(r.currentStreak, 3);
      expect(r.longestStreak, 3);
    });

    test('no reading yet today keeps yesterday\'s streak', () {
      final r = computeReadingRecap(
        books: [_book('a')],
        readingDays: days(['2026-10-21', '2026-10-20']),
        completionDates: const {},
        now: now,
      );
      expect(r.currentStreak, 2);
    });

    test('a missed day ends the streak; longest survives', () {
      final r = computeReadingRecap(
        books: [_book('a')],
        readingDays: days([
          '2026-10-20', // gap on the 21st and 22nd
          '2026-09-01', '2026-09-02', '2026-09-03', '2026-09-04',
          // across a month end
          '2026-08-30', '2026-08-31',
        ]),
        completionDates: const {},
        now: now,
      );
      expect(r.currentStreak, 0);
      expect(r.longestStreak, 6);
    });

    test('28 days, oldest first, today last', () {
      final r = computeReadingRecap(
        books: [_book('a')],
        readingDays: {'2026-10-22': 7, '2026-09-25': 2, '2026-09-24': 9},
        completionDates: const {},
        now: now,
      );
      expect(r.recentDays.length, 28);
      expect(r.recentDays.last, 7);
      expect(r.recentDays.first, 2); // 27 days before the 22nd
      expect(r.recentReadingDays, 2);
    });

    test('this month counts only library books finished this month', () {
      final r = computeReadingRecap(
        books: [
          _book('a', status: ReadingStatus.completed),
          _book('b', status: ReadingStatus.completed),
          _book('c', status: ReadingStatus.inProgress),
        ],
        readingDays: days(['2026-10-01', '2026-10-15', '2026-09-30']),
        completionDates: {
          'a.epub': DateTime(2026, 10, 3),
          'b.epub': DateTime(2026, 9, 28),
          'removed.epub': DateTime(2026, 10, 4),
        },
        now: now,
      );
      expect(r.completed, 2);
      expect(r.inProgress, 1);
      expect(r.completedThisMonth, 1);
      expect(r.readingDaysThisMonth, 2);
      expect(r.month, 10);
    });

    test('genres largest first, books without a genre left out', () {
      final r = computeReadingRecap(
        books: [
          _book('a', genre: BookGenre.comic),
          _book('b', genre: BookGenre.lightNovel),
          _book('c', genre: BookGenre.lightNovel),
          _book('d'),
        ],
        readingDays: const {},
        completionDates: const {},
        now: now,
      );
      expect(
          r.genres.map((e) => e.key), [BookGenre.lightNovel, BookGenre.comic]);
      expect(r.genres.first.value, 2);
    });
  });

  group('widgets', () {
    Widget app(Widget child, {Locale locale = const Locale('ko')}) =>
        MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SingleChildScrollView(child: child)),
        );

    ReadingRecap recap({required int completed, int genres = 6}) {
      final books = [
        for (var i = 0; i < completed + 3; i++)
          _book('b$i',
              status: i < completed
                  ? ReadingStatus.completed
                  : ReadingStatus.inProgress,
              genre: i % 7 < genres ? BookGenre.values[i % 7] : null),
      ];
      return computeReadingRecap(
        books: books,
        readingDays: {
          for (var i = 0; i < 30; i++)
            MyLibraryDb.dayKey(DateTime(2026, 10, 22 - i)): i % 4 * 4,
        },
        completionDates: {'b0.epub': DateTime(2026, 10, 2)},
        now: DateTime(2026, 10, 22, 12),
      );
    }

    for (final width in [320.0, 360.0, 430.0]) {
      for (final completed in [0, 4, 1234]) {
        testWidgets('recap fits at ${width.toInt()}dp with $completed finished',
            (tester) async {
          tester.view.physicalSize = Size(width * 3, 2400);
          tester.view.devicePixelRatio = 3;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(app(Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LibraryRecapBento(recap: recap(completed: completed)),
          )));
          await tester.pump(const Duration(seconds: 1));
          expect(tester.takeException(), isNull);
          expect(find.byKey(const ValueKey('recapMilestone')), findsOneWidget);
          expect(find.byKey(const ValueKey('recapActivity')), findsOneWidget);
          expect(find.byKey(const ValueKey('recapGenres')), findsOneWidget);
        });
      }
    }

    testWidgets('recap reads in Korean and Japanese', (tester) async {
      await tester.pumpWidget(
          app(LibraryRecapBento(recap: recap(completed: 4, genres: 0))));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('독서 기록'), findsOneWidget);
      expect(find.text('5권까지 1권 남음'), findsOneWidget);
      expect(find.text('10월 리캡'), findsOneWidget);
      expect(find.byKey(const ValueKey('recapGenres')), findsNothing);

      await tester.pumpWidget(app(
          LibraryRecapBento(recap: recap(completed: 4, genres: 0)),
          locale: const Locale('ja')));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('読書記録'), findsOneWidget);
      expect(find.text('5冊まであと1冊'), findsOneWidget);
      expect(find.text('10月のまとめ'), findsOneWidget);
    });

    testWidgets('search page lists recent searches and removes one',
        (tester) async {
      await tester.runAsync(() async {
        await db.clearSearchHistory();
        await db.addSearchHistory('Overlord', DateTime(2026, 10, 1));
        await db.addSearchHistory('Re:Zero', DateTime(2026, 10, 2));
      });
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      // The search filters' fixed-width dropdowns overflow with the test
      // font (every glyph a full em wide); that layout is not under test.
      final original = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('RenderFlex overflowed')) {
          return;
        }
        original?.call(details);
      };
      addTearDown(() => FlutterError.onError = original);
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: SearchPage()),
        ),
      ));
      await pumpUntil(
          tester,
          () => find
              .byKey(const ValueKey('history-Overlord'))
              .evaluate()
              .isNotEmpty);
      expect(find.byKey(const ValueKey('largeTitle')), findsOneWidget);
      expect(find.text('Recent searches'), findsOneWidget);
      expect(find.byKey(const ValueKey('history-Re:Zero')), findsOneWidget);
      expect(find.byKey(const ValueKey('history-Overlord')), findsOneWidget);
      // Newest first.
      expect(
          tester.getTopLeft(find.byKey(const ValueKey('history-Re:Zero'))).dx,
          lessThan(tester
              .getTopLeft(find.byKey(const ValueKey('history-Overlord')))
              .dx));

      await tester.tap(find.descendant(
          of: find.byKey(const ValueKey('history-Overlord')),
          matching: find.byIcon(Icons.close)));
      await pumpUntil(
          tester,
          () => find
              .byKey(const ValueKey('history-Overlord'))
              .evaluate()
              .isEmpty);
      expect(find.byKey(const ValueKey('history-Overlord')), findsNothing);
      expect(await tester.runAsync(() => db.getSearchHistory()), ['Re:Zero']);

      // Typing shows matching history above the web suggestions.
      await tester.enterText(find.byType(TextField).first, 'zer');
      await tester.pump();
      expect(
          find.byKey(const ValueKey('historyMatch-Re:Zero')), findsOneWidget);
      expect(find.byKey(const ValueKey('recentSearches')), findsNothing);
      // Let the suggestion debounce fire (its request fails offline).
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 700)));
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
