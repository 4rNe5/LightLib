import 'dart:io';

// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

// Project imports:
import 'package:openlib/services/instance_manager.dart';
import 'package:openlib/services/libgen_service.dart';
import 'package:openlib/services/preference_store.dart';
import 'package:openlib/services/slum_catalogue.dart';

// The libgen tests inject an InstanceManager whose catalogue is a local
// server, so the enabled-mirror list they exercise comes from a real
// open-slum.org-shaped response instead of the network or the database.
class _FakePathProvider extends PathProviderPlatform {
  Future<String> _dir(String name) async {
    final dir = Directory('/tmp/openlib_libgen_test/$name');
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

const _md5Temple = '7373b39d1addaf236328975f9bbef7c4';
const _md5Flutter = '0229cc161352df1fb45a8f8246350910';

/// An open-slum.org page in the shape the catalogue parses: one card per
/// mirror with a title link and a status badge.
String _slumPage(List<String> mirrorOrigins) {
  final cards = StringBuffer();
  for (var i = 0; i < mirrorOrigins.length; i++) {
    final origin = mirrorOrigins[i];
    cards.write('''
<div class="card" id="libgen.m$i">
  <div class="card-header">
    <a href="$origin" class="card-title">${Uri.parse(origin).host}</a>
    <span class="status-badge up">UP</span>
  </div>
  <div>Latency: <span>120ms</span></div>
</div>
''');
  }
  return '<!doctype html><html><body>$cards</body></html>';
}

/// Serves that page for every path, so SlumCatalogue sees [mirrorOrigins]
/// as the libgen mirrors.
Future<HttpServer> _catalogueServer(List<String> mirrorOrigins) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.html
      ..write(_slumPage(mirrorOrigins));
    await request.response.close();
  });
  return server;
}

InstanceManager _managerFor(HttpServer catalogue) => InstanceManager.forTest(
      catalogue: SlumCatalogue(
        store: MemoryPreferenceStore(),
        baseUrl: 'http://127.0.0.1:${catalogue.port}',
      ),
      store: MemoryPreferenceStore(),
    );

