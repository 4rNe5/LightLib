// Devices: the reader's page in a WebView (flutter_inappwebview). Android
// intercepts an https origin, Apple platforms a custom scheme; both are
// served from ReaderResources.

// Dart imports:
import 'dart:typed_data';

// Flutter imports:
import 'package:flutter/widgets.dart';

// Package imports:
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

// Project imports:
import 'package:openlib/ui/reader_host/reader_host.dart';
import 'package:openlib/ui/reader_host/reader_resources.dart';

class _WebViewHost implements ReaderHostController {
  _WebViewHost(this._controller);
  final InAppWebViewController _controller;

  @override
  Future<Object?> evaluate(String code) =>
      _controller.evaluateJavascript(source: code);

  @override
  Future<String> bookUrl() async => '${ReaderResources.origin}/book';
}

Widget readerHostView({
  required ReaderResources resources,
  required void Function(ReaderHostController controller) onCreated,
  required void Function(Map<String, dynamic> message) onMessage,
  required void Function(String message) onPageError,
  required void Function(String description) onLoadError,
}) {
  final settings = InAppWebViewSettings(
    javaScriptEnabled: true,
    transparentBackground: true,
    supportZoom: false,
    builtInZoomControls: false,
    displayZoomControls: false,
    disableHorizontalScroll: false,
    verticalScrollBarEnabled: false,
    horizontalScrollBarEnabled: false,
    overScrollMode: OverScrollMode.NEVER,
    useShouldInterceptRequest: true,
    resourceCustomSchemes: const [ReaderResources.appleScheme],
    allowFileAccess: false,
    allowContentAccess: false,
    mediaPlaybackRequiresUserGesture: true,
    isInspectable: false,
    useHybridComposition: true,
  );
  return InAppWebView(
    key: const ValueKey('bookReaderWebView'),
    initialUrlRequest:
        URLRequest(url: WebUri('${ReaderResources.origin}/index.html')),
    initialSettings: settings,
    onWebViewCreated: (controller) {
      controller.addJavaScriptHandler(
        handlerName: 'reader',
        callback: (args) {
          final msg = args.isEmpty ? null : args.first;
          if (msg is Map) onMessage(Map<String, dynamic>.from(msg));
          return null;
        },
      );
      onCreated(_WebViewHost(controller));
    },
    shouldInterceptRequest: (controller, request) async {
      final uri = request.url;
      if (uri.host != Uri.parse(ReaderResources.androidOrigin).host) {
        return null;
      }
      final res = await resources.resolve(uri);
      if (res == null) {
        return WebResourceResponse(
            statusCode: 404, reasonPhrase: 'Not Found', data: Uint8List(0));
      }
      return WebResourceResponse(
        contentType: res.contentType,
        contentEncoding: 'utf-8',
        data: res.bytes,
        statusCode: 200,
        reasonPhrase: 'OK',
        headers: const {'Cache-Control': 'no-store'},
      );
    },
    onLoadResourceWithCustomScheme: (controller, request) async {
      final res = await resources.resolve(request.url);
      if (res == null) return null;
      return CustomSchemeResponse(
          data: res.bytes, contentType: res.contentType);
    },
    onConsoleMessage: (controller, message) {
      if (message.messageLevel == ConsoleMessageLevel.ERROR) {
        onPageError(message.message);
      }
    },
    onReceivedError: (controller, request, error) {
      if (request.isForMainFrame == true) onLoadError(error.description);
    },
  );
}
