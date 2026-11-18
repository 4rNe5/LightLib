// Signing in with Google without leaving the page: Google's own button
// (Google Identity Services) hands the page a token of who signed in, and
// the sync project takes that token. The usual way sends the browser to
// the project's address and back, which a network that does not reach the
// project cannot do (the site built with SYNC_RELAY, tool/cloudflare_build.sh).

// Project imports:
import 'package:openlib/web/google_id_sign_in_stub.dart'
    if (dart.library.js_interop) 'package:openlib/web/google_id_sign_in_web.dart'
    as impl;

/// Google's token of who signed in, and the nonce it was asked with (the
/// project checks the token carries it).
typedef GoogleIdToken = ({String idToken, String nonce});

class GoogleIdSignIn {
  /// Shows Google's button over the page; the token once the owner has
  /// chosen an account, null when it was closed. Throws when Google's
  /// script cannot be loaded.
  static Future<GoogleIdToken?> ask(String clientId) => impl.ask(clientId);
}
