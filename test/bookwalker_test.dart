// BOOK☆WALKER lists on the home page: the pages read into books, store
// titles cut to the series a library lists, one entry per series, and
// the Japanese home view.

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/bookwalker.dart';
import 'package:openlib/state/state.dart';
import 'package:openlib/ui/japan_discover.dart';

// The shape of a search results page (series tiles), cut down.
const _searchPage = '''
<html><body>
<div class="o-tile"><div class="o-tile-thumb">
  <a class="a-thumb-img" href="https://bookwalker.jp/de1/">
    <img class="lazy" src="https://c.bookwalker.jp/louis/sp/img/common/bg-now-loading-sp.png"
         data-original="https://c.bookwalker.jp/thumbnailImage_1.jpg" alt="x"/></a></div>
  <div class="o-tile-tag-box"><span class="a-tag-LN">ラノベ</span></div>
  <h2 class="o-tile-ttl"><a href="https://bookwalker.jp/series/1/">『青春ブタ野郎』シリーズ（電撃文庫）</a></h2>
  <p class="o-tile-book-author">鴨志田一 他</p></div>
<div class="o-tile"><div class="o-tile-thumb">
  <img class="lazy" data-original="https://c.bookwalker.jp/thumbnailImage_2.jpg"/></div>
  <h2 class="o-tile-ttl"><a href="https://bookwalker.jp/de2/">【購入特典】『攻撃力ゼロから始める剣聖譚 7』BOOK☆WALKER限定書き下ろしショートストーリー</a></h2></div>
<div class="o-tile"><div class="o-tile-thumb">
  <img class="lazy" data-original="https://c.bookwalker.jp/thumbnailImage_3.jpg"/></div>
  <h2 class="o-tile-ttl"><a href="https://bookwalker.jp/de3/">攻撃力ゼロから始める剣聖譚 7　～幼馴染の皇女に捨てられ～</a></h2></div>
<div class="o-tile"><div class="o-tile-thumb">
  <img class="lazy" data-original="https://c.bookwalker.jp/thumbnailImage_4.jpg"/></div>
  <h2 class="o-tile-ttl"><a href="https://bookwalker.jp/de4/">攻撃力ゼロから始める剣聖譚 8【電子特別版】</a></h2></div>
</body></html>''';

// A ranking page carries its books as structured data.
const _rankingPage = '''
<script type="application/ld+json">{"@type": "BreadcrumbList"}</script>
<script type="application/ld+json">[
  {"@type": "Product", "name": "転生したら剣でした 21【電子限定おまけ付き】",
   "image": "https://rimg.bookwalker.jp/a/b.jpg", "url": "https://bookwalker.jp/de5/",
   "category": "新文芸"},
  {"@type": "Product", "name": "転生したら剣でした 20",
   "image": "https://rimg.bookwalker.jp/a/c.jpg"},
  {"@type": "Thing", "name": "x"}
]</script>''';

