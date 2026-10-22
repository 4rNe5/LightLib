// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/annas_archieve.dart';
import 'package:openlib/services/search_manager.dart';
import 'package:openlib/ui/components/zlib_recommendations_widget.dart';

// Kept apart from zlib_recommendations_test.dart: testWidgets swaps in a
// binding whose HttpClient answers every request with 400, which would
// break that file's local-server tests.
void main() {
  const base = 'https://z-lib.example';

  testWidgets('renders the heading and covers; tapping opens the book',
      (tester) async {
    final recs = ZlibraryRecommendations(
      books: [
        for (final id in ['A1', 'B2', 'C3'])
          BookData(title: 'Book $id', link: '$base/book/$id/x.html', md5: id),
      ],
      bookIds: const [],
      onPage: 21,
      page: 2,
      mirror: base,
      hasMore: false,
    );
    BookData? opened;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: ZlibRecommendationsWidget(
            initial: recs,
            onOpen: (b) => opened = b,
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('You may be interested in'), findsOneWidget);
    expect(find.byKey(const ValueKey('zlibRecommendationsLoadMore')),
        findsNothing);
    // No cover URL: the title stands in for the cover.
    // The ripple layer above the cover takes the tap.
    await tester.tap(find.text('Book B2'), warnIfMissed: false);
    expect(opened?.md5, 'B2');
  });

  testWidgets('holds back a partial row, then Load more appends the page',
      (tester) async {
    BookData book(String id) =>
        BookData(title: 'Book $id', link: '$base/book/$id/x.html', md5: id);
    final recs = ZlibraryRecommendations(
      books: [for (var i = 1; i <= 6; i++) book('A$i')],
      bookIds: const [1, 2, 3],
      onPage: 21,
      page: 2,
      mirror: base,
      hasMore: true,
    );
    final fake = _FakeProvider((current) => current.copyWith(
          books: [
            ...current.books,
            for (var i = 1; i <= 4; i++) book('B$i'),
          ],
          page: current.page + 1,
          hasMore: false,
        ));
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: ZlibRecommendationsWidget(
            initial: recs,
            onOpen: (_) {},
            provider: fake,
          ),
        ),
      ),
    ));
    await tester.pump();

    // 800 px wide -> 5 columns; the 6th book waits for a full row.
    expect(find.text('Book A5'), findsOneWidget);
    expect(find.text('Book A6'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('zlibRecommendationsLoadMore')));
    await tester.pump();
    await tester.pump();

    expect(fake.calls, 1);
    expect(find.text('Book A6'), findsOneWidget);
    expect(find.text('Book B4'), findsOneWidget);
    // Last page: everything shows and the button is gone.
    expect(find.byKey(const ValueKey('zlibRecommendationsLoadMore')),
        findsNothing);
  });

  testWidgets('an empty mosaic loads its first page by itself', (tester) async {
    final fake = _FakeProvider((current) => current.copyWith(
          books: [
            BookData(title: 'Auto 1', link: '$base/book/X1/x.html', md5: 'X1'),
          ],
          page: current.page + 1,
          hasMore: false,
        ));
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: ZlibRecommendationsWidget(
            initial: const ZlibraryRecommendations(
              books: [],
              bookIds: [1],
              onPage: 21,
              page: 0,
              mirror: base,
              hasMore: true,
            ),
            onOpen: (_) {},
            provider: fake,
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(fake.calls, 1);
    expect(find.text('Auto 1'), findsOneWidget);
  });

  testWidgets('nothing to show and nothing to fetch renders nothing',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ZlibRecommendationsWidget(
          initial: const ZlibraryRecommendations(
            books: [],
            bookIds: [],
            onPage: 0,
            page: 0,
            mirror: base,
            hasMore: false,
          ),
          onOpen: (_) {},
        ),
      ),
    ));
    expect(find.text('You may be interested in'), findsNothing);
  });
}

class _FakeProvider extends ZlibraryProvider {
  _FakeProvider(this.next) : super(mirrors: const []);

  final ZlibraryRecommendations Function(ZlibraryRecommendations) next;
  int calls = 0;

  @override
  Future<ZlibraryRecommendations> loadMoreRecommendations(
      ZlibraryRecommendations current) async {
    calls++;
    return next(current);
  }
}