void main() {
  setUpAll(() {
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      PathProviderPlatform.instance = _FakePathProvider();
    }
  });

  group('parseAdsPage on captured libgen pages', () {
    test('parses the Temple Legacy ads page (md5=$_md5Temple)', () {
      final html = File('test/fixtures/libgen_ads_page.html')
          .readAsStringSync(); // live capture of libgen.vg ads.php

      final book = LibgenService().parseAdsPage(html, 'https://libgen.vg',
          'https://libgen.vg/ads.php?md5=$_md5Temple');

      expect(book, isNotNull);
      expect(book!.title, equals('The Temple Legacy'));
      expect(book.author, equals('Macey, D.C.'));
      expect(book.publisher, contains('Butcher & Cameron'));
      expect(book.publisher, contains('2015'));
      expect(book.publisher, contains('Series: The Temple 1'));
      expect(book.md5, equals(_md5Temple));
      // The mirror must be the get.php download URL with the key.
      expect(book.mirror,
          startsWith('https://libgen.vg/get.php?md5=$_md5Temple&key='));
      expect(book.mirror, matches(r'&key=[0-9A-Z]{16}$'));
      // Cover is absolute.
      expect(book.thumbnail,
          equals('https://libgen.vg/fictioncovers/2204000/$_md5Temple.jpg'));
    });

    test('parses the Flutter for Beginners ads page (md5=$_md5Flutter)', () {
      final html = File('test/fixtures/libgen_ads_page_flutter.html')
          .readAsStringSync(); // live capture of libgen.vg ads.php

      final book = LibgenService().parseAdsPage(html, 'https://libgen.li',
          'https://libgen.li/ads.php?md5=$_md5Flutter');

      expect(book, isNotNull);
      expect(book!.title,
          startsWith('Flutter for Beginners: An introductory guide'));
      expect(book.author, equals('Thomas Bailey, Alessandro Biessek'));
      expect(book.publisher, contains('Packt Publishing'));
      expect(book.publisher, contains('2021'));
      expect(book.md5, equals(_md5Flutter));
      expect(book.mirror,
          startsWith('https://libgen.li/get.php?md5=$_md5Flutter&key='));
      expect(book.thumbnail,
          equals('https://libgen.li/covers/3206000/$_md5Flutter.jpg'));
    });

    test('md5 falls back to the get.php link when the url lacks it', () {
      final html =
          File('test/fixtures/libgen_ads_page.html').readAsStringSync();

      final book = LibgenService()
          .parseAdsPage(html, 'https://libgen.vg', 'https://libgen.vg/ads.php');

      expect(book, isNotNull);
      expect(book!.md5, equals(_md5Temple));
    });

    test('format defaults to epub when no extension is visible', () {
      final html =
          File('test/fixtures/libgen_ads_page.html').readAsStringSync();

      // Neither fixture page nor the url carry an extension token.
      final book = LibgenService().parseAdsPage(html, 'https://libgen.vg',
          'https://libgen.vg/ads.php?md5=$_md5Temple');

      expect(book, isNotNull);
      expect(book!.format, equals('epub'));
    });
  });

  group('parseAdsCover (lazy result-list covers)', () {
    test('extracts the cover URL from a captured ads page', () {
      final html =
          File('test/fixtures/libgen_ads_page.html').readAsStringSync();

      final cover =
          LibgenService.parseAdsCover(html, 'https://libgen.vg');

      // The fixture's cover img is a relative /fictioncovers/ URL.
      expect(cover, isNotNull);
      expect(cover,
          'https://libgen.vg/fictioncovers/2204000/7373b39d1addaf236328975f9bbef7c4.jpg');
    });

    test('keeps absolute cover URLs untouched', () {
      const html =
          '<table id="main"><tr><td><img src="https://libgen.li/covers/1/abc.jpg">'
          '</td><td>Title: X</td></tr></table>';

      expect(LibgenService.parseAdsCover(html, 'https://libgen.li'),
          'https://libgen.li/covers/1/abc.jpg');
    });

    test('returns null when the img src is empty (libgen.vg quirk)', () {
      const html =
          '<table id="main"><tr><td><img src=""></td><td>Title: X</td></tr></table>';

      expect(LibgenService.parseAdsCover(html, 'https://libgen.vg'), isNull);
    });

    test('returns null on a search results page (no ads table)', () {
      final html =
          File('test/fixtures/libgen_vg_results.html').readAsStringSync();

      expect(LibgenService.parseAdsCover(html, 'https://libgen.vg'), isNull);
    });
  });

  group('parseAdsPage rejects non-matching markup', () {
    test('returns null on garbage html', () {
      expect(
          LibgenService().parseAdsPage('<html><body>hello world</body></html>',
              'https://libgen.vg', 'https://libgen.vg/ads.php?md5=$_md5Temple'),
          isNull);
    });

    test('returns null on a Cloudflare challenge page', () {
      expect(
          LibgenService().parseAdsPage(
              '<!DOCTYPE html><html><head><title>Just a moment...</title>'
                  '</head><body>Checking your browser before accessing.</body></html>',
              'https://libgen.gl',
              'https://libgen.gl/ads.php?md5=$_md5Temple'),
          isNull);
    });

    test('returns null on a search results page (no ads detail row)', () {
      final html =
          File('test/fixtures/libgen_vg_results.html').readAsStringSync();

      expect(
          LibgenService().parseAdsPage(html, 'https://libgen.vg',
              'https://libgen.vg/index.php?req=flutter&res=25'),
          isNull);
    });

    test('never throws on truncated html', () {
      final html = File('test/fixtures/libgen_ads_page.html')
          .readAsStringSync()
          .substring(0, 5000);

      // Must return null or a book - but not throw.
      final book = LibgenService().parseAdsPage(html, 'https://libgen.vg',
          'https://libgen.vg/ads.php?md5=$_md5Temple');
      expect(book == null || book.title.isNotEmpty, isTrue);
    });
  });

  group('mirror host swap logic', () {
    final service = LibgenService();

    test('swapHost keeps path and query', () {
      expect(
          service.swapHost(
              'https://dead.example/ads.php?md5=X', 'https://libgen.li'),
          equals('https://libgen.li/ads.php?md5=X'));
      expect(
          service.swapHost(
              'https://dead.example/ads.php?md5=X', 'https://libgen.bz'),
          equals('https://libgen.bz/ads.php?md5=X'));
      expect(
          service.swapHost(
              'https://libgen.vg/ads.php?md5=X&key=K', 'https://libgen.li'),
          equals('https://libgen.li/ads.php?md5=X&key=K'));
    });

    test('candidateUrls leads with the host when the catalogue enabled it',
        () {
      final mirrors = ['https://libgen.li', 'https://libgen.bz'];
      expect(
          service.candidateUrls('https://libgen.li/ads.php?md5=X', mirrors),
          equals([
            'https://libgen.li/ads.php?md5=X',
            'https://libgen.bz/ads.php?md5=X',
          ]));
    });

    test('candidateUrls never probes a host the catalogue did not enable', () {
      final mirrors = ['https://libgen.li', 'https://libgen.bz'];
      // A stored link on a host SLUM reports DOWN, or that the user
      // switched off, must not be contacted - only the enabled mirrors.
      expect(
          service.candidateUrls('https://dead.example/ads.php?md5=X', mirrors),
          equals([
            'https://libgen.li/ads.php?md5=X',
            'https://libgen.bz/ads.php?md5=X',
          ]));
      expect(
          service.candidateUrls('https://libgen.vg/ads.php?md5=X', mirrors),
          equals([
            'https://libgen.li/ads.php?md5=X',
            'https://libgen.bz/ads.php?md5=X',
          ]));
    });

    test('candidateUrls resolves a bare path against the first mirror',
        () async {
      expect(
          service.candidateUrls(
              '/ads.php?md5=X', ['https://libgen.li', 'https://libgen.bz']),
          equals([
            'https://libgen.li/ads.php?md5=X',
            'https://libgen.bz/ads.php?md5=X',
          ]));
    });

    test('candidateUrls is empty without an enabled mirror', () {
      // No catalogue knowledge (SLUM unreachable, nothing cached) and
      // every mirror down/disabled are both "nothing known-good to ask":
      // no request is made at all, matching LibgenProvider.search.
      expect(service.candidateUrls('https://libgen.li/ads.php?md5=X', []),
          isEmpty);
    });

    test('bookInfo takes its candidates from the injected catalogue',
        () async {
      // End to end through a real SLUM-shaped page: the listed mirror is
      // the only candidate, and a host outside the list is not probed.
      final mirror = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final adsHtml =
          File('test/fixtures/libgen_ads_page.html').readAsStringSync();
      mirror.listen((request) async {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write(adsHtml);
        await request.response.close();
      });
      final origin = 'http://127.0.0.1:${mirror.port}';
      final catalogue = await _catalogueServer([origin]);

      try {
        final service = LibgenService(instanceManager: _managerFor(catalogue));
        final book = await service.bookInfo('$origin/ads.php?md5=$_md5Temple');
        expect(book, isNotNull,
            reason: 'the catalogue-listed mirror must be used');
      } finally {
        await mirror.close();
        await catalogue.close();
      }
    });
  });

  group('same-origin Referer header', () {
    test('bookInfo sends same-origin Referer based on candidate mirror', () async {
      String? receivedReferer;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final html = File('test/fixtures/libgen_ads_page.html').readAsStringSync();
      server.listen((HttpRequest request) {
        receivedReferer = request.headers.value(HttpHeaders.refererHeader);
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write(html)
          ..close();
      });

      final origin = 'http://${server.address.host}:${server.port}';
      final catalogue = await _catalogueServer([origin]);

      try {
        final service = LibgenService(instanceManager: _managerFor(catalogue));
        final book = await service.bookInfo('$origin/ads.php?md5=$_md5Temple');

        expect(book, isNotNull);
        expect(receivedReferer, equals('$origin/index.php'));
      } finally {
        await server.close();
        await catalogue.close();
      }
    });

    test('fetchCover sends same-origin Referer based on candidate mirror', () async {
      String? receivedReferer;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final html = File('test/fixtures/libgen_ads_page.html').readAsStringSync();
      server.listen((HttpRequest request) {
        receivedReferer = request.headers.value(HttpHeaders.refererHeader);
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write(html)
          ..close();
      });

      final origin = 'http://${server.address.host}:${server.port}';
      final catalogue = await _catalogueServer([origin]);

      try {
        final service = LibgenService(instanceManager: _managerFor(catalogue));
        final cover = await service.fetchCover('$origin/ads.php?md5=$_md5Temple');

        expect(cover, isNotNull);
        expect(receivedReferer, equals('$origin/index.php'));
      } finally {
        await server.close();
        await catalogue.close();
      }
    });
  });

  group('bookInfo (live network - run manually)', () {
    test('fetches a real book from an enabled libgen mirror', () async {
      // Mirrors come from open-slum.org: there is no fixed host to test
      // against, and SLUM currently reports the whole family DOWN, so a
      // missing mirror is an honest skip - not a fabricated success.
      final mirrors = await InstanceManager().enabledUrls(MirrorService.libgen);
      if (mirrors.isEmpty) {
        markTestSkipped(
            'SLUM lists no attemptable libgen mirror right now');
        return;
      }

      final book = await LibgenService()
          .bookInfo('${mirrors.first}/ads.php?md5=$_md5Temple');
      if (book == null) {
        markTestSkipped('the test book is not on ${mirrors.first}');
        return;
      }

      expect(book.title, isNotEmpty);
      expect(book.author, isNotEmpty);
      expect(book.mirror, contains('/get.php?md5='));
    }, skip: 'live network - run manually');
  });
}
