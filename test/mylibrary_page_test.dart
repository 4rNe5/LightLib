// The library page end to end on a real (ffi) database: header, bento
// panel, cover grid, and setting a genre from the long-press sheet.

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
      for (final t in ['mybooks', 'bookposition', 'booktags', 'bookgenre']) {
        await database.delete(t);
      }
      await db.insert(_book('a', 'First Book'));
      await db.insert(_book('b', 'Second Book'));
      await db.insert(_book('c', 'A third book with a very long title'));
      await db.saveBookState('b.pdf', '5');
    });

    tester.view.physicalSize = const Size(1080, 2340);
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
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }

    expect(tester.takeException(), isNull);
    expect(find.text('My Library'), findsOneWidget);
    expect(find.text('3 books'), findsOneWidget);
    expect(find.byKey(const ValueKey('libraryBento')), findsOneWidget);
    expect(find.text('Continue reading'), findsOneWidget);
    for (final id in ['a', 'b', 'c']) {
      expect(find.byKey(ValueKey('libraryBook-$id')), findsOneWidget);
    }

    // Long-press a cover: the sheet sets the genre, which then shows as a
    // filter chip.
    await tester.longPress(find.byKey(const ValueKey('libraryBook-a')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
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
    expect(find.byKey(const ValueKey('genreFilter-lightNovel')),
        findsOneWidget);

    // Filtering by the genre hides the bento and the other books.
    await tester.tap(find.byKey(const ValueKey('genreFilter-lightNovel')));
    await tester.pump();
    expect(find.byKey(const ValueKey('libraryBento')), findsNothing);
    expect(find.byKey(const ValueKey('libraryBook-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('libraryBook-b')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
