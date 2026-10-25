// Reads a page the way a browser does: in an invisible WebView, which runs
// the page's scripts - and so clears bot checks such as AWS WAF's (a 202
// with an empty body to a plain HTTP client) - and hands back the HTML
// once the content is there.

// Dart imports:
import 'dart:async';

// Package imports:
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

// Project imports:
import 'package:openlib/services/logger.dart';
import 'package:openlib/services/platform_utils.dart';

final AppLogger _logger = AppLogger();

/// One page at a time: each WebView holds a renderer's memory.
Future<void> _queue = Future.value();

/// The HTML of [url] once the JavaScript expression [readyJs] is true in
/// it, or null after [timeout] or where there is no WebView.
Future<String?> readPageInBrowser(String url,
    {required String readyJs,
    Duration timeout = const Duration(seconds: 25)}) {
  if (!PlatformUtils.isMobile) return Future.value();
  final done = Completer<String?>();
  _queue = _queue.then((_) async {
    done.complete(await _read(url, readyJs, timeout));
  }).catchError((Object e) {
    if (!done.isCompleted) done.complete(null);
  });
  return done.future;
}

Future<String?> _read(String url, String readyJs, Duration timeout) async {
  final watch = Stopwatch()..start();
  final created = Completer<InAppWebViewController>();
  final headless = HeadlessInAppWebView(
    initialUrlRequest: URLRequest(url: WebUri(url)),
    initialSettings: InAppWebViewSettings(
      javaScriptEnabled: true,
      // Pictures are not needed to read the page.
      blockNetworkImage: true,
    ),
    onWebViewCreated: (controller) {
      if (!created.isCompleted) created.complete(controller);
    },
  );
  try {
    await headless.run();
    final controller = await created.future.timeout(timeout);
    while (watch.elapsed < timeout) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final ready = await controller
          .evaluateJavascript(source: '!!($readyJs)')
          .catchError((_) => null);
      if (ready == true) {
        final html = await controller.evaluateJavascript(
            source: 'document.documentElement.outerHTML');
        _logger.info('Page read in the browser',
            tag: 'BrowserPage',
            metadata: {'url': url, 'ms': watch.elapsedMilliseconds});
        return html is String ? html : null;
      }
    }
    _logger.warning('Page not ready in the browser',
        tag: 'BrowserPage',
        metadata: {
          'url': url,
          'ms': watch.elapsedMilliseconds,
          'title': await controller.getTitle().catchError((_) => null),
        });
    return null;
  } catch (e) {
    _logger.warning('Browser page read failed',
        tag: 'BrowserPage', metadata: {'url': url, 'error': e.toString()});
    return null;
  } finally {
    await headless.dispose().catchError((_) {});
  }
}
