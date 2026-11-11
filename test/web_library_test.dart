// The web's library: the books in the browser and the account's as one
// list, how it is filtered, searched and sorted, a book's card, the
// picture shown while a book comes, and what is kept between visits.

// Dart imports:
import 'dart:typed_data';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/cover_thumbs.dart';
import 'package:openlib/services/database.dart';
import 'package:openlib/services/storage/app_files.dart';
import 'package:openlib/services/storage/idb_app_files.dart';
import 'package:openlib/services/sync/remote_library.dart';
import 'package:openlib/services/sync/sync_engine.dart';
import 'package:openlib/web/web_book_dialog.dart';
import 'package:openlib/web/web_book_opening.dart';
import 'package:openlib/web/web_cover.dart';
import 'package:openlib/web/web_library.dart';
import 'package:openlib/web/web_library_page.dart';

const a = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const b = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const c = 'cccccccccccccccccccccccccccccccc';

MyBook here(String md5, String title, {String author = 'Unknown'}) => MyBook(
      id: 'local_$md5',
      title: title,
      author: author,
      thumbnail: '',
      link: '',
      publisher: '',
      info: '',
      format: 'epub',
      description: '',
      fileName: '$title.epub',
    );

RemoteBook there(String md5, String title,
        {String? author, int day = 1, bool hasCover = false}) =>
    RemoteBook(
      md5: md5,
      bookId: 'local_$md5',
      fileName: '$title.epub',
      title: title,
      author: author,
      sizeBytes: 3 * 1024 * 1024,
      hasFile: true,
      description: 'About $title',
      publisher: 'Press',
      hasCover: hasCover,
      addedAt: DateTime.utc(2026, 11, day),
    );

RemoteProgress read(String md5, int hour,
        {double? fraction, bool done = false}) =>
    RemoteProgress(
        md5: md5,
        position: 'foliate:x',
        completed: done,
        updatedAt: DateTime.utc(2026, 11, 10, hour),
        fraction: fraction);

List<WebBook> merged({
  List<MyBook> local = const [],
  RemoteLibrary remote = const RemoteLibrary(),
  Map<String, double> fractions = const {},
  Map<String, DateTime> readAt = const {},
}) =>
    mergeLibrary(
      local: local,
      remote: remote,
      md5Of: (book) => book.id.substring('local_'.length),
      fractionOf: (book) => fractions[book.title],
      readAtOf: (book) => readAt[book.title],
    );

