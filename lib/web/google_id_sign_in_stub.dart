// Not in a browser: there is no Google button to show.

// Project imports:
import 'package:openlib/web/google_id_sign_in.dart';

Future<GoogleIdToken?> ask(String clientId) async =>
    throw UnsupportedError('Google\'s button is the web\'s');
