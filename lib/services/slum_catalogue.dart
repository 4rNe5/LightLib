// Dart imports:
import 'dart:async';
import 'dart:convert';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:dio/dio.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

// Project imports:
import 'package:openlib/services/logger.dart';
import 'package:openlib/services/preference_store.dart';

/// Which shadow-library family a mirror belongs to.
///
/// This is the single source of truth for "who is a provider": the
/// search providers, the settings page and the instance manager all
/// speak in these values.
enum MirrorService {
  annasArchive,
  libgen,
  zlibrary,

  /// WeLib (open-slum.org's "other" page). Its search sits behind
  /// Cloudflare, so it is the last-resort source.
  welib,
}

/// What open-slum.org (SLUM) last saw for a mirror.
enum SlumStatus { up, protected, degraded, down, unknown }

/// The bot-protection gate a mirror sits behind, ordered from easiest
/// to hardest to pass without a browser:
///
///   none       - plain HTTP works
///   diamwall   - SHA1 proof-of-work, solvable in-app (see DiamWallSolver)
///   ddosGuard  - JS challenge, needs the webview solver
///   cloudflare - JS challenge, needs the webview solver
///   unknown    - a gate SLUM could not classify
///
/// Auto mode tries them in this order; a mirror that is DOWN is never
/// tried at all.
enum Protection { none, diamwall, ddosGuard, cloudflare, unknown }

extension ProtectionRank on Protection {
  /// Lower is tried first. Exposed so ordering lives in one place.
  int get rank => switch (this) {
        Protection.none => 0,
        Protection.diamwall => 1,
        Protection.ddosGuard => 2,
        Protection.cloudflare => 3,
        Protection.unknown => 4,
      };

  /// Label for the settings UI.
  String get label => switch (this) {
        Protection.none => 'Unprotected',
        Protection.diamwall => 'DiamWall',
        Protection.ddosGuard => 'DDoS-Guard',
        Protection.cloudflare => 'Cloudflare',
        Protection.unknown => 'Unknown',
      };

  /// True when a plain Dio client has any chance without a browser.
  /// Used to decide whether a provider should even attempt a mirror.
  bool get solvableHeadless => this == Protection.none || this == Protection.diamwall;
}

/// One mirror as open-slum.org reports it, plus the two facts SLUM
/// gives that matter for ordering: how it is protected and whether it
/// is currently up.
@immutable
class SlumSite {
  final MirrorService service;
  final String url;

  /// Bare host, e.g. `z-lib.gd`. The stable key for user preferences.
  final String host;

  final SlumStatus status;
  final Protection protection;

  /// HTTP status SLUM's last check received (null when it could not
  /// connect at all).
  final int? httpStatus;

  /// SLUM's measured latency in milliseconds.
  final int? latencyMs;

  const SlumSite({
    required this.service,
    required this.url,
    required this.host,
    required this.status,
    required this.protection,
    this.httpStatus,
    this.latencyMs,
  });

  /// SLUM says it is down: never search or download on it.
  bool get isDown => status == SlumStatus.down;

  /// A mirror we may attempt: not down. `unknown` is attempted last -
  /// SLUM simply has no reading, which is not the same as down.
  bool get isAttemptable => !isDown;

  /// Sort key inside auto mode. Down mirrors sort last so a stable
  /// order still exists when a caller asks for "everything".
  int get statusTier => switch (status) {
        SlumStatus.up => 0,
        SlumStatus.degraded => 1,
        SlumStatus.protected => 2,
        SlumStatus.unknown => 3,
        SlumStatus.down => 9,
      };

  @override
  String toString() =>
      'SlumSite($host, ${status.name}, ${protection.name})';
}

