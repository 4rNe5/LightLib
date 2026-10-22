// Dart imports:
import 'dart:convert';
import 'dart:io';

// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;

// Project imports:
import 'package:openlib/services/annas_archieve.dart';
import 'package:openlib/services/search_manager.dart';
import 'package:openlib/ui/components/zlib_recommendations_widget.dart';

void main() {
  const base = 'https://z-lib.example';
  final html = File('test/fixtures/zlib_book_page.html').readAsStringSync();
  final provider = ZlibraryProvider(mirrors: const [base]);

  group('parseRecommendations (captured book page)', () {
    final recs =
        provider.parseRecommendations(html_parser.parse(html), html, base)!;

    test('reads every mosaic item, deduplicated, in page order', () {
      expect(recs.books, hasLength(42));
      expect(recs.books.map((b) => b.md5).toSet(), hasLength(42));
      final first = recs.books.first;
      expect(first.title, 'The Complete Plant-Based Cookbook');
      expect(first.author, 'Americas Test Kitchen');
      expect(first.md5, 'GPbV13vWPe');
      expect(first.thumbnail,
          startsWith('https://s3proxy-alp2-covers.cdn-zlib.sk/covers200/'));
      expect(first.source, 'Z-Library');
    });

    test('drops the dsource tracking query and keeps the mirror', () {
      expect(recs.books.first.link,
          '$base/book/GPbV13vWPe/the-complete-plantbased-cookbook.html');
      expect(recs.books.every((b) => !b.link.contains('?')), isTrue);
    });

    test('reads the Load more cursor from the inline script', () {
      expect(recs.page, 2);
      expect(recs.onPage, 21);
      expect(recs.bookIds, hasLength(42));
      expect(recs.bookIds.first, 11930175);
      expect(recs.bookIds.last, 5929174);
      expect(recs.mirror, base);
      expect(recs.hasMore, isTrue);
    });

    test('parseBookPage carries the recommendations', () {
      final info = provider.parseBookPage(html, base, '$base/book/x/y.html');
      expect(info, isA<ZlibraryBookInfoData>());
      expect(
          (info as ZlibraryBookInfoData).recommendations?.books, hasLength(42));
    });

    test('falls back to dsource=recommend links outside the mosaic', () {
      const page = '<html><body><h1 itemprop="name">T</h1>'
          '<div class="other"><a href="/book/QQ11/q.html?dsource=recommend">'
          '<img data-src="https://c.example/q.jpg" alt="Some Author \u2014 Some Title">'
          '</a></div></body></html>';
      final recs =
          provider.parseRecommendations(html_parser.parse(page), page, base)!;
      expect(recs.books.single.title, 'Some Title');
      expect(recs.books.single.author, 'Some Author');
      expect(recs.books.single.thumbnail, 'https://c.example/q.jpg');
      expect(recs.books.single.link, '$base/book/QQ11/q.html');
      expect(recs.hasMore, isFalse);
    });

    test('an empty mosaic with an API cursor asks the API from page 1', () {
      const page = '<html><body><div class="books-mosaic">'
          '<div class="masonry-endless"></div></div><script>'
          "let mosaicPage = parseInt('2'); let onPage = parseInt('21');"
          'data = { bookIds: [5,6,7] }</script></body></html>';
      final recs =
          provider.parseRecommendations(html_parser.parse(page), page, base)!;
      expect(recs.books, isEmpty);
      expect(recs.bookIds, [5, 6, 7]);
      expect(recs.page, 0);
      expect(recs.hasMore, isTrue);
    });

    test('reads the description box when the page has one', () {
      const page = '<html><body><h1 itemprop="name">T</h1>'
          '<div id="bookDescriptionBox">  A <b>fine</b>\n book.  </div>'
          '</body></html>';
      final info = provider.parseBookPage(page, base, '$base/book/a/b.html');
      expect(info!.description, 'A fine book.');
    });

    test('a page without the mosaic yields null', () {
      const plain = '<html><body><h1 itemprop="name">T</h1></body></html>';
      expect(
          provider.parseRecommendations(html_parser.parse(plain), plain, base),
          isNull);
      final info = provider.parseBookPage(plain, base, '$base/book/a/b.html');
      expect((info as ZlibraryBookInfoData).recommendations, isNull);
    });
  });

  group('parseRecommendationsJson', () {
    final start = ZlibraryRecommendations(
      books: [BookData(title: 'A', link: '$base/book/AAA/a.html', md5: 'AAA')],
      bookIds: const [1, 2],
      onPage: 21,
      page: 2,
      mirror: base,
      hasMore: true,
    );

    test('appends new books, skips duplicates, advances the page', () {
      final next = provider.parseRecommendationsJson({
        'success': 1,
        'books': [
          {'id': 1, 'url': '/book/AAA/a.html', 'title': 'A', 'author': 'x'},
          {
            'id': 2,
            'isbn': '',
            'url': '/book/BBB/b.html',
            'title': 'B',
            'author': 'Y',
            'cover': 'https://cdn.example/c.jpg',
          },
        ],
        'nextPage': 4,
      }, start);
      expect(next.books.map((b) => b.md5), ['AAA', 'BBB']);
      expect(next.books.last.link, '$base/book/BBB/b.html');
      expect(next.books.last.thumbnail, 'https://cdn.example/c.jpg');
      expect(next.page, 3);
      expect(next.hasMore, isTrue);
    });

    test('nextPage false ends the list, as the site script does', () {
      final next = provider.parseRecommendationsJson({
        'books': [
          {'url': '/book/CCC/c.html', 'title': 'C'}
        ],
        'nextPage': false,
      }, start);
      expect(next.books, hasLength(2));
      expect(next.hasMore, isFalse);
    });

    test('no books ends the list', () {
      expect(provider.parseRecommendationsJson({'books': []}, start).hasMore,
          isFalse);
      expect(provider.parseRecommendationsJson({}, start).hasMore, isFalse);
    });
  });

  group('loadMoreRecommendations (local server)', () {
    late HttpServer server;
    late String origin;
    String? method;
    String? path;
    Object? body;
    var status = 200;
    var reply = '';

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      origin = 'http://127.0.0.1:${server.port}';
      server.listen((req) async {
        method = req.method;
        path = req.uri.path;
        body = jsonDecode(await utf8.decoder.bind(req).join());
        req.response
          ..statusCode = status
          ..headers.contentType = ContentType.json
          ..write(reply);
        await req.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    ZlibraryRecommendations cursor() => ZlibraryRecommendations(
          books: const [],
          bookIds: const [11, 22],
          onPage: 21,
          page: 2,
          mirror: origin,
          hasMore: true,
        );

    test('POSTs the bookIds JSON to the next mosaic page', () async {
      status = 200;
      reply = jsonEncode({
        'success': 1,
        'books': [
          {'url': '/book/DDD/d.html', 'title': 'D', 'author': 'Z'}
        ],
        'nextPage': false,
      });
      final next = await ZlibraryProvider(mirrors: [origin])
          .loadMoreRecommendations(cursor());
      expect(method, 'POST');
      expect(path, '/papi/book/recommended/mosaic/21/3');
      expect(body, {
        'bookIds': [11, 22]
      });
      expect(next.books.single.link, '$origin/book/DDD/d.html');
      expect(next.hasMore, isFalse);
    });

    test('throws on a non-200 so the UI can offer a retry', () async {
      status = 500;
      reply = '{}';
      await expectLater(
          ZlibraryProvider(mirrors: [origin]).loadMoreRecommendations(cursor()),
          throwsException);
    });

    test('throws on success: 0', () async {
      status = 200;
      reply = jsonEncode({'success': 0, 'error': 'nope'});
      await expectLater(
          ZlibraryProvider(mirrors: [origin]).loadMoreRecommendations(cursor()),
          throwsException);
    });
  });

  group('mosaic layout rules', () {
    test('columns scale with width between 3 and 5', () {
      expect(recommendationColumns(300), 3);
      expect(recommendationColumns(440), 4);
      expect(recommendationColumns(1200), 5);
    });

    test('an incomplete last row waits while more pages exist', () {
      expect(visibleRecommendationCount(42, 5, true), 40);
      expect(visibleRecommendationCount(42, 5, false), 42);
      expect(visibleRecommendationCount(42, 3, true), 42);
      expect(visibleRecommendationCount(2, 5, true), 2);
    });
  });
}