void main() {
  test('a store title becomes the series a library lists', () {
    expect(bookSearchQuery('『青春ブタ野郎』シリーズ（電撃文庫）'), '青春ブタ野郎');
    expect(bookSearchQuery('「お隣の天使様にいつの間にか駄目人間にされていた件」シリーズ（GA文庫）'),
        'お隣の天使様にいつの間にか駄目人間にされていた件');
    expect(bookSearchQuery('【電子版限定特典付き】凶乱令嬢ニア・リストン12病弱令嬢に転生した'),
        '凶乱令嬢ニア・リストン');
    expect(bookSearchQuery('魔導具師ダリヤはうつむかない　～今日から自由な職人ライフ～15'),
        '魔導具師ダリヤはうつむかない');
    expect(bookSearchQuery('転生したらスライムだった件（３３）'), '転生したらスライムだった件');
    expect(bookSearchQuery('探偵はもう、死んでいる。（MF文庫J）'), '探偵はもう、死んでいる');
    expect(bookSearchQuery('Ｒｅ：ゼロから始める異世界生活（MF文庫J）'), 'Ｒｅ：ゼロから始める異世界生活');
    expect(bookSearchQuery('没落予定の貴族だけど、暇だったから魔法を極めてみた@COMIC（LEVINコミックス）'),
        '没落予定の貴族だけど、暇だったから魔法を極めてみた');
    expect(bookSearchQuery('2周目冒険者は隠しクラス〈重力使い〉で最強を目指す 【コミック】（ナンバーナイン）'),
        '2周目冒険者は隠しクラス〈重力使い〉で最強を目指す');
    // A label inside the title belongs to it.
    expect(bookSearchQuery('「死亡エンドを回避したギャルゲーのヒロインたちが俺の【日記帳】を読んで秘密を知ったらしい」シリーズ（ＧＡ文庫）'),
        '死亡エンドを回避したギャルゲーのヒロインたちが俺の【日記帳】を読んで秘密を知ったらしい');
  });

  test('a search page: series tiles with covers, no bonus stories', () {
    final books = parseBookWalkerSearch(_searchPage);
    expect([for (final b in books) b.title], [
      '『青春ブタ野郎』シリーズ（電撃文庫）',
      '攻撃力ゼロから始める剣聖譚 7　～幼馴染の皇女に捨てられ～',
      '攻撃力ゼロから始める剣聖譚 8【電子特別版】',
    ]);
    expect(books.first.cover, 'https://c.bookwalker.jp/thumbnailImage_1.jpg');
    expect(books.first.author, '鴨志田一 他');
    // Two volumes of one series: one entry.
    expect([for (final b in onePerSeries(books)) b.searchQuery],
        ['青春ブタ野郎', '攻撃力ゼロから始める剣聖譚']);
  });

  test('the computer layout of a search page reads the same', () {
    const page = '''
<ul class="m-tile-list"><li class="m-tile"><div class="m-book-item ">
  <div class="m-book-item__thumb-block"><div class="m-thumb">
    <a href="https://bookwalker.jp/series/177437/list/" class="m-thumb__image">
      <img class="lazy" src="https://c.bookwalker.jp/louis/pc/img/common/bg-now-loading-pc.png"
           data-original="https://rimg.bookwalker.jp/1140/e.jpg" alt="『青春ブタ野郎』シリーズ（電撃文庫）"/></a></div></div>
  <div class="m-book-item__info-block"><div class="m-book-item__secondary">
    <p class="m-book-item__title"><a href="https://bookwalker.jp/series/177437/list/"
       class="m-book-item__title"> 『青春ブタ野郎』シリーズ（電撃文庫） </a></p></div></div>
</div></li></ul>''';
    final books = parseBookWalkerSearch(page);
    expect(books.single.searchQuery, '青春ブタ野郎');
    expect(books.single.cover, 'https://rimg.bookwalker.jp/1140/e.jpg');
  });

  test('a ranking page: its products', () {
    final books = parseBookWalkerRanking(_rankingPage);
    expect(books.length, 2);
    expect(books.first.cover, 'https://rimg.bookwalker.jp/a/b.jpg');
    expect(onePerSeries(books).single.searchQuery, '転生したら剣でした');
    expect(parseBookWalkerRanking('<html></html>'), isEmpty);
  });

  testWidgets('the Japanese home view: categories and covers',
      (tester) async {
    final asked = <BookWalkerCategory>[];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        japanPopularProvider.overrideWith((ref, category) async {
          asked.add(category);
          return parseBookWalkerSearch(_searchPage);
        }),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('ko'),
        home: Scaffold(body: JapanTrendingView()),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('라이트노벨'), findsOneWidget);
    expect(find.text('만화'), findsOneWidget);
    expect(find.text('青春ブタ野郎'), findsOneWidget);
    expect(asked, [BookWalkerCategory.lightNovel]);
    await tester.tap(find.byKey(const ValueKey('japanCategory-manga')));
    await tester.pump();
    await tester.pump();
    expect(asked.last, BookWalkerCategory.manga);
  });

  testWidgets('the genres: one tile each, named for the reader',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('ko'),
        home: Scaffold(body: JapanGenresView()),
      ),
    ));
    expect(find.text('이세계'), findsOneWidget);
    expect(find.text('異世界系作品'), findsOneWidget);
  });
}