/// Reads mirror lists and their status from open-slum.org.
///
/// This is the **only** place mirror URLs come from: nothing else in
/// the app hardcodes a libgen/zlib/AA/welib host. SLUM publishes one
/// static HTML page per service:
///
///   annas.html     -> Anna's Archive mirrors
///   libgen.html    -> Library Genesis mirrors
///   zlibrary.html  -> Z-Library mirrors
///   other.html     -> WeLib and friends
///
/// Each page lists `<div class="card" id="service.host">` blocks with a
/// `card-title` link (the URL), a `status-badge <status>` and - for
/// gated mirrors - a "Protected Site" block naming the vendor
/// (Cloudflare / DiamWall / DDoS-Guard).
///
/// Everything is cached in memory for [ttl] and persisted, so a cold
/// start with SLUM unreachable still knows the last known mirrors. When
/// SLUM cannot be reached *and* nothing is cached the list is empty -
/// the app then reports "no mirrors" instead of guessing a URL.
class SlumCatalogue {
  SlumCatalogue({Dio? dio, PreferenceStore? store, String? baseUrl})
      : _dio = dio ??
            createDioWithLogging(
                options: BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              headers: const {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                    'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 '
                    'Safari/537.36',
              },
            )),
        _store = store,
        _baseUrl = baseUrl ?? defaultBaseUrl;

  final Dio _dio;
  final PreferenceStore? _store;
  final String _baseUrl;

  /// The one URL the app is allowed to hardcode: the monitor itself.
  static const String defaultBaseUrl = 'https://open-slum.org';

  /// Kept as `baseUrl` for callers that only ever read it.
  static const String baseUrl = defaultBaseUrl;

  /// Page per service. `welib` lives on SLUM's "other" page.
  static const Map<MirrorService, String> pages = {
    MirrorService.annasArchive: 'annas.html',
    MirrorService.libgen: 'libgen.html',
    MirrorService.zlibrary: 'zlibrary.html',
    MirrorService.welib: 'other.html',
  };

  /// Hosts on the "other" page that are not WeLib. Kept explicit so a
  /// new entrant on that page does not silently become a provider.
  static const Set<String> _otherPageSkipHosts = {
    'libstc.nexus',
    'liber3.eth.limo',
    'library.memoryoftheworld.org',
  };

  /// How long a fetched catalogue stays fresh.
  static const Duration ttl = Duration(minutes: 10);

  static const String _cacheKey = 'slum_catalogue_cache';

  Map<MirrorService, List<SlumSite>> _cache = {};
  DateTime? _fetchedAt;

  /// When the last fetch attempt started. Used to throttle retries after
  /// a fetch that produced nothing at all.
  DateTime? _lastAttemptAt;

  /// True when the most recent fetch got at least one mirror (from SLUM
  /// or carried over from cache). The Mirrors page uses it to tell
  /// "nothing changed" apart from "SLUM was unreachable".
  bool get lastFetchSucceeded => _lastFetchSucceeded;
  bool _lastFetchSucceeded = true;

  /// How long to wait before trying SLUM again after a fetch yielded
  /// nothing. Long enough that an outage does not turn every provider
  /// call into four requests, short enough that the user does not stare
  /// at an empty list for the whole [ttl].
  static const Duration _retryAfterFailedFetch = Duration(seconds: 30);

  bool get _isFresh =>
      _fetchedAt != null && DateTime.now().difference(_fetchedAt!) < ttl;

  /// The mirrors of one service, in SLUM's page order. Ordering (see
  /// [SlumCatalogue.sortAuto]) is applied by [InstanceManager.instances].
  /// Returns an empty list when SLUM is unreachable and nothing is cached.
  Future<List<SlumSite>> sites(MirrorService service,
      {bool force = false}) async {
    final all = await fetchAll(force: force);
    return all[service] ?? const [];
  }

  /// Every service's mirrors, fetched in parallel. Cached for [ttl].
  ///
  /// A fetch that gets nothing at all (SLUM unreachable, cold start) is
  /// deliberately NOT counted as fresh: freshness would otherwise freeze
  /// the empty list for the whole [ttl]. Retries are throttled by
  /// [_retryAfterFailedFetch] instead, and a "Try Again"/refresh passes
  /// `force: true`.
  Future<Map<MirrorService, List<SlumSite>>> fetchAll(
      {bool force = false}) async {
    if (!force && _isFresh) return _cache;

    final nothingKnown = _cache.values.every((sites) => sites.isEmpty);
    if (!force &&
        nothingKnown &&
        _lastAttemptAt != null &&
        DateTime.now().difference(_lastAttemptAt!) <
            _retryAfterFailedFetch) {
      return _cache;
    }
    _lastAttemptAt = DateTime.now();

    final results = await Future.wait([
      for (final service in MirrorService.values) _fetchOne(service),
    ]);

    final merged = <MirrorService, List<SlumSite>>{};
    for (var i = 0; i < MirrorService.values.length; i++) {
      final service = MirrorService.values[i];
      final sites = results[i];
      // Keep the previous list for a service SLUM failed on; an empty
      // fetch must not wipe mirrors we already know.
      if (sites.isNotEmpty || !_cache.containsKey(service)) {
        merged[service] = sites;
      } else {
        merged[service] = _cache[service]!;
      }
    }

    _cache = merged;
    final gotAnything = merged.values.any((sites) => sites.isNotEmpty);
    _lastFetchSucceeded = gotAnything;
    _fetchedAt = gotAnything ? DateTime.now() : null;
    await _persist(merged);
    return _cache;
  }

  /// Fetches and parses one service page. Empty on any failure or when
  /// the page parses to nothing - the caller decides whether to keep
  /// the previous list.
  Future<List<SlumSite>> _fetchOne(MirrorService service) async {
    final page = pages[service];
    if (page == null) return const [];
    try {
      final response = await _dio.get<String>('$_baseUrl/$page');
      if (response.statusCode != 200 || response.data == null) {
        AppLogger().warning('open-slum page answered a non-200',
            tag: 'SlumCatalogue',
            metadata: {'service': service.name, 'status': response.statusCode});
        return const [];
      }
      final sites = parsePage(response.data!, service);
      AppLogger().info('open-slum: ${sites.length} ${service.name} mirrors',
          tag: 'SlumCatalogue');
      return sites;
    } catch (e) {
      AppLogger().warning('open-slum page unreachable, using cache',
          tag: 'SlumCatalogue', error: e, metadata: {'service': service.name});
      return const [];
    }
  }

  /// Parses one SLUM service page. Public so tests (and the persisted
  /// cache) can feed captured HTML without network.
  @visibleForTesting
  List<SlumSite> parsePage(String html, MirrorService service) {
    final document = html_parser.parse(html);
    final sites = <SlumSite>[];

    for (final card in document.querySelectorAll('div.card[id]')) {
      final link = card.querySelector('a.card-title');
      final href = link?.attributes['href'];
      if (href == null || href.isEmpty) continue;

      final uri = Uri.tryParse(href);
      final host = uri?.host;
      if (host == null || host.isEmpty) continue;

      // The "other" page mixes WeLib with unrelated libraries; only the
      // service's own hosts become mirrors.
      if (service == MirrorService.welib) {
        if (!host.contains('welib') || _otherPageSkipHosts.contains(host)) {
          continue;
        }
      }

      final status = _parseStatus(card);
      final protection = _parseProtection(card, status);
      final httpStatus = _parseIntAfterLabel(card, 'Status:');
      final latencyMs = _parseIntAfterLabel(card, 'Latency:');

      sites.add(SlumSite(
        service: service,
        url: _normalize(href),
        host: host,
        status: status,
        protection: protection,
        httpStatus: httpStatus,
        latencyMs: latencyMs,
      ));
    }

    return sites;
  }

  /// The badge class carries the current status (`status-badge down`).
  /// Falls back to the last timeline reading when the badge is absent
  /// (or a variant SLUM did not style).
  SlumStatus _parseStatus(dom.Element card) {
    final badge = card.querySelector('.status-badge');
    final raw = badge?.attributes['class'] ?? '';
    final match = RegExp(r'\b(up|protected|degraded|down|unknown)\b',
            caseSensitive: false)
        .firstMatch(raw);
    final fromBadge = _statusFromWord(match?.group(1));
    if (fromBadge != null) return fromBadge;

    // Timeline readings are oldest first; the last one is the newest.
    final readings =
        card.querySelectorAll('[data-status]').map((e) => e.attributes['data-status']);
    for (final value in readings.toList().reversed) {
      final parsed = _statusFromWord(value);
      if (parsed != null) return parsed;
    }
    return SlumStatus.unknown;
  }

  SlumStatus? _statusFromWord(String? word) => switch (word?.toLowerCase()) {
        'up' => SlumStatus.up,
        'protected' => SlumStatus.protected,
        'degraded' => SlumStatus.degraded,
        'down' => SlumStatus.down,
        'unknown' => SlumStatus.unknown,
        _ => null,
      };

  /// The "Protected Site" block names the vendor. A protected mirror
  /// without a vendor is [Protection.unknown]; an UP mirror has no gate.
  Protection _parseProtection(dom.Element card, SlumStatus status) {
    final vendor = _vendorName(card);
    if (vendor != null) {
      final lower = vendor.toLowerCase();
      if (lower.contains('diamwall')) return Protection.diamwall;
      if (lower.contains('ddos')) return Protection.ddosGuard;
      if (lower.contains('cloudflare')) return Protection.cloudflare;
      return Protection.unknown;
    }
    // No vendor label: only claim "none" when SLUM saw it plain.
    return status == SlumStatus.up ? Protection.none : Protection.unknown;
  }

  String? _vendorName(dom.Element card) {
    for (final strong in card.querySelectorAll('strong')) {
      if (strong.text.trim().toLowerCase().contains('protected site')) {
        final span = strong.nextElementSibling;
        final name = span?.text.trim() ?? '';
        if (name.isNotEmpty) return name;
      }
    }
    return null;
  }

  int? _parseIntAfterLabel(dom.Element card, String label) {
    for (final div in card.querySelectorAll('div')) {
      final text = div.text;
      final index = text.indexOf(label);
      if (index == -1) continue;
      final match = RegExp(r'\d+').firstMatch(text.substring(index + label.length));
      if (match != null) return int.tryParse(match.group(0)!);
    }
    return null;
  }

  String _normalize(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  /// Auto order: never-down mirrors first by protection difficulty
  /// (unprotected -> DiamWall -> DDoS-Guard/Cloudflare -> unknown), then
  /// by SLUM status, then by latency. Mirrors SLUM reports DOWN sort
  /// last whatever their protection - they are never attempted - and
  /// callers that must not touch them filter with [SlumSite.isDown].
  static List<SlumSite> sortAuto(Iterable<SlumSite> sites) {
    final list = sites.toList();
    list.sort((a, b) {
      if (a.isDown != b.isDown) return a.isDown ? 1 : -1;
      final byProtection = a.protection.rank.compareTo(b.protection.rank);
      if (byProtection != 0) return byProtection;
      final byStatus = a.statusTier.compareTo(b.statusTier);
      if (byStatus != 0) return byStatus;
      final byLatency =
          (a.latencyMs ?? 1 << 30).compareTo(b.latencyMs ?? 1 << 30);
      if (byLatency != 0) return byLatency;
      return a.host.compareTo(b.host);
    });
    return list;
  }

  // ------------------------------------------------------------------
  // Persistence: the last good catalogue survives restarts and lets a
  // cold start with SLUM unreachable still find mirrors.
  // ------------------------------------------------------------------

  Future<void> _persist(Map<MirrorService, List<SlumSite>> all) async {
    final store = _store;
    if (store == null) return;
    try {
      final json = {
        for (final entry in all.entries)
          entry.key.name: [for (final site in entry.value) _siteToJson(site)],
      };
      await store.write(_cacheKey, jsonEncode(json));
    } catch (_) {
      // Persistence is best-effort; the in-memory cache already has it.
    }
  }

  /// Loads the persisted catalogue into the cache. Called once at
  /// startup so the first search does not depend on SLUM being up.
  Future<void> restore() async {
    final store = _store;
    if (store == null) return;
    try {
      final raw = await store.read(_cacheKey);
      if (raw is! String || raw.isEmpty) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;

      final restored = <MirrorService, List<SlumSite>>{};
      for (final service in MirrorService.values) {
        final list = decoded[service.name];
        if (list is! List) continue;
        restored[service] = [
          for (final item in list)
            if (item is Map<String, dynamic>) _siteFromJson(item, service),
        ];
      }
      if (restored.isNotEmpty && _cache.isEmpty) {
        _cache = restored;
        // Deliberately leave _fetchedAt null: persisted data is a
        // fallback, not a fresh reading, so the next fetch still runs.
      }
    } catch (_) {
      // A corrupt cache is simply ignored.
    }
  }

  Map<String, dynamic> _siteToJson(SlumSite site) => {
        'url': site.url,
        'host': site.host,
        'status': site.status.name,
        'protection': site.protection.name,
        'httpStatus': site.httpStatus,
        'latencyMs': site.latencyMs,
      };

  SlumSite _siteFromJson(Map<String, dynamic> json, MirrorService service) {
    SlumStatus status = SlumStatus.unknown;
    Protection protection = Protection.unknown;
    for (final value in SlumStatus.values) {
      if (value.name == json['status']) status = value;
    }
    for (final value in Protection.values) {
      if (value.name == json['protection']) protection = value;
    }
    final url = json['url'] as String? ?? '';
    return SlumSite(
      service: service,
      url: url,
      host: json['host'] as String? ?? Uri.tryParse(url)?.host ?? '',
      status: status,
      protection: protection,
      httpStatus: json['httpStatus'] as int?,
      latencyMs: json['latencyMs'] as int?,
    );
  }
}
