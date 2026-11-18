// In the browser: Google's script, its button in a layer over the app
// (plain page elements above the canvas - the button is Google's own
// frame, which takes its clicks itself).

// Dart imports:
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';

// Package imports:
import 'package:crypto/crypto.dart';
import 'package:web/web.dart' as web;

// Project imports:
import 'package:openlib/web/google_id_sign_in.dart';

const _script = 'https://accounts.google.com/gsi/client';
const overlayId = 'lightlib-google-sign-in';

@JS('google.accounts.id.initialize')
external void _initialize(JSObject config);

@JS('google.accounts.id.renderButton')
external void _renderButton(web.HTMLElement parent, JSObject options);

Future<void>? _loading;

Future<void> _load() => _loading ??= () {
      final done = Completer<void>();
      final script = web.HTMLScriptElement()
        ..src = _script
        ..async = true;
      script.addEventListener('load', ((web.Event _) => done.complete()).toJS);
      script.addEventListener(
          'error',
          ((web.Event _) {
            // Asked for again at the next try.
            _loading = null;
            script.remove();
            done.completeError(
                StateError('Google sign-in could not be loaded'));
          }).toJS);
      web.document.head!.append(script);
      return done.future;
    }();

/// A value Google puts in the token, new each time: it gets the hash, the
/// project the value itself.
String _newNonce() {
  final random = Random.secure();
  return base64Url
      .encode(List.generate(32, (_) => random.nextInt(256)))
      .replaceAll('=', '');
}

Future<GoogleIdToken?> ask(String clientId) async {
  await _load();
  web.document.getElementById(overlayId)?.remove();
  final nonce = _newNonce();
  final result = Completer<GoogleIdToken?>();

  final overlay = web.HTMLDivElement()
    ..id = overlayId
    ..style.cssText = 'position:fixed;inset:0;z-index:2147483000;display:flex;'
        'align-items:center;justify-content:center;background:rgba(0,0,0,.5)';
  final card = web.HTMLDivElement()
    ..style.cssText = 'position:relative;background:#fff;border-radius:18px;'
        'padding:44px 28px 30px;min-width:264px;min-height:44px;display:flex;'
        'justify-content:center;box-shadow:0 18px 50px rgba(0,0,0,.3)';
  final close = web.HTMLButtonElement()
    ..type = 'button'
    ..textContent = '×'
    ..ariaLabel = 'Close'
    ..style.cssText = 'position:absolute;top:4px;right:8px;border:0;'
        'background:none;font-size:24px;line-height:1;padding:8px;'
        'cursor:pointer;color:#555';
  final button = web.HTMLDivElement();
  card
    ..append(close)
    ..append(button);
  overlay.append(card);

  late final JSFunction onKey;
  void finish(GoogleIdToken? token) {
    if (result.isCompleted) return;
    web.document.removeEventListener('keydown', onKey, true.toJS);
    overlay.remove();
    result.complete(token);
  }

  onKey = ((web.KeyboardEvent e) {
    if (e.key == 'Escape') {
      e.stopPropagation();
      finish(null);
    }
  }).toJS;
  web.document.addEventListener('keydown', onKey, true.toJS);
  close.addEventListener('click', ((web.Event _) => finish(null)).toJS);
  overlay.addEventListener(
      'click',
      ((web.Event e) {
        if (e.target == overlay) finish(null);
      }).toJS);

  _initialize(JSObject()
    ..['client_id'] = clientId.toJS
    ..['nonce'] = sha256.convert(utf8.encode(nonce)).toString().toJS
    ..['ux_mode'] = 'popup'.toJS
    ..['auto_select'] = false.toJS
    ..['itp_support'] = true.toJS
    ..['callback'] = ((JSObject response) {
      final credential = response['credential'];
      finish(credential.isA<JSString>()
          ? (idToken: (credential as JSString).toDart, nonce: nonce)
          : null);
    }).toJS);
  web.document.body!.append(overlay);
  _renderButton(
      button,
      JSObject()
        ..['type'] = 'standard'.toJS
        ..['theme'] = 'outline'.toJS
        ..['size'] = 'large'.toJS
        ..['shape'] = 'pill'.toJS
        ..['text'] = 'continue_with'.toJS
        ..['width'] = 264.toJS);
  return result.future;
}
