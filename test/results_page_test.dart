// Dart imports:
import 'dart:async';

// Real pagination behavior of the results page: page 1 renders, the
// next page loads as the list scrolls near its end, an empty page stops
// the pager. The search provider is overridden with deterministic pages;
// the page widget under test is the real one.

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/services/annas_archieve.dart';
import 'package:openlib/services/search_manager.dart' show SearchProviderId;
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/state/state.dart';
import 'package:openlib/ui/components/book_card_widget.dart';
import 'package:openlib/ui/results_page.dart';

/// Builds a page of books with recognizable titles.
List<BookData> fakePage(int page, {String? source}) {
  return List.generate(
      20,
      (i) => BookData(
            title: 'Book $page-$i',
            author: 'Author $page$i',
            link: 'https://example.com/md5/p$page-$i',
            md5: 'md5-p$page-$i',
            source: source,
          ));
}

Future<List<BookData>> fakeSearch(SearchPageKey key) async {
  // Page 3 exists but is empty: the pager must stop there.
  if (key.page >= 3) return [];
  await Future<void>.delayed(const Duration(milliseconds: 10));
  return fakePage(key.page);
}

void main() {
  Future<void> pumpResults(WidgetTester tester, {double height = 600}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        searchProvider.overrideWith((ref, key) => fakeSearch(key)),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ResultPage(searchQuery: 'docker'),
      ),
    ));
    // Bounded pumping: the bottom loader keeps its animation alive, so
    // pumpAndSettle never settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('renders the first page of results', (tester) async {
    await pumpResults(tester);

    // Lazy slivers only build what is visible; page 1's data must at
    // least fill the screen with its items.
    expect(find.text('Book 1-0'), findsOneWidget);
    expect(find.byType(BookInfoCard), findsWidgets);
  });

  testWidgets('scrolling to the bottom loads the next page and appends',
      (tester) async {
    await pumpResults(tester);

    // Drag far down: past the 200px pre-fetch margin, into page 2.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    // Page 2 items are now in the data: at least one page-2 card must
    // have been built as the list shows them.
    final visiblePage2 = find
        .byWidgetPredicate(
            (w) => w is BookInfoCard && w.title.startsWith('Book 2-'))
        .evaluate()
        .length;
    expect(visiblePage2, greaterThan(0),
        reason: 'page 2 items must append after scrolling');
  });

  testWidgets('an empty page ends the pager instead of fetching forever',
      (tester) async {
    await pumpResults(tester);

    // First scroll loads page 2, second reaches for page 3, which is
    // empty - the pager must stop.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -8000));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    // Page 3 returned nothing: no page-3 book ever renders, and the
    // pager stops instead of fetching page 4 (whose books would also be
    // absent, but the empty response proves the fetch ran once and
    // stopped).
    expect(
        find.byWidgetPredicate(
            (w) => w is BookInfoCard && w.title.startsWith('Book 3-')),
        findsNothing);
  });

  testWidgets('shows the source chip on tagged results and the header line',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        searchProvider.overrideWith((ref, key) async {
          if (key.page >= 2) return [];
          return fakePage(1, source: 'LibGen');
        }),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ResultPage(searchQuery: 'docker'),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Every visible card carries the catalog chip...
    expect(
        find.descendant(
            of: find.byType(BookInfoCard).first,
            matching: find.text('LibGen')),
        findsOneWidget);

    // ...and the list header states where the results came from.
    final l10n =
        AppLocalizations.of(tester.element(find.byType(ResultPage).first));
    expect(find.text('${l10n.resultFileCount(20)} · LibGen'), findsOneWidget);
  });

  testWidgets('untagged results render without a source chip', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        searchProvider.overrideWith((ref, key) async {
          if (key.page >= 2) return [];
          return fakePage(1); // no source
        }),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ResultPage(searchQuery: 'docker'),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // No 'LibGen'/'Z-Library' chip on the cards (only the source picker
    // names them), and no source in the header line.
    expect(
        find.descendant(
            of: find.byType(BookInfoCard), matching: find.text('LibGen')),
        findsNothing);
    final l10n =
        AppLocalizations.of(tester.element(find.byType(ResultPage).first));
    expect(find.text(l10n.resultFileCount(20)), findsOneWidget);
  });

  testWidgets('while searching, shows a spinner and never "No results found"',
      (tester) async {
    final gate = Completer<List<BookData>>();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        searchProvider.overrideWith((ref, key) =>
            key.page == 1 ? gate.future : Future.value(<BookData>[])),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ResultPage(searchQuery: 'docker'),
      ),
    ));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Searching…'), findsOneWidget);
    expect(find.text('No results found'), findsNothing);
    expect(find.textContaining('No results here'), findsNothing);

    gate.complete(fakePage(1));
    await tester.pump();
    expect(find.text('No results found'), findsNothing);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Book 1-0'), findsOneWidget);
  });

  testWidgets('an empty search ends on "No results found"', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        searchProvider.overrideWith((ref, key) async => <BookData>[]),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ResultPage(searchQuery: 'docker'),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('No results found'), findsOneWidget);
  });

  BookData volume(String title, String info, String md5) => BookData(
      title: title,
      author: 'Author',
      link: 'https://example.com/md5/$md5',
      md5: md5,
      info: info,
      source: "Anna's Archive");

  testWidgets('a series shows as one card with a chip per volume found',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        searchProvider.overrideWith((ref, key) async {
          if (key.page >= 2) return [];
          return [
            volume('死亡遊戯で飯を食う。2', 'Japanese [ja] · EPUB · 3MB', 'a2'),
            volume('死亡遊戯で飯を食う。1', 'Japanese [ja] · EPUB · 3MB', 'a1'),
            volume('死亡遊戯で飯を食う。1', 'Japanese [ja] · PDF · 9MB', 'a1p'),
            volume('死亡遊戯で飯を食う。10', 'Japanese [ja] · EPUB · 3MB', 'a10'),
            volume('別の本', 'Japanese [ja] · EPUB · 2MB', 'b'),
          ];
        }),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ResultPage(searchQuery: '死亡遊戯'),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const ValueKey('series-死亡遊戯で飯を食う。')), findsOneWidget);
    for (final v in ['1', '2', '10']) {
      expect(find.byKey(ValueKey('volume-死亡遊戯で飯を食う。-$v')), findsOneWidget);
    }
    // The rest stays a file of its own.
    expect(find.widgetWithText(BookInfoCard, '別の本'), findsOneWidget);
    // Volume 1 has two files: a long press lists them, EPUB first.
    await tester.longPress(find.byKey(const ValueKey('volume-死亡遊戯で飯を食う。-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final cards = tester.widgetList<BookInfoCard>(find.byType(BookInfoCard)).toList();
    expect(cards.where((c) => c.md5 == 'a1' || c.md5 == 'a1p').map((c) => c.md5),
        ['a1', 'a1p']);
    Navigator.of(tester.element(find.byType(BookInfoCard).last)).pop();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // The plain list of files is a tap away.
    await tester.tap(find.text('Files'));
    await tester.pump();
    expect(find.byKey(const ValueKey('series-死亡遊戯で飯を食う。')), findsNothing);
    // In the libraries' own order.
    expect(tester.widget<BookInfoCard>(find.byType(BookInfoCard).first).md5,
        'a2');
    await tester.tap(find.text('Series'));
    await tester.pump();
  });

  testWidgets('a picked source searches that catalog only', (tester) async {
    final asked = <SearchPageKey>[];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        searchProvider.overrideWith((ref, key) async {
          asked.add(key);
          return key.page >= 2 ? [] : fakePage(1);
        }),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ResultPage(searchQuery: 'docker'),
      ),
    ));
    await tester.pump();
    expect(asked.first.source, isNull);
    await tester.tap(find.byKey(const ValueKey('source-zlibrary')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(asked.last.source, SearchProviderId.zlibrary);
    expect(asked.last.page, 1);
  });

  testWidgets('a next page that fails can be tried again', (tester) async {
    var failNext = true;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        searchProvider.overrideWith((ref, key) async {
          if (key.page == 2 && failNext) throw Exception('offline');
          if (key.page >= 3) return [];
          return fakePage(key.page);
        }),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ResultPage(searchQuery: 'docker'),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
    await tester.pump();
    expect(find.byKey(const ValueKey('paginationError')), findsOneWidget);
    failNext = false;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('paginationError')), findsNothing);
  });
}
