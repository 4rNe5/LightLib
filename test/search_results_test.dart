// Search results read and gathered: the info line, a title's series and
// volume, the best file of a volume, series of two volumes or more.

// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/services/annas_archieve.dart' show BookData;
import 'package:openlib/services/search_results.dart';

BookData book(String title, String info, {String? md5, String? cover}) =>
    BookData(
        title: title,
        author: 'Author',
        link: 'https://x/${md5 ?? title.hashCode}',
        md5: md5 ?? '${title.hashCode}${info.hashCode}',
        info: info,
        thumbnail: cover);

void main() {
  test('the info line: language, format, size, year, collections', () {
    final aa = factsOf('Japanese [ja] · EPUB · 3.2MB · 2023 · 📕 Book (fiction) · 🚀/lgli/zlib/upload');
    expect(aa.language, 'Japanese');
    expect(aa.format, 'EPUB');
    expect(aa.megabytes, closeTo(3.2, 1e-9));
    expect(aa.year, 2023);
    expect(aa.copies, 3);
    final libgen = factsOf('Japanese, PDF, 512 KB, 2019');
    expect(libgen.language, 'Japanese');
    expect(libgen.format, 'PDF');
    expect(libgen.megabytes, closeTo(0.5, 1e-9));
    expect(libgen.year, 2019);
    expect(factsOf(null).format, isNull);
    expect(factsOf('English [en] · AZW3 · 1.1GB').megabytes, closeTo(1126.4, 0.1));
  });

  group('series and volume of a title', () {
    void check(String title, String series, String? volume) {
      final v = volumeOf(title);
      expect(v.series, series, reason: title);
      expect(v.number == null ? null : v.display, volume, reason: title);
    }

    test('Japanese light novel titles', () {
      check('死亡遊戯で飯を食う。10', '死亡遊戯で飯を食う。', '10');
      check('死亡遊戯で飯を食う。１０【電子特典付き】', '死亡遊戯で飯を食う。', '10');
      check('ようこそ実力至上主義の教室へ 2年生編 (3)', 'ようこそ実力至上主義の教室へ 2年生編', '3');
      check('ようこそ実力至上主義の教室へ 2年生編 3', 'ようこそ実力至上主義の教室へ 2年生編', '3');
      check('魔女の旅々 第5巻 (GAノベル)', '魔女の旅々', '5');
      check('魔女の旅々 5巻', '魔女の旅々', '5');
      check('魔女の旅々 5 ～旅の終わり～', '魔女の旅々', '5');
      check('ソードアート・オンライン 1 アインクラッド', 'ソードアート・オンライン', '1');
      check('涼宮ハルヒの憂鬱 (角川スニーカー文庫)', '涼宮ハルヒの憂鬱', null);
      check('とある魔術の禁書目録 (上)', 'とある魔術の禁書目録', '上');
      check('とある魔術の禁書目録 下巻', 'とある魔術の禁書目録', '下');
      check('86―エイティシックス―', '86―エイティシックス―', null);
      check('【悲報】タイトル 2', 'タイトル', '2');
    });

    test('Latin titles', () {
      check('Overlord, Vol. 4', 'Overlord', '4');
      check('Sword Art Online 10: Alicization Running', 'Sword Art Online', '10');
      check('Re:Zero #3', 'Re:Zero', '3');
      check('1984', '1984', null);
      check('Book 1-0', 'Book 1-0', null);
    });

    test('series compare without spaces and punctuation', () {
      expect(seriesKey('死亡遊戯で飯を食う。'), seriesKey('死亡遊戯で飯を食う'));
      expect(seriesKey('Sword Art Online'), seriesKey('sword-art online'));
    });
  });

  test('the best file: language, then EPUB, then how widely kept', () {
    final ja = ResultFile(book('X 1', 'Japanese [ja] · PDF · 9MB · 2020'));
    final epub = ResultFile(book('X 1', 'Japanese [ja] · EPUB · 3MB · 2020 · 🚀/lgli/zlib'));
    final en = ResultFile(book('X 1', 'English [en] · EPUB · 3MB · 2022'));
    final empty = ResultFile(book('X 1', 'Japanese [ja] · EPUB · 0.01MB · 2020'));
    int s(ResultFile f) => fileScore(f, language: 'Japanese', format: 'EPUB');
    expect(s(epub), greaterThan(s(ja)));
    expect(s(ja), greaterThan(s(en)));
    expect(s(epub), greaterThan(s(empty)));
  });

  test('results gathered: series with their volumes, the rest apart', () {
    final g = groupResults([
      book('死亡遊戯で飯を食う。2', 'Japanese [ja] · PDF · 5MB', cover: ''),
      book('死亡遊戯で飯を食う。 1', 'Japanese [ja] · EPUB · 3MB', cover: 'c1'),
      book('死亡遊戯で飯を食う。2', 'Japanese [ja] · EPUB · 3MB · 🚀/lgli/zlib'),
      book('死亡遊戯で飯を食う。10【電子特典付き】', 'Japanese [ja] · EPUB · 3MB'),
      book('死亡遊戯で飯を食う。 (MF文庫J)', 'Japanese [ja] · EPUB · 3MB'),
      book('死亡遊戯で飯を食う。 3', 'English [en] · EPUB · 3MB'),
      book('別の本', 'Japanese [ja] · EPUB · 2MB'),
      book('Some Book 4', 'English [en] · PDF · 2MB'),
    ], language: 'Japanese', format: 'EPUB');
    expect(g.series.length, 1);
    final s = g.series.single;
    expect(s.series, '死亡遊戯で飯を食う。');
    expect([for (final v in s.volumes) v.volume.display], ['1', '2', '3', '10']);
    // Volume 2's EPUB (Japanese, kept in two collections) beats its PDF.
    expect(s.volumes[1].best.facts.format, 'EPUB');
    expect(s.volumes[1].files.length, 2);
    expect(s.others.length, 1);
    expect(s.cover, 'c1');
    expect(s.fileCount, 6);
    expect(volumeRanges(s.volumes), '1–3, 10');
    // The rest, best first: the Japanese EPUB before the English PDF.
    expect([for (final f in g.singles) f.book.title], ['別の本', 'Some Book 4']);
  });

  test('one numbered title is not a series', () {
    final g = groupResults([
      book('Overlord, Vol. 4', 'English [en] · EPUB · 3MB'),
      book('Overlord', 'English [en] · EPUB · 3MB'),
    ]);
    expect(g.hasSeries, isFalse);
    expect(g.singles.length, 2);
  });

  test('volume ranges', () {
    List<VolumeGroup> vs(List<String> titles) => groupResults([
          for (final t in titles) book(t, 'Japanese [ja] · EPUB · 3MB'),
        ]).series.single.volumes;
    expect(volumeRanges(vs(['A 1', 'A 2'])), '1, 2');
    expect(volumeRanges(vs(['A 1', 'A 2', 'A 3', 'A 5', 'A 6'])), '1–3, 5, 6');
    expect(volumeRanges(vs(['A (上)', 'A (下)'])), '上, 下');
  });
}
