// Series the reader made in the library: which books are one series
// (the reader's grouping beside what the titles say), their volumes in
// order, and a glossary's names carried from one volume to the others -
// when the reader has that on.

// Dart imports:
import 'dart:io';

// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/library_organization.dart';
import 'package:openlib/services/translation/book_glossary.dart';
import 'package:openlib/services/translation/glossary_service.dart';
import 'package:openlib/services/translation/series_glossary.dart';

class _FakePathProvider extends PathProviderPlatform {
  Future<String> _dir(String name) async {
    final dir = Directory('/tmp/openlib_series_test/$name');
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
      author: null,
      thumbnail: null,
      link: 'https://example.com/$id',
      publisher: null,
      info: null,
      format: 'epub',
      description: null,
      fileName: '$id.epub',
    );

LibraryBook _lib(String id, String title, {String? series}) =>
    LibraryBook(book: _book(id, title), series: series);

GlossaryEntry _name(String source, String target,
        {String? reading, bool edited = false}) =>
    GlossaryEntry(
        source: source,
        target: target,
        reading: reading,
        kind: GlossaryKind.person,
        edited: edited);

BookGlossary _glossary(List<GlossaryEntry> entries) => BookGlossary(
    entries: entries, complete: true, version: BookGlossary.currentVersion);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the series in the library', () {
    test('volumes in the order of their numbers; a title without one last', () {
      final series = librarySeries([
        _lib('x', 'Some other book'),
        _lib('c', '物語 10 (MF文庫J)', series: '物語'),
        _lib('s', '物語 短編集', series: '物語'),
        _lib('a', '物語 2', series: '物語'),
        _lib('b', '別の話 1', series: '別'),
        _lib('d', '物語', series: '物語'),
      ]);
      expect([for (final s in series) s.name], ['物語', '別']);
      expect(
          [for (final v in series.first.volumes) v.id], ['a', 'c', 'd', 's']);
      expect(series.last.volumes.single.id, 'b');
      expect(librarySeries([_lib('x', 'Alone')]), isEmpty);
    });

