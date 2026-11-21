// The order of screens round a library book: the tabs, the book's page,
// the reader - whatever led to the book. A book asked for from outside
// (a home-screen widget) takes the place of what is open, so "back"
// never lands in another book's reader; where the shelf and a book fit
// side by side, the book goes to the pane beside the shelf.

// Flutter imports:
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/database.dart';
import 'package:openlib/services/library_organization.dart';
import 'package:openlib/state/state.dart';
import 'package:openlib/ui/adaptive.dart';
import 'package:openlib/ui/book_navigation.dart';
import 'package:openlib/ui/components/book_detail.dart';
import 'package:openlib/ui/mybook_page.dart';

LibraryBook _book(String id,
        {ReadingStatus status = ReadingStatus.unread, double? fraction}) =>
    LibraryBook(
      status: status,
      fraction: fraction,
      book: MyBook(
        id: id,
        title: 'Book $id',
        author: 'Writer',
        thumbnail: null,
        link: 'https://example.com/$id',
        publisher: null,
        info: null,
        // (Not an EPUB: the page then has no translation card, which
        // asks the device about its engines.)
        format: 'cbz',
        description: null,
      ),
    );

final _books = [
  _book('a', status: ReadingStatus.inProgress, fraction: 0.62),
  _book('b'),
];

late WidgetRef _ref;
late BuildContext _root;

