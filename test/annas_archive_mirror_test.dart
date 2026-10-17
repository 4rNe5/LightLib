// End-to-end tests for the chain the app promises its mirrors follow:
//
//   open-slum.org page  ->  mirror list (no hardcoded URLs)
//      -> protection-ordered (unprotected before DiamWall before
//         DDoS-Guard/Cloudflare)
//      -> Anna's Archive walks the mirrors in that order and survives
//         a failing one.
//
// Everything runs against real local HTTP servers: one plays
// open-slum.org (serving a page with the exact markup SLUM uses), the
// others play the mirrors themselves, one of them serving the search
// results page captured live from Anna's Archive. Nothing is mocked.

// Dart imports:
import 'dart:io';

// Package imports:
import 'package:dio/dio.dart';

// Flutter imports:
import 'package:flutter_test/flutter_test.dart';

// Package imports:

// Project imports:
import 'package:openlib/services/annas_archieve.dart';
import 'package:openlib/services/challenge_html_cache.dart';
import 'package:openlib/services/instance_manager.dart';
import 'package:openlib/services/network_error.dart';
import 'package:openlib/services/preference_store.dart';
import 'package:openlib/services/slum_catalogue.dart';
import 'package:openlib/services/webview_challenge_solver.dart';

/// Builds an open-slum.org page in the exact shape SLUM serves: one
/// `div.card` per mirror with a `card-title` link, a status badge and,
/// for gated mirrors, the "Protected Site" block naming the vendor.
String slumPage(List<({String url, String status, String? vendor})> mirrors) {
  final cards = StringBuffer();
  for (var i = 0; i < mirrors.length; i++) {
    final mirror = mirrors[i];
    final host = Uri.parse(mirror.url).host;
    cards.write('''
<div class="card" id="annas.m$i">
  <div class="card-header">
    <div class="domain-info">
      <a href="${mirror.url}" class="card-title" target="_blank" rel="noopener noreferrer">$host</a>
    </div>
    <div style="display: flex; align-items: center; gap: 0.75rem;">
      <span class="status-badge ${mirror.status}">${mirror.status.toUpperCase()}</span>
    </div>
  </div>
  <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 1rem;">
    <div><div>Expected</div><div>Status: <span>200</span></div></div>
    <div><div>Actual</div><div>Status: <span>200</span></div>
      <div>Latency: <span>120ms</span></div></div>
  </div>
''');
    if (mirror.vendor != null) {
      cards.write('''
  <div style="margin-top: 0.75rem; padding: 0.5rem;">
    <strong style="color: #3fb950;">Protected Site</strong>
    <span style="color: #58a6ff; margin-left: 0.5rem;">${mirror.vendor}</span>
    <p style="margin: 0.25rem 0 0 0;">Bot protection active.</p>
  </div>
''');
    }
    cards.write('</div>\n');
  }
  return '<!doctype html><html><body>$cards</body></html>';
}

