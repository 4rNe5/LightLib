// What the home-screen widgets are given: the book being read (else the
// newest), the next one, and the reading record, worded in the app's
// language.

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/database.dart';
import 'package:openlib/services/home_widgets.dart';
import 'package:openlib/services/library_organization.dart';
import 'package:openlib/services/reading_recap.dart';

LibraryBook _book(String id, ReadingStatus status,
        {double? fraction, DateTime? readAt}) =>
    LibraryBook(
      fraction: fraction,
      readAt: readAt,
      book: MyBook(
        id: id,
        title: 'Title $id',
        author: 'Author $id',
        thumbnail: null,
        link: '',
        publisher: null,
        info: null,
        format: 'epub',
        description: null,
      ),
      tags: const {},
      status: status,
    );

Future<AppLocalizations> _l10n(WidgetTester tester, Locale locale) async {
  late AppLocalizations l10n;
  await tester.pumpWidget(Localizations(
    locale: locale,
    delegates: AppLocalizations.localizationsDelegates,
    child: Builder(builder: (context) {
      l10n = AppLocalizations.of(context);
      return const SizedBox();
    }),
  ));
  return l10n;
}

void main() {
  testWidgets('the book read last leads, with how far it was read',
      (tester) async {
    final l10n = await _l10n(tester, const Locale('ko'));
    final snapshot = widgetSnapshot(
      books: [
        // (Added last, read a week ago.)
        _book('volume4', ReadingStatus.inProgress,
            fraction: 0.08, readAt: DateTime(2026, 11, 14)),
        _book('volume3', ReadingStatus.inProgress,
            fraction: 0.616, readAt: DateTime(2026, 11, 21)),
        _book('done', ReadingStatus.completed),
      ],
      recap: null,
      l10n: l10n,
      localeTag: 'ko',
      covers: const {},
    );
    final hero = snapshot['hero']! as Map;
    expect(hero['id'], 'volume3');
    expect(hero['percent'], 62);
    expect(hero['progressText'], '62%');
    final next = snapshot['next']! as Map;
    expect(next['id'], 'volume4');
    expect(next['percent'], 8);
  });

  testWidgets('a book not opened has no bar; a finished one is full',
      (tester) async {
    final l10n = await _l10n(tester, const Locale('ko'));
    Map shown(LibraryBook book) => widgetSnapshot(
          books: [book],
          recap: null,
          l10n: l10n,
          localeTag: 'ko',
          covers: const {},
        )['hero']! as Map;
    final unread = shown(_book('n', ReadingStatus.unread));
    expect(unread.containsKey('percent'), isFalse);
    expect(unread.containsKey('progressText'), isFalse);
    final done = shown(_book('d', ReadingStatus.completed));
    expect(done['percent'], 100);
    expect(done['progressText'], '다 읽음');
    // Read in a viewer that does not say how far.
    final somewhere = shown(_book('p', ReadingStatus.inProgress));
    expect(somewhere.containsKey('percent'), isFalse);
  });

  testWidgets('the book being read comes first, the next after it',
      (tester) async {
    final l10n = await _l10n(tester, const Locale('ko'));
    final books = [
      _book('new', ReadingStatus.unread),
      _book('a', ReadingStatus.inProgress),
      _book('done', ReadingStatus.completed),
      _book('b', ReadingStatus.inProgress),
    ];
    final recap = computeReadingRecap(
      books: books,
      readingDays: {MyLibraryDb.dayKey(DateTime(2026, 10, 24)): 3},
      completionDates: {},
      now: DateTime(2026, 10, 24, 9),
    );
    final snap = widgetSnapshot(
      books: books,
      recap: recap,
      l10n: l10n,
      localeTag: 'ko',
      covers: {'a': '/covers/a.jpg'},
    );
    expect((snap['hero'] as Map)['id'], 'a');
    expect((snap['hero'] as Map)['cover'], '/covers/a.jpg');
    expect((snap['next'] as Map)['id'], 'b');
    expect(snap['total'], 4);
    expect(snap['finished'], 1);
    final labels = snap['labels'] as Map;
    expect(labels['hero'], l10n.libraryContinueReading);
    final r = snap['recap'] as Map;
    expect(r['streak'], '1${l10n.recapDaysUnit}');
    expect(r['streakOn'], isTrue);
    expect((r['days'] as List).length, ReadingRecap.recentDayCount);
    expect(r['month'], contains('10'));
  });

  testWidgets('nothing being read: the newest book; no record without one',
      (tester) async {
    final l10n = await _l10n(tester, const Locale('en'));
    final snap = widgetSnapshot(
      books: [_book('x', ReadingStatus.unread)],
      recap: null,
      l10n: l10n,
      localeTag: 'en',
      covers: const {},
    );
    expect((snap['hero'] as Map)['id'], 'x');
    expect(snap['next'], isNull);
    expect(snap['recap'], isNull);
    expect((snap['labels'] as Map)['hero'], l10n.libraryRecentlyAdded);
  });

  test('a widget tap becomes an action', () {
    expect(WidgetAction.fromMap({'bookId': 'abc'})?.bookId, 'abc');
    expect(WidgetAction.fromMap({'library': true})?.library, isTrue);
    expect(WidgetAction.fromMap(null), isNull);
    expect(WidgetAction.fromMap({'bookId': ''}), isNull);
  });
}
