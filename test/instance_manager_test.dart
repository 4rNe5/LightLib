// Tests for the mirror-selection rules the app promises:
//
//  * mirror URLs come from open-slum.org, never from the app;
//  * a mirror SLUM reports DOWN is never handed to a provider;
//  * auto mode orders by protection difficulty (unprotected -> DiamWall
//    -> the browser-only gates), manual mode follows the user;
//  * switching a mirror off removes it from the provider list.
//
// The catalogue talks to a real local HTTP server that serves the pages
// captured from open-slum.org, so the whole path - HTTP, parsing, user
// preferences, ordering - is exercised for real.

// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/services/instance_manager.dart';
import 'package:openlib/services/preference_store.dart';
import 'package:openlib/services/slum_catalogue.dart';

/// Serves the captured open-slum.org pages under their real paths.
Future<HttpServer> _slumServer() async {
  // The live paths map onto the fixtures captured from them.
  const files = {
    '/annas.html': 'slum_annas.html',
    '/libgen.html': 'slum_libgen.html',
    '/zlibrary.html': 'slum_zlibrary.html',
    '/other.html': 'slum_other.html',
  };

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final name = files[request.uri.path];
    final file = name == null ? null : File('test/fixtures/$name');
    if (file != null && await file.exists()) {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..write(await file.readAsString());
    } else {
      request.response.statusCode = HttpStatus.notFound;
    }
    await request.response.close();
  });
  return server;
}

void main() {
  late HttpServer server;
  late InstanceManager manager;
  late MemoryPreferenceStore store;

  setUp(() async {
    server = await _slumServer();
    final base = 'http://127.0.0.1:${server.port}';
    // A fresh in-memory preference store per test: the mirror rules are
    // exercised without the app's sqlite singleton.
    store = MemoryPreferenceStore();
    manager = InstanceManager.forTest(
      catalogue: SlumCatalogue(store: store, baseUrl: base),
      store: store,
    );
  });

  tearDown(() async {
    await server.close();
  });

  group('mirror source', () {
    test('every mirror URL is the one open-slum.org publishes', () async {
      final views = await manager.instances(MirrorService.zlibrary,
          force: true);

      // From test/fixtures/slum_zlibrary.html.
      expect(views.map((v) => v.url), containsAll([
        'https://z-library.sk',
        'https://1lib.sk',
        'https://z-lib.gl',
        'https://z-lib.gd',
        'https://go-to-library.sk',
        'https://library-access.sk',
      ]));
      expect(views.map((v) => v.host), isNot(contains('welib.org')),
          reason: 'welib is its own service');
    });

    test('welib mirrors come from the "other" page', () async {
      final urls = await manager.enabledUrls(MirrorService.welib,
          force: true);
      expect(urls, ['https://welib.org']);
    });
  });

  group('down mirrors', () {
    test('are never handed to a provider', () async {
      // The libgen fixture has four mirrors DOWN and one degraded.
      final urls = await manager.enabledUrls(MirrorService.libgen,
          force: true);

      expect(urls, ['https://libgen.la'],
          reason: 'only the degraded mirror may be contacted');
    });

    test('are still listed for the UI, with status and protection', () async {
      final views =
          await manager.instances(MirrorService.libgen, force: true);

      expect(views, hasLength(5));
      final down = views.where((v) => v.isDown).toList();
      expect(down, hasLength(4));
      expect(down.every((v) => v.site.status == SlumStatus.down), isTrue);
    });

    test('sort last even when their protection is easier', () async {
      final views =
          await manager.instances(MirrorService.libgen, force: true);
      final firstDown =
          views.indexWhere((v) => v.isDown);
      final lastUp = views.lastIndexWhere((v) => !v.isDown);
      expect(lastUp, lessThan(firstDown),
          reason: 'all attemptable mirrors come before any down one');
    });
  });

  group('auto mode (default)', () {
    test('is on by default', () async {
      expect(await manager.isAutoMode(), isTrue);
    });

    test('orders DiamWall mirrors before the browser-only gates', () async {
      final urls = await manager.enabledUrls(MirrorService.zlibrary,
          force: true);

      // DiamWall gates come first because the app solves their proof of
      // work in-process; Cloudflare needs a browser.
      const diamwall = [
        'https://z-library.sk',
        'https://1lib.sk',
        'https://go-to-library.sk',
      ];
      const cloudflare = [
        'https://z-lib.gl',
        'https://z-lib.gd',
        'https://library-access.sk',
      ];

      final diamwallIndexes =
          diamwall.map((u) => urls.indexOf(u)).where((i) => i != -1);
      final cloudflareIndexes =
          cloudflare.map((u) => urls.indexOf(u)).where((i) => i != -1);

      expect(diamwallIndexes, isNotEmpty);
      expect(cloudflareIndexes, isNotEmpty);
      expect(diamwallIndexes.reduce((a, b) => a > b ? a : b),
          lessThan(cloudflareIndexes.reduce((a, b) => a < b ? a : b)),
          reason: 'every DiamWall mirror must precede every Cloudflare one');
    });

    test('headlessOnly drops mirrors a plain client can never pass', () async {
      final all = await manager.enabledUrls(MirrorService.zlibrary,
          force: true);
      final headless = await manager.enabledUrls(MirrorService.zlibrary,
          force: true, headlessOnly: true);

      expect(headless, isNotEmpty);
      expect(headless.length, lessThan(all.length));
      for (final url in headless) {
        final site = (await manager.instances(MirrorService.zlibrary))
            .firstWhere((v) => v.url == url)
            .site;
        expect(site.protection.solvableHeadless, isTrue);
      }
    });
  });

  group('user choices', () {
    test('a switched-off mirror disappears from the provider list', () async {
      await manager.setEnabled(MirrorService.zlibrary, 'z-lib.gd', false);

      final urls = await manager.enabledUrls(MirrorService.zlibrary,
          force: true);
      expect(urls, isNot(contains('https://z-lib.gd')));
      expect(urls, contains('https://z-lib.gl'));
    });

    test('the choice survives a fresh manager instance', () async {
      await manager.setEnabled(MirrorService.libgen, 'libgen.la', false);

      final second = InstanceManager.forTest(
        catalogue: SlumCatalogue(
          store: store,
          baseUrl: 'http://127.0.0.1:${server.port}',
        ),
        store: store,
      );
      expect(await second.enabledUrls(MirrorService.libgen), isEmpty,
          reason: 'the only attemptable mirror was switched off');
    });

    test('manual mode follows the user order, new mirrors come after',
        () async {
      await manager.setAutoMode(false);
      await manager.setManualOrder(MirrorService.zlibrary, [
        'z-lib.gd', // a Cloudflare mirror the user wants first
        'z-lib.gl',
      ]);

      final views =
          await manager.instances(MirrorService.zlibrary, force: true);
      expect(views[0].host, 'z-lib.gd');
      expect(views[1].host, 'z-lib.gl');
      // Everything the user did not pin keeps its auto position after the
      // pinned ones instead of disappearing.
      expect(views.length, 6);
    });

    test('move() shifts a mirror one slot in the manual order', () async {
      await manager.setAutoMode(false);
      final before = await manager.instances(MirrorService.zlibrary,
          force: true);
      final moving = before[1].host;

      await manager.move(MirrorService.zlibrary, moving, -1);

      final after =
          await manager.instances(MirrorService.zlibrary, force: true);
      expect(after[0].host, moving);
    });
  });
}
