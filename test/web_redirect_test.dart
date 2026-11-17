// Where the browser returns after Google sign-in on the web: the app's
// own address, also on a host that serves it under a path.

// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/services/sync/sync_service.dart';

void main() {
  String at(String page) => SyncConfig.webRedirect(Uri.parse(page));

  test('at a host\'s root: the origin, as the project lists it', () {
    expect(at('https://lightlib-4rne5.vercel.app/'),
        'https://lightlib-4rne5.vercel.app');
    expect(at('https://lightlib-4rne5.vercel.app'),
        'https://lightlib-4rne5.vercel.app');
    expect(at('https://lightlib-4rne5.vercel.app/#/settings'),
        'https://lightlib-4rne5.vercel.app');
    expect(at('https://lightlib-4rne5.vercel.app/index.html'),
        'https://lightlib-4rne5.vercel.app');
    expect(at('http://localhost:8094/?code=abc'), 'http://localhost:8094');
  });

  test('under a path: that path', () {
    const pages = 'https://4rne5.github.io/LightLib/';
    expect(at('https://4rne5.github.io/LightLib/'), pages);
    expect(at('https://4rne5.github.io/LightLib/#/'), pages);
    expect(at('https://4rne5.github.io/LightLib/index.html'), pages);
    expect(at('https://4rne5.github.io/LightLib/?code=abc&state=x'), pages);
  });
}