    test('a name is offered from what the titles call the series', () {
      expect(
          suggestedSeriesName(const [
            '死亡遊戯で飯を食う。 10 (MF文庫J)',
            '死亡遊戯で飯を食う。 2',
            'まったく別の本 1',
          ]),
          '死亡遊戯で飯を食う。');
      expect(suggestedSeriesName(const []), '');
    });
  });

  group('which books are one series', () {
    const titles = {
      'a1.epub': '物語 1',
      'a2.epub': '物語 2',
      'a3.epub': '物語 3',
      'side.epub': '番外編 きみの名前',
      'other.epub': 'まったく別の本 1',
    };

    test('the reader\'s grouping joins what the titles cannot', () {
      expect(sameSeries('side.epub', titles), isEmpty);
      const grouped = {'a1.epub': '物語', 'side.epub': '物語'};
      expect(sameSeries('side.epub', titles, grouped: grouped), ['a1.epub']);
      // Volume 1 is in the reader's series and still one with the
      // volumes its title names, which are in none.
      expect(sameSeries('a1.epub', titles, grouped: grouped).toSet(),
          {'a2.epub', 'a3.epub', 'side.epub'});
      // A volume the reader has not grouped finds the ones grouped by
      // its title.
      expect(sameSeries('a2.epub', titles, grouped: grouped).toSet(),
          {'a1.epub', 'a3.epub'});
    });

    test(
        'books the reader put in different series are not one, whatever '
        'their titles say', () {
      const grouped = {'a1.epub': '물어', 'a2.epub': '다른 것'};
      expect(sameSeries('a1.epub', titles, grouped: grouped), ['a3.epub']);
      expect(sameSeries('a2.epub', titles, grouped: grouped), ['a3.epub']);
    });
  });

  group('a glossary and its series', () {
    test(
        'what the reader set in one volume is written in another that has '
        'the word, and only there', () {
      final other = _glossary([
        _name('純太郎', '준 타로'),
        _name('しずく', '시즈쿠'),
      ]);
      final next = withSeriesEdit(other, _name('純太郎', '준타로', edited: true))!;
      final entry = next.entries.firstWhere((e) => e.source == '純太郎');
      expect(entry.target, '준타로');
      expect(entry.edited, isTrue);
      expect(next.entries.firstWhere((e) => e.source == 'しずく').target, '시즈쿠');
      // A word that volume does not have is not given to it.
      expect(withSeriesEdit(other, _name('玲子', '레이코', edited: true)), isNull);
      // Nothing to do where it is written so already.
      expect(withSeriesEdit(next, _name('純太郎', '준타로', edited: true)), isNull);
    });

    test(
        'books put in one series agree on the names both have: the '
        'reader\'s word, or the volume that gives the reading', () {
      final first = _glossary([
        _name('風宮', '후미야'),
        _name('純太郎', '준타로', edited: true),
      ]);
      final second = _glossary([
        _name('風宮', '카자미야', reading: 'かざみや'),
        _name('純太郎', '준 타로'),
        _name('玲子', '레이코'),
      ]);
      final one = agreeWithSeries(first, [second]);
      expect(one.entries.firstWhere((e) => e.source == '風宮').target, '카자미야');
      expect(one.entries.any((e) => e.source == '玲子'), isFalse,
          reason: 'no name is added without the book\'s text');
      final two = agreeWithSeries(second, [first]);
      expect(two.entries.firstWhere((e) => e.source == '純太郎').target, '준타로');
      expect(two.entries.firstWhere((e) => e.source == '風宮').target, '카자미야');
      expect(identical(agreeWithSeries(one, [two]), one), isTrue);
    });
  });

  group('in the library', () {
    final service = GlossaryService.instance;
    late Directory dir;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      PathProviderPlatform.instance = _FakePathProvider();
    });

    setUp(() async {
      final database = await MyLibraryDb.instance.database;
      for (final t in ['mybooks', 'bookseries']) {
        await database.delete(t);
      }
      await MyLibraryDb.instance.savePreference(seriesGlossaryPref, 1);
      dir = Directory.systemTemp.createTempSync('series_glossary');
      service.directory = () async => dir;
      final db = MyLibraryDb.instance;
      await db.insert(_book('v1', '物語 1'));
      await db.insert(_book('v2', '物語 2'));
      await db.insert(_book('side', '番外編 きみの名前'));
      await db.insert(_book('else', 'まったく別の本'));
      for (final file in ['v1.epub', 'v2.epub', 'side.epub', 'else.epub']) {
        await service.save(file, _glossary([_name('純太郎', '준 타로')]));
      }
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('a series is kept by name, left again, and gone with its book',
        () async {
      final db = MyLibraryDb.instance;
      await db.setSeries(['v1', 'side'], '  物語  ');
      expect(await db.getSeriesForAll(), {'v1': '物語', 'side': '物語'});
      await db.setSeries(['side'], '外伝');
      expect((await db.getSeriesForAll())['side'], '外伝');
      await db.setSeries(['side'], null);
      expect(await db.getSeriesForAll(), {'v1': '物語'});
      await db.delete('v1');
      expect(await db.getSeriesForAll(), isEmpty);
    });

    test(
        'an edit goes to the volumes the titles name and the ones the '
        'reader grouped, not to other books', () async {
      await MyLibraryDb.instance.setSeries(['v1', 'side'], '物語');
      final changed = await passOnToSeries(
          'v1.epub', _name('純太郎', '준타로', edited: true),
          pathOf: (file) async => '${dir.path}/$file');
      expect(changed.toSet(), {'v2.epub', 'side.epub'});
      for (final file in ['v2.epub', 'side.epub']) {
        final e = (await service.load(file)).entries.single;
        expect(e.target, '준타로');
        expect(e.edited, isTrue);
      }
      expect((await service.load('else.epub')).entries.single.target, '준 타로');
      expect(await seriesGlossaries('v2.epub'), hasLength(1));
    });

    test('turned off: every volume keeps its own', () async {
      await MyLibraryDb.instance.savePreference(seriesGlossaryPref, 0);
      expect(await seriesGlossaryShared(), isFalse);
      final changed = await passOnToSeries(
          'v1.epub', _name('純太郎', '준타로', edited: true),
          pathOf: (file) async => '${dir.path}/$file');
      expect(changed, isEmpty);
      expect((await service.load('v2.epub')).entries.single.target, '준 타로');
      expect(await seriesGlossaries('v2.epub'), isEmpty);
      expect(await shareWithinSeries(['v1.epub', 'v2.epub']), 0);
    });

    test('grouping books shares what their glossaries settled', () async {
      await service.save(
          'v1.epub', _glossary([_name('純太郎', '준타로', edited: true)]));
      final changed = await shareWithinSeries(['v1.epub', 'side.epub'],
          pathOf: (file) async => '${dir.path}/$file');
      expect(changed, 1);
      expect((await service.load('side.epub')).entries.single.target, '준타로');
    });
  });
}
