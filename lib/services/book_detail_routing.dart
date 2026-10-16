// Which provider serves a book-detail page.

// Project imports:
import 'package:openlib/services/instance_manager.dart';

/// The provider that can serve a book-detail URL.
enum BookDetailRoute { libgen, zlibrary, welib, annasArchive }

/// Book-detail services in matching order. A host belongs to exactly one
/// of them, so the first match wins.
const _routes = [
  (MirrorService.libgen, BookDetailRoute.libgen),
  (MirrorService.zlibrary, BookDetailRoute.zlibrary),
  (MirrorService.welib, BookDetailRoute.welib),
  (MirrorService.annasArchive, BookDetailRoute.annasArchive),
];

/// Routes a book-detail [url] to the provider that can actually serve it.
///
/// Mirrors come from open-slum.org and change over time, so the primary
/// signal is the host as the catalogue knows it. A hardcoded host list
/// goes stale the moment SLUM lists another mirror - Z-Library's
/// `go-to-library.sk` / `library-access.sk` broke routing exactly that
/// way. The catalogue is cached and persisted, so the lookup normally
/// costs nothing, and a mirror SLUM reports DOWN still routes correctly:
/// this only asks *which* service owns the host, the providers themselves
/// decide whether a request is attempted.
///
/// When no listed mirror matches (cold catalogue, unknown or bare host)
/// the URL's shape decides: libgen's `ads.php?md5=`, Z-Library's
/// `/book/...` (no other service serves that path), and everything else -
/// Anna's Archive and WeLib both use `/md5/...` - falls back to Anna's
/// Archive, the catch-all.
Future<BookDetailRoute> routeBookDetail(String url,
    {InstanceManager? manager}) async {
  if (url.contains('ads.php?md5=')) return BookDetailRoute.libgen;

  final host = Uri.tryParse(url)?.host ?? '';
  if (host.isNotEmpty) {
    try {
      final catalogueManager = manager ?? InstanceManager();
      for (final (service, route) in _routes) {
        final views = await catalogueManager.instances(service);
        if (views.any((view) => view.site.host == host)) return route;
      }
    } catch (_) {
      // Catalogue unavailable - the shape fallback below answers.
    }
  }

  final path = Uri.tryParse(url)?.path ?? url;
  if (RegExp(r'^/book/').hasMatch(path)) return BookDetailRoute.zlibrary;
  return BookDetailRoute.annasArchive;
}
