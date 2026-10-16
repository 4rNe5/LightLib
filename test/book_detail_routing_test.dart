// Book-detail routing: which provider serves a book URL.
//
// The regression this pins: routing used to test a hardcoded list of
// Z-Library hosts, so a result served from a mirror open-slum.org lists
// only after that list was written (go-to-library.sk, library-access.sk)
// was handed to Anna's Archive, which swapped the host and failed. The
// route must follow the catalogue instead.

// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/services/book_detail_routing.dart';
import 'package:openlib/services/instance_manager.dart';
import 'package:openlib/services/preference_store.dart';
import 'package:openlib/services/slum_catalogue.dart';

/// An open-slum.org page in the shape the catalogue parses.
String _slumPage(List<String> origins) {
  final cards = StringBuffer();
  for (var i = 0; i < origins.length; i++) {
    final origin = origins[i];
    cards.write('''
<div class="card" id="x.m$i">
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

void main() {
  group('routeBookDetail (catalogue-driven)', () {
    late HttpServer catalogue;

    /// Serves the per-service pages: z-library lists the two hosts a
    /// hardcoded list missed, "other" lists welib.org, annas lists its
    /// mirror, libgen its own.
    Future<void> serveCatalogue() async {
      catalogue = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      catalogue.listen((request) async {
        final body = switch (request.uri.path) {
          '/zlibrary.html' =>
            _slumPage(['https://go-to-library.sk', 'https://library-access.sk']),
          '/other.html' => _slumPage(['https://welib.org']),
          '/annas.html' => _slumPage(['https://annas-archive.gl']),
          '/libgen.html' => _slumPage(['https://libgen.la']),
          _ => '<!doctype html><html><body></body></html>',
        };
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write(body);
        await request.response.close();
      });
    }

    InstanceManager managerFor(HttpServer slum) => InstanceManager.forTest(
          catalogue: SlumCatalogue(
            store: MemoryPreferenceStore(),
            baseUrl: 'http://127.0.0.1:${slum.port}',
          ),
          store: MemoryPreferenceStore(),
        );

    setUp(serveCatalogue);
    tearDown(() async => catalogue.close());

    const md5 = '00f8a97a0e03ac203235b306e249aa76';

    test('a SLUM-listed Z-Library mirror routes to Z-Library', () async {
      // The exact case the hardcoded list broke: neither host is in it.
      expect(
        await routeBookDetail(
            'https://go-to-library.sk/book/abc123/a-title.html',
            manager: managerFor(catalogue)),
        BookDetailRoute.zlibrary,
      );
      expect(
        await routeBookDetail(
            'https://library-access.sk/book/xyz789/another.html',
            manager: managerFor(catalogue)),
        BookDetailRoute.zlibrary,
      );
    });

    test('a WeLib mirror routes to WeLib', () async {
      expect(
        await routeBookDetail('https://welib.org/md5/$md5',
            manager: managerFor(catalogue)),
        BookDetailRoute.welib,
      );
    });

    test("an Anna's Archive mirror routes to Anna's Archive", () async {
      expect(
        await routeBookDetail('https://annas-archive.gl/md5/$md5',
            manager: managerFor(catalogue)),
        BookDetailRoute.annasArchive,
      );
    });

    test('a libgen ads page routes to libgen', () async {
      expect(
        await routeBookDetail('https://libgen.la/ads.php?md5=$md5',
            manager: managerFor(catalogue)),
        BookDetailRoute.libgen,
      );
    });

    test('without a catalogue the URL shape decides', () async {
      // A dead catalogue (server refuses) leaves the shape fallback:
      // /book/ is Z-Library's alone; /md5/ goes to the catch-all.
      final dead = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = dead.port;
      await dead.close();
      final offline = InstanceManager.forTest(
        catalogue: SlumCatalogue(
          store: MemoryPreferenceStore(),
          baseUrl: 'http://127.0.0.1:$port',
        ),
        store: MemoryPreferenceStore(),
      );

      expect(
        await routeBookDetail('https://unknown-zlib.example/book/1/x.html',
            manager: offline),
        BookDetailRoute.zlibrary,
      );
      expect(
        await routeBookDetail('https://unknown-aa.example/md5/$md5',
            manager: offline),
        BookDetailRoute.annasArchive,
      );
    });
  });
}