void main() {
  /// URLs the (test-registered) visible solver hook was asked for.
  final gatewayCalls = <String>[];

  /// The query every search in this file uses.
  const gatewayQuery = 'harry potter';
  /// Serves any request with [body], recording the paths it was asked for.
  Future<(HttpServer, List<String>)> mirrorServer(
      {String? body, int status = 200}) async {
    final hits = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      hits.add(request.uri.toString());
      request.response
        ..statusCode = status
        ..headers.contentType = ContentType.html
        ..write(body ?? '');
      await request.response.close();
    });
    return (server, hits);
  }

  final searchFixture =
      File('test/fixtures/search_results_sample.html').readAsStringSync();

  group("Anna's Archive mirror walk (SLUM -> order -> fetch)", () {
    test('tries the unprotected mirror before the DDoS-Guard one', () async {
      // The SLUM page lists the GATED mirror first on purpose: the app
      // must still try the unprotected one first.
      final (dead, deadHits) = await mirrorServer(status: 403);
      final (gated, gatedHits) = await mirrorServer(body: searchFixture);

      final (slum, _) = await mirrorServer(
        body: slumPage([
          (
            url: 'http://127.0.0.1:${gated.port}',
            status: 'protected',
            vendor: 'DDoS-Guard'
          ),
          (
            url: 'http://127.0.0.1:${dead.port}',
            status: 'up',
            vendor: null
          ),
        ]),
      );

      try {
        final manager = InstanceManager.forTest(
          catalogue: SlumCatalogue(
            store: MemoryPreferenceStore(),
            baseUrl: 'http://127.0.0.1:${slum.port}',
          ),
          store: MemoryPreferenceStore(),
        );

        final api = AnnasArchieve(instanceManager: manager);
        final books = await api.searchBooks(searchQuery: 'harry potter');

        expect(deadHits, isNotEmpty,
            reason: 'the unprotected mirror is attempted');
        expect(gatedHits, isNotEmpty,
            reason: 'the walk must reach the gated mirror after the failure');
        expect(books, isNotEmpty,
            reason: 'the gated mirror serves real results and they parse');
        expect(books.first.md5, isNotEmpty);
      } finally {
        await dead.close();
        await gated.close();
        await slum.close();
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('a mirror that is not Anna\'s Archive is skipped, not read as empty',
        () async {
      // open-slum.org lists software.annas-archive.gl among the AA mirrors;
      // it serves a GitLab instance. A 200 from it must fail the mirror and
      // let the walk continue, instead of parsing to zero books and making
      // the whole search look empty.
      const gitlab = '<!doctype html><html><head><title>Search · GitLab'
          '</title></head><body><div class="content">Search</div>'
          '</body></html>';
      final (junk, junkHits) = await mirrorServer(body: gitlab);
      final (real, realHits) = await mirrorServer(body: searchFixture);

      final (slum, _) = await mirrorServer(
        body: slumPage([
          // Unprotected, so the walk reaches the junk mirror first.
          (url: 'http://127.0.0.1:${junk.port}', status: 'up', vendor: null),
          (
            url: 'http://127.0.0.1:${real.port}',
            status: 'protected',
            vendor: 'DDoS-Guard'
          ),
        ]),
      );

      try {
        final manager = InstanceManager.forTest(
          catalogue: SlumCatalogue(
            store: MemoryPreferenceStore(),
            baseUrl: 'http://127.0.0.1:${slum.port}',
          ),
          store: MemoryPreferenceStore(),
        );

        final books = await AnnasArchieve(instanceManager: manager)
            .searchBooks(searchQuery: 'harry potter');

        expect(junkHits, isNotEmpty, reason: 'the junk mirror is contacted');
        expect(realHits, isNotEmpty,
            reason: 'the walk must continue past the non-archive mirror');
        expect(books, isNotEmpty, reason: 'the real mirror serves results');
      } finally {
        await junk.close();
        await real.close();
        await slum.close();
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('a mirror SLUM reports DOWN is never contacted', () async {
      final (down, downHits) = await mirrorServer(body: searchFixture);
      final (up, upHits) = await mirrorServer(body: searchFixture);

      final (slum, _) = await mirrorServer(
        body: slumPage([
          (url: 'http://127.0.0.1:${down.port}', status: 'down', vendor: null),
          (url: 'http://127.0.0.1:${up.port}', status: 'up', vendor: null),
        ]),
      );

      try {
        final manager = InstanceManager.forTest(
          catalogue: SlumCatalogue(
            store: MemoryPreferenceStore(),
            baseUrl: 'http://127.0.0.1:${slum.port}',
          ),
          store: MemoryPreferenceStore(),
        );

        final books =
            await AnnasArchieve(instanceManager: manager).searchBooks(
          searchQuery: 'harry potter',
        );

        expect(downHits, isEmpty,
            reason: 'a mirror SLUM reports DOWN must never be contacted');
        expect(upHits, isNotEmpty);
        expect(books, isNotEmpty);
      } finally {
        await down.close();
        await up.close();
        await slum.close();
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('with no reachable mirror it reports that instead of guessing a URL',
        () async {
      final (slum, _) = await mirrorServer(body: slumPage(const []));

      try {
        final manager = InstanceManager.forTest(
          catalogue: SlumCatalogue(
            store: MemoryPreferenceStore(),
            baseUrl: 'http://127.0.0.1:${slum.port}',
          ),
          store: MemoryPreferenceStore(),
        );

        await expectLater(
          AnnasArchieve(instanceManager: manager)
              .searchBooks(searchQuery: 'harry potter'),
          throwsA(anything),
        );
      } finally {
        await slum.close();
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('a DDoS-Guard interstitial surfaces as a challenge, not as results',
        () async {
      // The real DDoS-Guard page shape: a 200 whose title is the tell.
      final challenge = '<!doctype html><html><head>'
          '<title>DDoS-Guard</title></head><body>'
          '<script src="https://check.ddos-guard.net/check.js"></script>'
          '<h1>Checking your browser before accessing</h1></body></html>';
      final (mirror, _) = await mirrorServer(body: challenge);

      final (slum, _) = await mirrorServer(
        body: slumPage([
          (
            url: 'http://127.0.0.1:${mirror.port}',
            status: 'protected',
            vendor: 'DDoS-Guard'
          ),
        ]),
      );

      try {
        final manager = InstanceManager.forTest(
          catalogue: SlumCatalogue(
            store: MemoryPreferenceStore(),
            baseUrl: 'http://127.0.0.1:${slum.port}',
          ),
          store: MemoryPreferenceStore(),
        );

        // The solver cannot run in a test VM, so the challenge must come
        // back as an error - never as a fabricated book list.
        await expectLater(
          AnnasArchieve(instanceManager: manager)
              .searchBooks(searchQuery: 'harry potter'),
          throwsA(anything),
        );
      } finally {
        await mirror.close();
        await slum.close();
      }
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
  // Production paths through the webview solver: real captured
  // interstitials (Cloudflare from welib.org, DDoS-Guard from
  // annas-archive.gl) must route into the solver, whose captured page
  // is the real AA search markup - or the failure must be honest.
  group("Anna's Archive webview solver flow (real pages)", () {
    final cfInterstitial =
        File('test/fixtures/cloudflare_interstitial.html').readAsStringSync();
    final ddgInterstitial =
        File('test/fixtures/ddosguard_interstitial.html').readAsStringSync();
    final plain403 = File('test/fixtures/aa_plain_403.html').readAsStringSync();
    final searchFixture =
        File('test/fixtures/search_results_sample.html').readAsStringSync();

    setUp(() {
      ChallengeHtmlCache.clear();
    });

    /// Serves [body] with [status] and [extraHeaders], recording every
    /// request. [body2]/[status2] apply from the [afterHits]th request
    /// on, so one server can play both the gated and the healthy state.
    Future<(HttpServer, List<String>)> serving(
      String body,
      int status, {
      Map<String, String> extraHeaders = const {},
      String? body2,
      int status2 = 200,
      int afterHits = 1,
    }) async {
      final hits = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        hits.add(request.uri.toString());
        final first = hits.length <= afterHits;
        final response = request.response;
        response.statusCode = first ? status : status2;
        for (final entry in extraHeaders.entries) {
          response.headers.set(entry.key, entry.value);
        }
        response.headers.contentType = ContentType.html;
        response.write(first ? body : (body2 ?? body));
        await response.close();
      });
      return (server, hits);
    }

    /// Solver seam: the registered visible-solver hook plays the
    /// webview. No real window is opened (guiEnabled stays off).
    void enableSolverSeam() {
      WebviewChallengeSolver.guiEnabled = false;
      WebviewChallengeSolver.overrideIsMobile = true;
      WebviewChallengeSolver.headlessEnabled = false;
      WebviewChallengeSolver.visibleSolverFallback = (url) async {
        gatewayCalls.add(url);
        return searchFixture;
      };
      addTearDown(() {
        WebviewChallengeSolver.guiEnabled = true;
        WebviewChallengeSolver.overrideIsMobile = null;
        WebviewChallengeSolver.headlessEnabled = true;
        WebviewChallengeSolver.visibleSolverFallback = null;
      });
    }

    setUp(() {
      gatewayCalls.clear();
    });

    InstanceManager managerFor(HttpServer slum) => InstanceManager.forTest(
          catalogue: SlumCatalogue(
            store: MemoryPreferenceStore(),
            baseUrl: 'http://127.0.0.1:${slum.port}',
          ),
          store: MemoryPreferenceStore(),
        );

    test('a Cloudflare 403 with the cf-mitigated header reaches the solver',
        () async {
      final (mirror, mirrorHits) = await serving(
        cfInterstitial,
        403,
        extraHeaders: {'cf-mitigated': 'challenge'},
        afterHits: 999,
      );
      enableSolverSeam();

      try {
        final (slum, _) = await serving(slumPage([
          (
            url: 'http://127.0.0.1:${mirror.port}',
            status: 'protected',
            vendor: 'Cloudflare'
          ),
        ]), 200);

        try {
          final manager = managerFor(slum);
          final books = await AnnasArchieve(
            dio: Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 5),
            )),
            instanceManager: manager,
          ).searchBooks(searchQuery: gatewayQuery);

          expect(books, isNotEmpty,
              reason: 'the solved page must parse into real book records');
          expect(gatewayCalls, isNotEmpty,
              reason: 'the solver must actually run for the blocked URL');
          expect(gatewayCalls.single, contains(mirror.port.toString()),
              reason: 'the solver must be asked for the blocked mirror URL');
        } finally {
          await slum.close();
        }
      } finally {
        await mirror.close();
      }
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('the real DDoS-Guard interstitial reaches the solver and parses',
        () async {
      // Captured live from annas-archive.gl: 302 to ?check=1, then 403
      // with the interstitial. Its title and check.ddos-guard.net must
      // be recognized whatever the status is.
      final (mirror, _) = await serving(ddgInterstitial, 403, afterHits: 999);
      enableSolverSeam();

      final (slum, _) = await serving(slumPage([
        (
          url: 'http://127.0.0.1:${mirror.port}',
          status: 'protected',
          vendor: 'DDoS-Guard'
        ),
      ]), 200);

      try {
        final books = await AnnasArchieve(
          dio: Dio(BaseOptions(
            connectTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 5),
          )),
          instanceManager: managerFor(slum),
        ).searchBooks(searchQuery: gatewayQuery);

        expect(books, isNotEmpty,
            reason: 'the solved capture must parse into records');
        expect(gatewayCalls, isNotEmpty);
      } finally {
        await mirror.close();
        await slum.close();
      }
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('a solved page is reused from the cache - zero extra requests',
        () async {
      final (mirror, mirrorHits) =
          await serving(cfInterstitial, 403, afterHits: 999);
      enableSolverSeam();

      final (slum, _) = await serving(slumPage([
        (
          url: 'http://127.0.0.1:${mirror.port}',
          status: 'protected',
          vendor: 'Cloudflare'
        ),
      ]), 200);

      try {
        final api = AnnasArchieve(
          dio: Dio(BaseOptions(
            connectTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 5),
          )),
          instanceManager: managerFor(slum),
        );

        final first = await api.searchBooks(searchQuery: gatewayQuery);
        expect(first, isNotEmpty);
        final hitsAfterFirstSolve = mirrorHits.length;
        expect(hitsAfterFirstSolve, greaterThanOrEqualTo(1));

        // A retry (Try Again / next page) must parse the previously
        // captured page without contacting the challenge again.
        final second = await api.searchBooks(searchQuery: gatewayQuery);
        expect(second, isNotEmpty);
        expect(mirrorHits.length, hitsAfterFirstSolve,
            reason: 'the cache must absorb the retry entirely');
        expect(gatewayCalls.length, 1,
            reason: 'no second solve is needed for the same URL');
      } finally {
        await mirror.close();
        await slum.close();
      }
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('a plain 403 "link expired" page is an error, never results',
        () async {
      // Captured live from an AA download mirror: 403 and normal text,
      // no challenge anywhere. A bare 403 is a refusal, not a block:
      // the solver must stay idle and the failure must propagate as an
      // error (never as a silent empty result or spurious solve).
      final (mirror, _) = await serving(plain403, 403, afterHits: 999);
      enableSolverSeam();

      final (slum, _) = await serving(slumPage([
        (
          url: 'http://127.0.0.1:${mirror.port}',
          status: 'up',
          vendor: null
        ),
      ]), 200);

      try {
        NetworkError? error;
        try {
          await AnnasArchieve(
            dio: Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 5),
            )),
            instanceManager: managerFor(slum),
          ).searchBooks(searchQuery: gatewayQuery);
        } on NetworkError catch (e) {
          error = e;
        } on DioException {
          error = null;
        }

        expect(error, isNotNull,
            reason: 'a refused mirror must fail loudly');
        expect(error!.type, isNot(NetworkErrorType.cloudflareBlock),
            reason: 'without challenge signals this is a plain refusal');
        expect(gatewayCalls, isEmpty,
            reason: 'no interstitial means no solver run');
      } finally {
        await mirror.close();
        await slum.close();
        ChallengeHtmlCache.clear();
      }
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('the same solver seam serves bookInfo pages', () async {
      // Book info goes through the identical gate as search: a real
      // captured AA book page must come back parsed once the solver
      // returned it, with the blocked mirror stopping the request.
      final (mirror, _) = await serving(
        cfInterstitial,
        403,
        extraHeaders: {'cf-mitigated': 'challenge'},
        afterHits: 999,
      );
      WebviewChallengeSolver.guiEnabled = false;
      WebviewChallengeSolver.overrideIsMobile = true;
      WebviewChallengeSolver.headlessEnabled = false;
      final bookFixture =
          File('test/fixtures/real_aa_book_page.html').readAsStringSync();
      WebviewChallengeSolver.visibleSolverFallback = (url) async {
        gatewayCalls.add(url);
        return bookFixture;
      };
      addTearDown(() {
        WebviewChallengeSolver.guiEnabled = true;
        WebviewChallengeSolver.overrideIsMobile = null;
        WebviewChallengeSolver.headlessEnabled = true;
        WebviewChallengeSolver.visibleSolverFallback = null;
      });

      final (slum, _) = await serving(slumPage([
        (
          url: 'http://127.0.0.1:${mirror.port}',
          status: 'protected',
          vendor: 'Cloudflare'
        ),
      ]), 200);

      try {
        const md5 = '0b2d8c9a4a4e7f3a1d5c9e2b8a7f6d4e';
        final bookUrl = 'http://127.0.0.1:${mirror.port}/md5/$md5';
        final api = AnnasArchieve(
          dio: Dio(BaseOptions(
            connectTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 5),
          )),
          instanceManager: managerFor(slum),
        );

        final info = await api.bookInfo(url: bookUrl);

        // The solver path must render exactly the details the real
        // parser produces for this captured page - no more, no less.
        final direct = await api.bookInfoParser(
            bookFixture, bookUrl, 'http://127.0.0.1:${mirror.port}');
        expect(direct, isNotNull,
            reason: 'the real parser must handle the capture directly');

        expect(info.title, isNotEmpty);
        expect(info.title, contains('Villa Coco'),
            reason: 'the capture is the real book page');
        expect(info.title, equals(direct!.title));
        expect(info.format, equals(direct.format));
        expect(info.format, isNot(contains('script')),
            reason: 'no script source leaks into the parsed format');
        expect(gatewayCalls, [bookUrl],
            reason: 'the solver was the only way through');
      } finally {
        await mirror.close();
        await slum.close();
        ChallengeHtmlCache.clear();
      }
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('a 500 on the first mirror moves on to the next one', () async {
      final (dead, deadHits) = await serving('<html>500</html>', 500,
          body2: searchFixture, status2: 200, afterHits: 1);
      final (slum, _) = await serving(slumPage([
        (
          url: 'http://127.0.0.1:${dead.port}',
          status: 'up',
          vendor: null
        ),
      ]), 200);

      try {
        final books = await AnnasArchieve(
          dio: Dio(BaseOptions(
            connectTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 5),
          )),
          instanceManager: managerFor(slum),
        ).searchBooks(searchQuery: gatewayQuery);

        expect(books, isNotEmpty,
            reason: 'the healthy response must be found after the 500s');
        expect(deadHits.length, 2,
            reason: 'one retry on the only mirror, then success');
      } finally {
        await dead.close();
        await slum.close();
      }
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

}