Widget app(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

class _Library extends WebLibrary {
  _Library(this._list);
  final List<WebBook> _list;

  @override
  List<WebBook>? get books => _list;

  @override
  Future<void> reload() async {}
}

void main() {
  final files = AppFiles.instance;
  setUp(() {
    AppFiles.instance = IdbAppFiles(newIdbFactoryMemory());
    WebCovers.forget();
  });
  tearDown(() {
    AppFiles.instance = files;
    WebCovers.fetchOverride = null;
    WebCovers.readOverride = null;
  });
  // Widgets are drawn without the browser's store behind them.
  void noStore() => setUp(() => WebCovers.readOverride = (_) async => null);

  group('one list from two places', () {
    test('a book in both is listed once, with both sides', () {
      final books = merged(
        local: [here(a, 'A')],
        remote: RemoteLibrary(books: [there(a, 'A'), there(b, 'B')]),
      );
      expect(books.map((x) => x.title), ['A', 'B']);
      expect(books[0].downloaded && books[0].onAccount, isTrue);
      expect(books[1].downloaded, isFalse);
      expect(books[1].sizeBytes, 3 * 1024 * 1024);
      expect(books[1].description, 'About B');
    });

    test('a book only in the browser (not signed in) is listed too', () {
      final books = merged(local: [here(a, 'A')]);
      expect(books.single.onAccount, isFalse);
      expect(books.single.author, '');
    });

    test('how far: the newer reading says, here or on another device', () {
      final remote = RemoteLibrary(
        books: [there(a, 'A'), there(b, 'B'), there(c, 'C')],
        progress: {
          a: read(a, 10, fraction: 0.2),
          b: read(b, 12, fraction: 0.9),
          c: read(c, 9, done: true),
        },
      );
      final books = merged(
        local: [here(a, 'A'), here(b, 'B')],
        remote: remote,
        fractions: {'A': 0.5, 'B': 0.3},
        readAt: {
          'A': DateTime.utc(2026, 11, 10, 11),
          'B': DateTime.utc(2026, 11, 10, 11),
        },
      );
      expect(books[0].fraction, 0.5); // read here later
      expect(books[1].fraction, 0.9); // read elsewhere later
      expect(books[1].readAt, DateTime.utc(2026, 11, 10, 12));
      expect(books[2].finished, isTrue);
    });

    test('a position from before sync kept times is not "read lately"', () {
      final books = merged(
        remote: RemoteLibrary(books: [
          there(a, 'A')
        ], progress: {
          a: RemoteProgress(
              md5: a,
              position: 'foliate:x',
              completed: false,
              updatedAt: unknownAge),
        }),
      );
      expect(books.single.readAt, isNull);
    });
  });

  group('what the library shows', () {
    final remote = RemoteLibrary(
      books: [
        there(a, 'Zeta', author: 'Abe', day: 1),
        there(b, 'Alpha', author: 'Mori', day: 3),
        there(c, 'Mid', author: 'Kato', day: 2),
      ],
      progress: {
        a: read(a, 12, fraction: 0.4),
        b: read(b, 9, done: true),
      },
    );
    final books =
        merged(local: [here(c, 'Mid', author: 'Kato')], remote: remote);

    test('filters', () {
      List<String> shown(WebFilter f) =>
          arrangeLibrary(books, filter: f).map((x) => x.title).toList();
      expect(shown(WebFilter.all), hasLength(3));
      expect(shown(WebFilter.reading), ['Zeta']);
      expect(shown(WebFilter.downloaded), ['Mid']);
      expect(shown(WebFilter.finished), ['Alpha']);
    });

    test('search looks at title, author and publisher', () {
      List<String> found(String q) =>
          arrangeLibrary(books, query: q).map((x) => x.title).toList();
      expect(found('alp'), ['Alpha']);
      expect(found('KATO'), ['Mid']);
      expect(found('press'), hasLength(2));
      expect(found('nothing'), isEmpty);
    });

    test('sorts', () {
      List<String> by(WebSort s) =>
          arrangeLibrary(books, sort: s).map((x) => x.title).toList();
      expect(by(WebSort.recent), ['Zeta', 'Alpha', 'Mid']);
      expect(by(WebSort.title), ['Alpha', 'Mid', 'Zeta']);
      expect(by(WebSort.author), ['Zeta', 'Mid', 'Alpha']);
      expect(by(WebSort.added), ['Alpha', 'Mid', 'Zeta']);
    });

    test('to go on with: the one read last that is not finished', () {
      expect(continueReading(books)!.title, 'Zeta');
      expect(continueReading(merged(local: [here(a, 'A')])), isNull);
    });

    test('sizes read as people say them', () {
      expect(formatBytes(900 * 1024), '900 KB');
      expect(formatBytes(3 * 1024 * 1024), '3 MB');
      expect(formatBytes((8.4 * 1024 * 1024).round()), '8.4 MB');
      expect(formatBytes(250 * 1024 * 1024), '250 MB');
    });
  });

  group('kept between visits', () {
    test('the listed library is there again after a reload', () async {
      final store = RemoteLibraryStore.instance;
      store.update(RemoteLibrary(books: [
        there(a, 'A', hasCover: true)
      ], progress: {
        a: read(a, 10, fraction: 0.5)
      }, translated: {
        a: {'ko': 7}
      }));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final path =
          '${await AppFiles.instance.supportPath()}/remote_library.json';
      final saved = await AppFiles.instance.readString(path);
      expect(saved, contains('"title":"A"'));
      expect(saved, contains('"ko":7'));

      await store.clear();
      expect(store.library.books, isEmpty);
      expect(await AppFiles.instance.exists(path), isFalse);
    });
  });

  group('covers', () {
    final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 1, 2, 3]);

    test('the small cover kept in the browser is used', () async {
      await CoverThumbs.write(a, jpeg);
      final book = merged(remote: RemoteLibrary(books: [there(a, 'A')])).single;
      expect(await WebCovers.of(book), jpeg);
      expect(WebCovers.known(book), jpeg);
    });

    test('the account\'s cover is fetched once and kept', () async {
      var asked = 0;
      WebCovers.fetchOverride = (md5) async {
        asked++;
        return jpeg;
      };
      final book =
          merged(remote: RemoteLibrary(books: [there(a, 'A', hasCover: true)]))
              .single;
      expect(await WebCovers.of(book), jpeg);
      expect(await CoverThumbs.read(a), jpeg);
      WebCovers.forget();
      expect(await WebCovers.of(book), jpeg);
      expect(asked, 1);
    });

    test('a book the account has no cover of is not asked for', () async {
      WebCovers.fetchOverride = (md5) async => fail('asked for $md5');
      final book = merged(remote: RemoteLibrary(books: [there(a, 'A')])).single;
      expect(await WebCovers.of(book), isNull);
    });

    test('many covers are fetched a few at a time', () async {
      var open = 0, most = 0;
      WebCovers.fetchOverride = (md5) async {
        open++;
        most = open > most ? open : most;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        open--;
        return jpeg;
      };
      final books = merged(
          remote: RemoteLibrary(books: [
        for (var i = 0; i < 12; i++)
          there(i.toRadixString(16) * 32, 'B$i', hasCover: true),
      ]));
      await Future.wait(books.map(WebCovers.of));
      expect(most, lessThanOrEqualTo(4));
    });
  });

  group('a book\'s card', () {
    noStore();
    final book = merged(
      remote: RemoteLibrary(books: [
        there(a, 'The Lighthouse', author: 'Mori')
      ], progress: {
        a: read(a, 10, fraction: 0.37)
      }, translated: {
        a: {'ko': 1234}
      }),
    ).single;

    Future<WebBookAction?> open(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      WebBookAction? result;
      await tester.pumpWidget(app(Builder(
        builder: (context) => Scaffold(
          body: TextButton(
              onPressed: () async =>
                  result = await showWebBookDialog(context, book),
              child: const Text('open')),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('webBookDialog')), findsOneWidget);
      expect(
          tester.widget<Text>(find.byKey(const ValueKey('webBookTitle'))).data,
          'The Lighthouse');
      expect(find.text('Mori'), findsOneWidget);
      expect(find.text('In your account'), findsOneWidget);
      expect(find.text('37% read'), findsOneWidget);
      expect(find.textContaining('1234 paragraphs translated'), findsOneWidget);
      expect(find.text('About The Lighthouse'), findsOneWidget);
      // Started and not finished: the button goes on with it.
      await tester.tap(find.byKey(const ValueKey('webBookRead')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      return result;
    }

    testWidgets('a wide window: cover beside the details', (tester) async {
      expect(await open(tester, const Size(1440, 900)), WebBookAction.read);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a phone: stacked, nothing overflows', (tester) async {
      expect(await open(tester, const Size(360, 640)), WebBookAction.read);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the menu: only what applies to the book', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(Builder(
        builder: (context) => Scaffold(
          body: TextButton(
              onPressed: () => showWebBookDialog(context, book),
              child: const Text('open')),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('webBookMore')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // Not in this browser: nothing to remove from it.
      expect(find.text('Remove from this browser'), findsNothing);
      expect(find.text('Delete from library'), findsOneWidget);
    });
  });

  group('while a book comes', () {
    noStore();
    final book =
        merged(remote: RemoteLibrary(books: [there(a, 'A Long Title')])).single;

    testWidgets('its name, what is happening and how far', (tester) async {
      await tester.pumpWidget(app(WebBookOpening(
          book: book,
          label: 'Downloading…',
          progress: 0.4,
          detail: '3.1 MB / 8.4 MB')));
      await tester.pump();
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('webOpeningTitle')))
              .data,
          'A Long Title');
      expect(find.text('Downloading…'), findsOneWidget);
      expect(find.text('3.1 MB / 8.4 MB'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
          find.byKey(const ValueKey('webOpeningBar')));
      expect(bar.value, 0.4);
    });

    testWidgets('it failed: said, with a way to try again', (tester) async {
      var retried = 0;
      await tester.pumpWidget(app(WebBookOpening(
          book: book,
          label: 'Could not load this book.',
          error: true,
          onRetry: () => retried++,
          onClose: () {})));
      await tester.pump();
      expect(find.byKey(const ValueKey('webOpeningBar')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('webOpeningRetry')));
      expect(retried, 1);
    });
  });

  group('the library page', () {
    noStore();
    // What the last visit listed: read once, before any widget asks.
    setUpAll(() async {
      final real = AppFiles.instance;
      AppFiles.instance = IdbAppFiles(newIdbFactoryMemory());
      await RemoteLibraryStore.instance.load();
      AppFiles.instance = real;
    });
    final books = merged(
      local: [here(c, 'Here Too')],
      remote: RemoteLibrary(books: [
        there(a, 'Cloud Book', author: 'Mori'),
        there(b, 'Other Book'),
        there(c, 'Here Too'),
      ], progress: {
        a: read(a, 10, fraction: 0.4)
      }),
    );

    Future<void> show(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(WebLibraryPage(library: _Library(books))));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('a desktop window: side bar, search, the last book to go on',
        (tester) async {
      await show(tester, const Size(1440, 900));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('webFilter:reading')), findsOneWidget);
      expect(find.byKey(const ValueKey('webSearch')), findsOneWidget);
      expect(find.byKey(const ValueKey('webContinue')), findsOneWidget);
      expect(find.byKey(const ValueKey('webBook:$a')), findsOneWidget);
      // Not in this browser: marked; the one that is, not.
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('webBook:$a')),
              matching: find.byKey(const ValueKey('webBookCloud'))),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('webBook:$c')),
              matching: find.byKey(const ValueKey('webBookCloud'))),
          findsNothing);

      await tester.enterText(find.byKey(const ValueKey('webSearch')), 'other');
      await tester.pump();
      expect(find.byKey(const ValueKey('webBook:$b')), findsOneWidget);
      expect(find.byKey(const ValueKey('webBook:$a')), findsNothing);
      // Searching: the "go on" card steps aside.
      expect(find.byKey(const ValueKey('webContinue')), findsNothing);

      await tester.enterText(find.byKey(const ValueKey('webSearch')), '');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('webFilter:downloaded')));
      await tester.pump();
      expect(find.byKey(const ValueKey('webBook:$c')), findsOneWidget);
      expect(find.byKey(const ValueKey('webBook:$a')), findsNothing);
    });

    testWidgets('a tile opens the book\'s card', (tester) async {
      await show(tester, const Size(1440, 900));
      await tester.tap(find.byKey(const ValueKey('webBook:$b')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('webBookDialog')), findsOneWidget);
      expect(find.byKey(const ValueKey('webBookRead')), findsOneWidget);
    });

    testWidgets('a phone: the same library under an app bar', (tester) async {
      await show(tester, const Size(390, 800));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('webAddBooks')), findsOneWidget);
      expect(find.byKey(const ValueKey('webFilter:all')), findsOneWidget);
      expect(find.byKey(const ValueKey('webBook:$a')), findsOneWidget);
      expect(find.byKey(const ValueKey('webSearch')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('webSearchOpen')));
      await tester.pump();
      expect(find.byKey(const ValueKey('webSearch')), findsOneWidget);
    });

    testWidgets('no books anywhere: said so', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(WebLibraryPage(library: _Library(const []))));
      await tester.pump();
      expect(find.byKey(const ValueKey('webLibraryEmpty')), findsOneWidget);
    });
  });
}