Widget _app() => ProviderScope(
      overrides: [
        libraryBooksProvider.overrideWith((ref) async => _books),
        completionDatesProvider
            .overrideWith((ref) async => <String, DateTime>{}),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Consumer(builder: (context, ref, _) {
          _ref = ref;
          _root = context;
          return Scaffold(
            body: Center(
                child: Text('TABS ${ref.watch(libraryDetailProvider)}')),
          );
        }),
      ),
    );

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(411, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _unfolded(WidgetTester tester) async {
  tester.view.physicalSize = const Size(750, 832);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// A reader's place in the stack (the reader itself needs a web view).
Route<void> _reader(String id) => MaterialPageRoute<void>(
      settings: RouteSettings(name: readerRouteName(id)),
      builder: (_) => Scaffold(body: Text('READER $id')),
    );

/// The names of the routes from the top down, by going back.
Future<List<String?>> _backToTheTabs(WidgetTester tester) async {
  final navigator = Navigator.of(_root);
  final names = <String?>[];
  while (true) {
    final top = topRouteOf(navigator)!;
    if (top.isFirst) break;
    names.add(top.settings.name);
    navigator.pop();
    await tester.pumpAndSettle();
  }
  return names;
}

void main() {
  testWidgets('a widget\'s book over another book\'s reader: in its place',
      (tester) async {
    await _phone(tester);
    await tester.pumpWidget(_app());
    final navigator = Navigator.of(_root);
    // Reading book a, opened from its page.
    pushBookPage(navigator, 'a');
    navigator.push(_reader('a'));
    await tester.pumpAndSettle();
    expect(find.text('READER a'), findsOneWidget);

    // The home-screen widget of book b is tapped.
    showBookFromOutside(_root, _ref, 'b');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bookDetail-b')), findsOneWidget);
    expect(find.text('READER a'), findsNothing);
    // Back from there is the tabs: book a's reader is not underneath.
    expect(await _backToTheTabs(tester), [bookRouteName('b')]);
    expect(find.textContaining('TABS'), findsOneWidget);
  });

  testWidgets('the widget of the book being read changes nothing',
      (tester) async {
    await _phone(tester);
    await tester.pumpWidget(_app());
    final navigator = Navigator.of(_root);
    pushBookPage(navigator, 'a');
    navigator.push(_reader('a'));
    await tester.pumpAndSettle();
    showBookFromOutside(_root, _ref, 'a');
    await tester.pumpAndSettle();
    expect(find.text('READER a'), findsOneWidget);
    expect(await _backToTheTabs(tester),
        [readerRouteName('a'), bookRouteName('a')]);
  });

  testWidgets('tapped twice, a widget\'s book is one page, not two',
      (tester) async {
    await _phone(tester);
    await tester.pumpWidget(_app());
    showBookFromOutside(_root, _ref, 'b');
    await tester.pumpAndSettle();
    showBookFromOutside(_root, _ref, 'b');
    await tester.pumpAndSettle();
    expect(await _backToTheTabs(tester), [bookRouteName('b')]);
  });

  testWidgets('a sheet open over a book is closed with it', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(_app());
    pushBookPage(Navigator.of(_root), 'a');
    await tester.pumpAndSettle();
    showModalBottomSheet<void>(
        context: tester.element(find.byType(BookPage)),
        builder: (_) => const Text('SHEET'));
    await tester.pumpAndSettle();
    expect(find.text('SHEET'), findsOneWidget);
    showBookFromOutside(_root, _ref, 'b');
    await tester.pumpAndSettle();
    expect(find.text('SHEET'), findsNothing);
    expect(await _backToTheTabs(tester), [bookRouteName('b')]);
  });

  testWidgets('unfolded, a widget\'s book goes to the pane beside the shelf',
      (tester) async {
    await _unfolded(tester);
    await tester.pumpWidget(_app());
    Navigator.of(_root).push(_reader('a'));
    await tester.pumpAndSettle();
    showBookFromOutside(_root, _ref, 'b');
    await tester.pumpAndSettle();
    // No page over the tabs: the library shows it.
    expect(find.text('TABS b'), findsOneWidget);
    expect(find.byType(BookPage), findsNothing);
  });

  testWidgets('a book\'s page shows how far it was read and goes on from it',
      (tester) async {
    await _phone(tester);
    await tester.pumpWidget(_app());
    pushBookPage(Navigator.of(_root), 'a');
    await tester.pumpAndSettle();
    expect(find.text('62% read'), findsOneWidget);
    expect(find.text('Continue from 62%'), findsOneWidget);
    expect(find.text('Mark as finished'), findsOneWidget);
    Navigator.of(_root).pop();
    await tester.pumpAndSettle();
    pushBookPage(Navigator.of(_root), 'b');
    await tester.pumpAndSettle();
    expect(find.text('Not started'), findsOneWidget);
    expect(find.text('Read'), findsOneWidget);
  });

  testWidgets('unfolding with a book\'s page up: it steps into the pane',
      (tester) async {
    await _phone(tester);
    await tester.pumpWidget(_app());
    pushBookPage(Navigator.of(_root), 'a');
    await tester.pumpAndSettle();
    expect(find.byType(BookPage), findsOneWidget);
    // The phone is unfolded.
    tester.view.physicalSize = const Size(750, 832);
    await tester.pumpAndSettle();
    expect(find.byType(BookPage), findsNothing);
    expect(find.text('TABS a'), findsOneWidget);
  });

  testWidgets('unfolding while reading: the page under the reader steps '
      'away too, and "back" is the shelf with the book beside it',
      (tester) async {
    await _phone(tester);
    await tester.pumpWidget(_app());
    final navigator = Navigator.of(_root);
    pushBookPage(navigator, 'a');
    navigator.push(_reader('a'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(750, 832);
    await tester.pumpAndSettle();
    expect(find.text('READER a'), findsOneWidget);
    expect(await _backToTheTabs(tester), [readerRouteName('a')]);
    expect(find.text('TABS a'), findsOneWidget);
  });

  group('two panes', () {
    Future<double> endWidth(WidgetTester tester,
        {required Size screen, double? foldAt, double trailing = 0}) async {
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1;
      tester.view.displayFeatures = [
        if (foldAt != null)
          ui.DisplayFeature(
            bounds: Rect.fromLTWH(foldAt, 0, 0, screen.height),
            type: ui.DisplayFeatureType.fold,
            state: ui.DisplayFeatureState.postureFlat,
          ),
      ];
      addTearDown(tester.view.reset);
      late double width;
      await tester.pumpWidget(MaterialApp(
        home: Row(
          children: [
            Expanded(
              child: TwoPane(
                trailing: trailing,
                start: const SizedBox(),
                end: LayoutBuilder(builder: (context, constraints) {
                  width = constraints.maxWidth;
                  return const SizedBox();
                }),
              ),
            ),
            SizedBox(width: trailing),
          ],
        ),
      ));
      return width;
    }

    testWidgets('meet at the fold of an unfolded screen', (tester) async {
      // The end pane: from just past the fold to the tabs' rail.
      expect(
          await endWidth(tester,
              screen: const Size(750, 832), foldAt: 375, trailing: 80),
          750 - 375 - 6 - 80);
    });

    testWidgets('share the width where nothing folds', (tester) async {
      final width =
          await endWidth(tester, screen: const Size(1280, 800), trailing: 80);
      expect(width, 460); // 46% of 1200, at most 460
    });

    testWidgets('a fold that runs across divides nothing side by side',
        (tester) async {
      tester.view.physicalSize = const Size(832, 750);
      tester.view.devicePixelRatio = 1;
      tester.view.displayFeatures = [
        const ui.DisplayFeature(
          bounds: Rect.fromLTWH(0, 375, 832, 0),
          type: ui.DisplayFeatureType.fold,
          state: ui.DisplayFeatureState.postureHalfOpened,
        ),
      ];
      addTearDown(tester.view.reset);
      late Rect? down, across;
      late bool half;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
        down = verticalFoldOf(context);
        across = horizontalFoldOf(context);
        half = isHalfOpened(context);
        return const SizedBox();
      })));
      expect(down, isNull);
      expect(across, const Rect.fromLTWH(0, 375, 832, 0));
      expect(half, isTrue);
    });

    testWidgets('one pane on a phone, two from 600 wide', (tester) async {
      Future<bool> at(Size size) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        late bool two;
        await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
          two = useTwoPanes(context);
          return const SizedBox();
        })));
        return two;
      }

      addTearDown(tester.view.reset);
      expect(await at(const Size(411, 914)), isFalse);
      expect(await at(const Size(750, 832)), isTrue);
    });
  });
}
