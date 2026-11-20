// The library page end to end on a real (ffi) database: header, bento
// panel, cover grid, choosing books by a long press (a genre for one,
// a series of several).

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
import 'package:openlib/services/database.dart';
import 'package:openlib/ui/mylibrary_page.dart';

class _FakePathProvider extends PathProviderPlatform {
  Future<String> _dir(String name) async {
    final dir = Directory('/tmp/openlib_mylibrary_test/$name');
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

MyBook _book(String id, String title) => MyBook(
      id: id,
      title: title,
      author: 'Writer',
      thumbnail: null,
      link: 'https://example.com/$id',
      publisher: null,
      info: null,
      format: 'pdf',
      description: null,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    PathProviderPlatform.instance = _FakePathProvider();
  });

  testWidgets('library shows header, bento and grid; long-press sets genre',
      (tester) async {
    final db = MyLibraryDb.instance;
    await tester.runAsync(() async {
      final database = await db.database;
      for (final t in [
        'mybooks',
        'bookposition',
        'booktags',
        'bookgenre',
        'bookseries'
      ]) {
        await database.delete(t);
      }
      await db.insert(_book('a', 'First Book'));
      await db.insert(_book('b', 'Second Book'));
      await db.insert(_book('c', 'A third book with a very long title'));
      await db.saveBookState('b.pdf', '5');
    });

    // Tall enough for header, bento, reading record and the first grid
    // row without scrolling (scrolling to the end on desktop syncs the
    // library with the storage folder, which drops these file-less
    // books).
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const Scaffold(body: MyLibraryPage()),
      ),
    ));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }

    expect(tester.takeException(), isNull);
    expect(find.text('My Library'), findsOneWidget);
    expect(find.text('3 books'), findsOneWidget);
    expect(find.byKey(const ValueKey('libraryBento')), findsOneWidget);
    expect(find.text('Continue reading'), findsOneWidget);
    expect(find.byKey(const ValueKey('libraryRecap')), findsOneWidget);
    expect(find.byKey(const ValueKey('recapMilestone')), findsOneWidget);
    expect(find.byKey(const ValueKey('recapStreak')), findsOneWidget);
    for (final id in ['a', 'b', 'c']) {
      expect(find.byKey(ValueKey('libraryBook-$id')), findsOneWidget);
    }

    // Long-press a cover: the book is chosen, and with one book chosen
    // its sheet can be opened. The sheet sets the genre, which then
    // shows as a filter chip.
    expect(find.byKey(const ValueKey('librarySelectionBar')), findsNothing);
    await tester.longPress(find.byKey(const ValueKey('libraryBook-a')));
    await tester.pump();
    expect(find.byKey(const ValueKey('librarySelectionBar')), findsOneWidget);
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('librarySelectionTags')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('librarySelectionBar')), findsNothing);
    expect(find.text('Genre'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('genreChoice-lightNovel')));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(await tester.runAsync(() => db.getGenre('a')), 'lightNovel');

    Navigator.of(tester.element(find.text('Genre'))).pop();
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(
        find.byKey(const ValueKey('genreFilter-lightNovel')), findsOneWidget);

    // Filtering by the genre hides the bento and the other books.
    await tester.tap(find.byKey(const ValueKey('genreFilter-lightNovel')));
    await tester.pump();
    expect(find.byKey(const ValueKey('libraryBento')), findsNothing);
    expect(find.byKey(const ValueKey('libraryBook-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('libraryBook-b')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'books chosen by a long press become a series: one row for '
      'its volumes, in order, and out of the grid', (tester) async {
    final db = MyLibraryDb.instance;
    await tester.runAsync(() async {
      final database = await db.database;
      for (final t in [
        'mybooks',
        'bookposition',
        'booktags',
        'bookgenre',
        'bookseries'
      ]) {
        await database.delete(t);
      }
      await db.insert(_book('v2', 'A Tale 2'));
      await db.insert(_book('v1', 'A Tale 1'));
      await db.insert(_book('x', 'Another Book'));
    });
    tester.view.physicalSize = const Size(1080, 4800);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
    }

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const Scaffold(body: MyLibraryPage()),
      ),
    ));
    await settle();
    expect(find.text('Series'), findsNothing);

    // The first by a long press, the next by a tap.
    await tester.longPress(find.byKey(const ValueKey('libraryBook-v2')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('libraryBook-v1')));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);
    // One book only has a sheet of its own; nothing to take out yet.
    expect(find.byKey(const ValueKey('librarySelectionTags')), findsNothing);
    expect(find.byKey(const ValueKey('seriesUngroup')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('seriesGroup')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // The name their titles give is offered.
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('seriesName')))
            .controller!
            .text,
        'A Tale');
    await tester.tap(find.byKey(const ValueKey('seriesNameSave')));
    await settle();

    expect(await tester.runAsync(db.getSeriesForAll),
        {'v1': 'A Tale', 'v2': 'A Tale'});
    expect(find.byKey(const ValueKey('librarySelectionBar')), findsNothing);
    expect(find.text('Series'), findsOneWidget);
    final row = find.byKey(const ValueKey('librarySeries-A Tale'));
    // The series' glossary, without opening a volume.
    expect(
        find.descendant(
            of: row,
            matching: find.byKey(const ValueKey('seriesGlossary-A Tale'))),
        findsOneWidget);
    expect(row, findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('2 volumes')),
        findsOneWidget);
    // Volume 1 before volume 2, whatever order they were added in.
    final first = find.descendant(
        of: row, matching: find.byKey(const ValueKey('libraryBook-v1')));
    final second = find.descendant(
        of: row, matching: find.byKey(const ValueKey('libraryBook-v2')));
    expect(tester.getTopLeft(first).dx, lessThan(tester.getTopLeft(second).dx));
    // Each book once: the series' in its row, the other in the grid.
    expect(find.byKey(const ValueKey('libraryBook-v1')), findsOneWidget);
    expect(find.byKey(const ValueKey('libraryBook-x')), findsOneWidget);
    expect(
        find.descendant(
            of: row, matching: find.byKey(const ValueKey('libraryBook-x'))),
        findsNothing);

    // Taken out again: back in the grid, and the row is gone with its
    // last... two volumes.
    await tester.longPress(first);
    await tester.pump();
    await tester.tap(second);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('seriesUngroup')));
    await settle();
    expect(await tester.runAsync(db.getSeriesForAll), isEmpty);
    expect(find.text('Series'), findsNothing);
    expect(find.byKey(const ValueKey('libraryBook-v1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
