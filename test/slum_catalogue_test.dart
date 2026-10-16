// Tests for the open-slum.org catalogue: the single source of mirror
// URLs. The parser runs against pages captured live from open-slum.org
// (one per service); the live group at the bottom re-fetches the real
// pages and is skipped by default because it needs the network.
//
//   flutter test --run-skipped test/slum_catalogue_test.dart

// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/services/slum_catalogue.dart';

String _fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  final catalogue = SlumCatalogue();

  group('annas page', () {
    late List<SlumSite> sites;

    setUpAll(() {
      sites = catalogue.parsePage(
          _fixture('slum_annas.html'), MirrorService.annasArchive);
    });

    test('lists every mirror SLUM publishes', () {
      final hosts = sites.map((s) => s.host).toSet();
      expect(hosts, containsAll(['annas-archive.gl', 'annas-archive.pk']));
      expect(sites.length, greaterThanOrEqualTo(4));
    });

    test('reads DDoS-Guard as the gate, not "protected" as a status only',
        () {
      final gl = sites.firstWhere((s) => s.host == 'annas-archive.gl');
      expect(gl.protection, Protection.ddosGuard);
      expect(gl.status, SlumStatus.protected);
      // DDoS-Guard is a browser-only gate: not solvable by plain Dio.
      expect(gl.protection.solvableHeadless, isFalse);
    });

    test('URLs are absolute and slash-free', () {
      for (final site in sites) {
        expect(site.url, startsWith('https://'));
        expect(site.url, isNot(endsWith('/')));
      }
    });
  });

  group('libgen page', () {
    late List<SlumSite> sites;

    setUpAll(() {
      sites = catalogue.parsePage(
          _fixture('slum_libgen.html'), MirrorService.libgen);
    });

    test('captures all five known mirror families', () {
      expect(sites.map((s) => s.host).toSet(), {
        'libgen.bz',
        'libgen.gl',
        'libgen.la',
        'libgen.vg',
        'libgen.li',
      });
    });

    test('marks the down mirrors down and the degraded one degraded', () {
      final down = sites.where((s) => s.isDown).map((s) => s.host).toSet();
      expect(down, containsAll(['libgen.bz', 'libgen.gl', 'libgen.vg', 'libgen.li']));

      final la = sites.firstWhere((s) => s.host == 'libgen.la');
      expect(la.status, SlumStatus.degraded);
      // Down mirrors are never attempted; degraded ones still are.
      expect(down.every((host) =>
          !sites.firstWhere((s) => s.host == host).isAttemptable), isTrue);
      expect(la.isAttemptable, isTrue);
    });
  });

  group('zlibrary page', () {
    late List<SlumSite> sites;

    setUpAll(() {
      sites = catalogue.parsePage(
          _fixture('slum_zlibrary.html'), MirrorService.zlibrary);
    });

    test('picks up every mirror, including ones added later', () {
      expect(sites.length, greaterThanOrEqualTo(6));
      expect(sites.map((s) => s.host), contains('z-lib.gd'));
      expect(sites.map((s) => s.host), contains('z-library.sk'));
    });

    test('distinguishes the DiamWall gate from the Cloudflare gate', () {
      final sk = sites.firstWhere((s) => s.host == 'z-library.sk');
      expect(sk.protection, Protection.diamwall);
      expect(sk.protection.solvableHeadless, isTrue,
          reason: 'DiamWall is the SHA1 PoW the app solves in-process');

      final cf = sites.where((s) => s.protection == Protection.cloudflare);
      expect(cf, isNotEmpty,
          reason: 'the page labels at least one mirror Cloudflare');
    });
  });

  group('other page (welib)', () {
    test('keeps only WeLib hosts', () {
      final sites = catalogue.parsePage(
          _fixture('slum_other.html'), MirrorService.welib);

      expect(sites, hasLength(1));
      expect(sites.single.host, 'welib.org');
      expect(sites.single.service, MirrorService.welib);
    });
  });

  group('auto ordering', () {
    SlumSite site(String host, Protection protection, SlumStatus status,
            {int? latency}) =>
        SlumSite(
          service: MirrorService.zlibrary,
          url: 'https://$host',
          host: host,
          status: status,
          protection: protection,
          latencyMs: latency,
        );

    test('unprotected first, then DiamWall, then the browser-only gates', () {
      final ordered = SlumCatalogue.sortAuto([
        site('cf', Protection.cloudflare, SlumStatus.protected),
        site('dw', Protection.diamwall, SlumStatus.protected),
        site('plain', Protection.none, SlumStatus.up),
        site('ddg', Protection.ddosGuard, SlumStatus.protected),
        site('unknown', Protection.unknown, SlumStatus.protected),
      ]);

      expect(ordered.map((s) => s.host).toList(),
          ['plain', 'dw', 'ddg', 'cf', 'unknown']);
    });

    test('down mirrors sink to the bottom and are never attempted', () {
      final ordered = SlumCatalogue.sortAuto([
        site('down', Protection.none, SlumStatus.down),
        site('up', Protection.cloudflare, SlumStatus.protected),
      ]);

      expect(ordered.first.host, 'up');
      expect(ordered.last.isDown, isTrue);
      expect(ordered.last.isAttemptable, isFalse);
    });

    test('latency breaks ties inside one protection tier', () {
      final ordered = SlumCatalogue.sortAuto([
        site('slow', Protection.cloudflare, SlumStatus.protected, latency: 900),
        site('fast', Protection.cloudflare, SlumStatus.protected, latency: 100),
      ]);
      expect(ordered.map((s) => s.host).toList(), ['fast', 'slow']);
    });
  });

  // The live catalogue: proves the parser still matches the real pages.
  // Opt-in because it needs the network; see the file header.
  group('live open-slum.org', () {
    test('fetches every service page and finds mirrors', () async {
      final all = await SlumCatalogue().fetchAll(force: true);

      for (final service in MirrorService.values) {
        expect(all[service], isNotNull,
            reason: 'SLUM must answer the ${service.name} page');
      }
      expect(all[MirrorService.zlibrary]!.length, greaterThanOrEqualTo(4),
          reason: 'z-library mirrors are listed on zlibrary.html');
      expect(all[MirrorService.libgen]!.length, greaterThanOrEqualTo(3));
      expect(all[MirrorService.annasArchive]!.length, greaterThanOrEqualTo(3));
      expect(all[MirrorService.welib]!.single.host, 'welib.org');
    }, skip: 'live network - run with --run-skipped');

    test('every mirror it reports resolves to a usable URL', () async {
      final sites = await SlumCatalogue()
          .sites(MirrorService.zlibrary, force: true);
      for (final site in sites) {
        expect(Uri.tryParse(site.url)?.hasAuthority, isTrue,
            reason: '${site.url} must be an absolute URL');
      }
    }, skip: 'live network - run with --run-skipped');
  });
}
