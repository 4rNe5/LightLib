// Signing in to Z-Library in the app's browser, for when signing in with
// an email and password from the settings does not go through (a
// captcha, another way of signing in): the page is the mirror's own, and
// once it has set the session's cookies the page closes with them.

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/zlibrary_account.dart';

/// The session in the browser's cookies for [url], if it is signed in.
Future<ZlibrarySession?> zlibraryBrowserSession(WebUri url) async {
  try {
    final cookies = await CookieManager.instance().getCookies(url: url);
    return ZlibrarySession.fromCookies(
        {for (final c in cookies) c.name: '${c.value}'});
  } catch (_) {
    return null;
  }
}

/// Signs the browser out of [mirrors] too, so a later sign-in there
/// starts from the form instead of the old session.
Future<void> zlibraryBrowserSignOut(List<String> mirrors) async {
  for (final mirror in mirrors) {
    for (final name in const [
      ZlibrarySession.idCookie,
      ZlibrarySession.keyCookie
    ]) {
      try {
        await CookieManager.instance()
            .deleteCookie(url: WebUri(mirror), name: name);
      } catch (_) {}
    }
  }
}

class ZlibraryLoginPage extends StatefulWidget {
  const ZlibraryLoginPage({super.key, required this.mirror});

  /// The mirror to sign in on (`https://host`).
  final String mirror;

  @override
  State<ZlibraryLoginPage> createState() => _ZlibraryLoginPageState();
}

class _ZlibraryLoginPageState extends State<ZlibraryLoginPage> {
  bool _done = false;
  double _progress = 0;

  Future<void> _check(WebUri? url) async {
    if (_done || url == null) return;
    final session = await zlibraryBrowserSession(url);
    if (session == null || _done || !mounted) return;
    _done = true;
    Navigator.of(context).pop(session);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.zlibAccountTitle),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(26),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(l10n.zlibBrowserHint,
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            ),
            if (_progress < 1)
              LinearProgressIndicator(value: _progress, minHeight: 2)
            else
              const SizedBox(height: 2),
          ]),
        ),
      ),
      body: SafeArea(
        child: InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri('${widget.mirror}/login')),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            thirdPartyCookiesEnabled: true,
          ),
          onProgressChanged: (_, p) => setState(() => _progress = p / 100),
          onLoadStop: (_, url) => _check(url),
          onUpdateVisitedHistory: (_, url, __) => _check(url),
        ),
      ),
    );
  }
}
