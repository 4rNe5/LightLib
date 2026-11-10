// Web: the reader's page in an iframe of the site itself (same origin).
// Scripts run through the frame's eval; the page posts its messages to
// this window. The book is handed over as a blob: URL.

// Dart imports:
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

// Flutter imports:
import 'package:flutter/widgets.dart';

// Package imports:
import 'package:web/web.dart' as web;

// Project imports:
import 'package:openlib/ui/reader_host/reader_host.dart';
import 'package:openlib/ui/reader_host/reader_resources.dart';

class _FrameHost implements ReaderHostController {
  _FrameHost(this._frame, this._resources);

  final web.HTMLIFrameElement _frame;
  final ReaderResources _resources;
  String? _bookUrl;

  @override
  Future<Object?> evaluate(String code) async {
    final window = _frame.contentWindow;
    if (window == null) return null;
    final result =
        (window as JSObject).callMethod<JSAny?>('eval'.toJS, code.toJS);
    if (result != null && result.isA<JSString>()) {
      return (result as JSString).toDart;
    }
    return null;
  }

  @override
  Future<String> bookUrl() async {
    final known = _bookUrl;
    if (known != null) return known;
    final res = await _resources.resolve(Uri.parse('/book'));
    if (res == null) throw StateError('The book is not in this browser');
    final blob = web.Blob(
        [res.bytes.toJS].toJS, web.BlobPropertyBag(type: res.contentType));
    return _bookUrl = web.URL.createObjectURL(blob);
  }

  void dispose() {
    final url = _bookUrl;
    if (url != null) web.URL.revokeObjectURL(url);
  }
}

Widget readerHostView({
  required ReaderResources resources,
  required void Function(ReaderHostController controller) onCreated,
  required void Function(Map<String, dynamic> message) onMessage,
  required void Function(String message) onPageError,
  required void Function(String description) onLoadError,
}) =>
    _FrameView(
      resources: resources,
      onCreated: onCreated,
      onMessage: onMessage,
    );

class _FrameView extends StatefulWidget {
  const _FrameView({
    required this.resources,
    required this.onCreated,
    required this.onMessage,
  });

  final ReaderResources resources;
  final void Function(ReaderHostController controller) onCreated;
  final void Function(Map<String, dynamic> message) onMessage;

  @override
  State<_FrameView> createState() => _FrameViewState();
}

class _FrameViewState extends State<_FrameView> {
  web.HTMLIFrameElement? _frame;
  _FrameHost? _host;
  JSFunction? _listener;

  @override
  void initState() {
    super.initState();
    _listener = ((web.MessageEvent event) {
      final frame = _frame;
      if (frame == null || event.source == null) return;
      if (!event.source!.strictEquals(frame.contentWindow).toDart) return;
      final data = event.data.dartify();
      if (data is! Map) return;
      final msg = data['lightlibReader'];
      if (msg is Map) widget.onMessage(_stringKeys(msg));
    }).toJS;
    web.window.addEventListener('message', _listener);
  }

  static Map<String, dynamic> _stringKeys(Map map) => {
        for (final MapEntry(:key, :value) in map.entries)
          '$key': value is Map ? _stringKeys(value) : value,
      };

  @override
  void dispose() {
    web.window.removeEventListener('message', _listener);
    _host?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView.fromTagName(
        key: const ValueKey('bookReaderFrame'),
        tagName: 'iframe',
        onElementCreated: (Object element) {
          final frame = element as web.HTMLIFrameElement;
          frame.style
            ..border = '0'
            ..width = '100%'
            ..height = '100%'
            ..backgroundColor = 'transparent';
          frame.src =
              ui_web.assetManager.getAssetUrl('assets/reader/index.html');
          _frame = frame;
          final host = _host = _FrameHost(frame, widget.resources);
          widget.onCreated(host);
        },
      );
}
