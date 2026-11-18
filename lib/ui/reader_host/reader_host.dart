// The page the reader draws the book in: a WebView on devices
// (flutter_inappwebview), an iframe of the site itself on the web. The
// reader talks to both the same way - scripts in, messages out.

// Flutter imports:
import 'package:flutter/widgets.dart';

// Project imports:
import 'package:openlib/ui/reader_host/reader_host_io.dart'
    if (dart.library.js_interop) 'package:openlib/ui/reader_host/reader_host_web.dart'
    as impl;
import 'package:openlib/ui/reader_host/reader_resources.dart';

abstract class ReaderHostController {
  /// Runs [code] in the page; what it returns (strings come back as
  /// strings), or null.
  Future<Object?> evaluate(String code);

  /// Where the page fetches the book from.
  Future<String> bookUrl();
}

/// The page, made once per reader.
Widget readerHostView({
  required ReaderResources resources,
  required void Function(ReaderHostController controller) onCreated,
  required void Function(Map<String, dynamic> message) onMessage,
  required void Function(String message) onPageError,
  required void Function(String description) onLoadError,
}) =>
    impl.readerHostView(
      resources: resources,
      onCreated: onCreated,
      onMessage: onMessage,
      onPageError: onPageError,
      onLoadError: onLoadError,
    );
