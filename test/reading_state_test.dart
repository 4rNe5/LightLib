// How far a book was read, as the library shows it: kept through
// position saves and the finished mark, ordered by what was read last,
// and told to whoever shows it when a reader is left.

// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter_test/flutter_test.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/library_organization.dart';
import 'package:openlib/state/state.dart';

class _Paths extends PathProviderPlatform {
  Future<String> _dir(String name) async {
    final dir = Directory('/tmp/openlib_reading_state_test/$name');
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

MyBook _book(String id) => MyBook(
      id: id,
      title: 'Title $id',
      author: 'Writer',
      thumbnail: null,
      link: 'https://example.com/$id',
      publisher: null,
      info: null,
      format: 'epub',
      description: null,
    );

LibraryBook _reading(String id, {DateTime? at, double? fraction}) =>
    LibraryBook(
        book: _book(id),
        status: ReadingStatus.inProgress,
        readAt: at,
        fraction: fraction);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final db = MyLibraryDb.instance;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    PathProviderPlatform.instance = _Paths();
  });

  setUp(() async {
    final database = await db.database;
    for (final t in [
      'mybooks',
      'bookposition',
      'syncstate',
      'completions',
      'readingdays'
    ]) {
      await database.delete(t);
    }
  });

  group('the finished mark and the position', () {
    test('a position saved in a finished book leaves it finished', () async {
      await db.saveBookState('a.epub', 'reader:epubcfi(/6/4)');
      await db.setCompleted('a.epub', true, DateTime(2026, 11, 20));
      // (Read again, or turned back a page.)
      await db.saveBookState('a.epub', 'reader:epubcfi(/6/2)');
      final row = await db.getBookRow('a.epub');
      expect(row!.completed, isTrue);
      expect(row.position, 'reader:epubcfi(/6/2)');
      expect((await db.getCompletionDates())['a.epub'], DateTime(2026, 11, 20));
    });

    test('marking a book finished keeps where the reader was', () async {
      await db.saveBookState('a.epub', 'reader:epubcfi(/6/40)');
      await db.setCompleted('a.epub', true);
      expect((await db.getBookRow('a.epub'))!.position,
          'reader:epubcfi(/6/40)');
      await db.setCompleted('a.epub', false);
      final row = await db.getBookRow('a.epub');
      expect(row!.completed, isFalse);
      expect(row.position, 'reader:epubcfi(/6/40)');
      expect(await db.getCompletionDates(), isEmpty);
    });

    test('a book never opened can be marked finished', () async {
      await db.setCompleted('new.epub', true);
      expect(await db.isCompleted('new.epub'), isTrue);
    });

    test('marking tells the library; a page turned does not', () async {
      final before = MyLibraryDb.readingChanged.value;
      await db.saveBookState('a.epub', 'reader:epubcfi(/6/4)');
      expect(MyLibraryDb.readingChanged.value, before);
      await db.setCompleted('a.epub', true);
      expect(MyLibraryDb.readingChanged.value, before + 1);
    });
  });

  test('readingOf: how far, when, finished', () async {
    expect((await db.readingOf('a.epub')).started, isFalse);
    await db.setSyncState('frac:a.epub', '0.6200');
    await db.saveBookState('a.epub', 'reader:epubcfi(/6/4)');
    var reading = await db.readingOf('a.epub');
    expect(reading.started, isTrue);
    expect(reading.fraction, closeTo(0.62, 1e-9));
    expect(reading.finished, isFalse);
    expect(
        DateTime.now().difference(reading.readAt!).inSeconds.abs(), lessThan(5));
    // The last page reached, on a device that never marked it.
    await db.setSyncState('frac:a.epub', '0.9980');
    reading = await db.readingOf('a.epub');
    expect(reading.completed, isFalse);
    expect(reading.finished, isTrue);
  });

  group('a PDF', () {
    test('how far is the page over the pages; the last page finishes it',
        () async {
      await savePdfPosition('p.pdf', 51, pages: 200);
      expect((await db.readingOf('p.pdf')).fraction, closeTo(0.25, 1e-9));
      expect(await db.isCompleted('p.pdf'), isFalse);
      await savePdfPosition('p.pdf', 200, pages: 200);
      final reading = await db.readingOf('p.pdf');
      expect(reading.fraction, 1);
      expect(reading.completed, isTrue);
    });

    test('with the page count not known yet, only the page is saved',
        () async {
      await savePdfPosition('p.pdf', 3);
      final reading = await db.readingOf('p.pdf');
      expect(reading.started, isTrue);
      expect(reading.fraction, isNull);
    });
  });

  group('the library', () {
    test('each book carries how far it was read and when', () async {
      for (final id in ['a', 'b', 'c', 'd']) {
        await db.insert(_book(id));
      }
      await db.saveBookState('a.epub', 'reader:epubcfi(/6/4)');
      await db.setSyncState('frac:a.epub', '0.4100');
      await db.setSyncState('pos:a.epub', '1795000000000');
      // Read to its end on another device: its share says so.
      await db.saveBookState('b.epub', 'reader:epubcfi(/6/90)');
      await db.setSyncState('frac:b.epub', '0.9990');
      await db.setCompleted('c.epub', true);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final books = {
        for (final b in await container.read(libraryBooksProvider.future))
          b.id: b,
      };
      expect(books['a']!.status, ReadingStatus.inProgress);
      expect(books['a']!.percent, 41);
      expect(books['a']!.progress, closeTo(0.41, 1e-9));
      expect(books['a']!.readAt,
          DateTime.fromMillisecondsSinceEpoch(1795000000000));
      expect(books['b']!.status, ReadingStatus.completed);
      expect(books['b']!.progress, 1);
      expect(books['b']!.percent, isNull);
      expect(books['c']!.status, ReadingStatus.completed);
      expect(books['d']!.status, ReadingStatus.unread);
      expect(books['d']!.progress, 0);
      expect(books['d']!.readAt, isNull);
    });
  });

  group('what to go on with', () {
    test('the book read last comes first, whatever was added last', () {
      final books = [
        // (The library's order: newest added first.)
        _reading('volume4', at: DateTime(2026, 11, 18)),
        _reading('volume3', at: DateTime(2026, 11, 21, 16)),
        LibraryBook(book: _book('unread')),
        _reading('old', at: DateTime(2026, 10, 2)),
        LibraryBook(book: _book('done'), status: ReadingStatus.completed),
      ];
      expect([for (final b in continueReading(books)) b.id],
          ['volume3', 'volume4', 'old']);
    });

    test('books with no time known keep the library\'s order, after', () {
      final books = [
        _reading('x'),
        _reading('y'),
        _reading('z', at: DateTime(2026, 11, 1)),
      ];
      expect(
          [for (final b in continueReading(books)) b.id], ['z', 'x', 'y']);
    });

    test('a percent is 1 to 99 while reading, none without a share', () {
      expect(_reading('a', fraction: 0.001).percent, 1);
      expect(_reading('a', fraction: 0.994).percent, 99);
      expect(_reading('a').percent, isNull);
      expect(_reading('a').progress, isNull);
      expect(
          LibraryBook(book: _book('n'), fraction: 0.5).percent, isNull);
    });
  });
}
