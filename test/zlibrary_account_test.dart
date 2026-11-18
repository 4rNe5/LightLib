// The reader's Z-Library account: the session read from what the mirrors
// answer and kept on the device (never the password), book pages and
// download links asked for as the account, searches and signing in not,
// and the account's limits. (The settings sheet has a file of its own: a
// widget test's binding answers every real HTTP request with 400.)

// Dart imports:
import 'dart:convert';
import 'dart:io';

// Package imports:
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/services/search_manager.dart';
import 'package:openlib/services/zlibrary_account.dart';

class _Seen {
  _Seen(this.method, this.path, this.cookie, this.body);
  final String method;
  final String path;
  final String? cookie;
  final String body;
}

void main() {
  late Directory dir;
  late ZlibraryAccount account;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('zlib_account');
    account = ZlibraryAccount()..path = () async => '${dir.path}/session';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('a session from a sign-in answer, a profile, cookies, the file', () {
    final signedIn = ZlibrarySession.fromApi({
      'success': 1,
      'user': {
        'id': 4821,
        'email': 'reader@example.com',
        'name': 'Reader',
        'remix_userkey': 'abc123',
      },
    })!;
    expect(signedIn.userId, '4821');
    expect(
        signedIn.cookies, {'remix_userid': '4821', 'remix_userkey': 'abc123'});
    expect(signedIn.label, 'Reader');
    expect(
        ZlibrarySession.fromJson(jsonDecode(jsonEncode(signedIn.toJson())))!
            .userKey,
        'abc123');
    // A refusal, or an answer without the key, is no session.
    expect(ZlibrarySession.fromApi({'success': 0, 'error': 'x'}), isNull);
    expect(
        ZlibrarySession.fromApi({
          'user': {'id': 1}
        }),
        isNull);
    // The profile has no key: the session's own stays.
    final named = ZlibrarySession.fromApi({
      'user': {'id': 4821, 'email': 'new@example.com'}
    }, fallback: const ZlibrarySession(userId: '4821', userKey: 'abc123'))!;
    expect((named.userKey, named.email), ('abc123', 'new@example.com'));

    expect(
        ZlibrarySession.fromCookies(
                {'remix_userid': '7', 'remix_userkey': 'k', 'other': 'x'})!
            .label,
        '#7');
    expect(ZlibrarySession.fromCookies({'remix_userid': '7'}), isNull);
    expect(parseCookieHeader('a=1; remix_userid=7;b=x=y'),
        {'a': '1', 'remix_userid': '7', 'b': 'x=y'});

    final limits = ZlibraryLimits.fromApi({
      'user': {'downloads_today': '3', 'downloads_limit': 999}
    })!;
    expect((limits.today, limits.limit, limits.left), (3, 999, 996));
    expect(ZlibraryLimits.fromApi({'user': {}}), isNull);
  });

  test('the session is kept across starts and gone after signing out',
      () async {
    await account.signIn(const ZlibrarySession(
        userId: '7', userKey: 'k', email: 'reader@example.com'));
    final again = ZlibraryAccount()..path = () async => '${dir.path}/session';
    await again.load();
    expect(again.session!.userKey, 'k');
    expect(again.signedIn, isTrue);
    await again.signOut();
    expect(File('${dir.path}/session').existsSync(), isFalse);
    final after = ZlibraryAccount()..path = () async => '${dir.path}/session';
    await after.load();
    expect(after.signedIn, isFalse);
  });

  group('against a mirror (local server)', () {
    late HttpServer server;
    late String base;
    final seen = <_Seen>[];
    var profile = <String, Object?>{
      'success': 1,
      'user': {
        'id': 4821,
        'email': 'reader@example.com',
        'name': 'Reader',
        'downloads_today': 4,
        'downloads_limit': 50,
      },
    };
    final limiter =
        File('test/fixtures/zlib_daily_limit.html').readAsStringSync();
    final bookPage =
        File('test/fixtures/zlib_book_page.html').readAsStringSync();

    setUp(() async {
      seen.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = 'http://127.0.0.1:${server.port}';
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        final path = request.uri.path;
        seen.add(
            _Seen(request.method, path, request.headers.value('cookie'), body));
        final response = request.response;
        if (path == '/eapi/user/login') {
          final form = Uri.splitQueryString(body);
          response.headers.contentType = ContentType.json;
          response.write(jsonEncode(form['password'] == 'right'
              ? {
                  'success': 1,
                  'user': {
                    'id': 4821,
                    'email': form['email'],
                    'name': 'Reader',
                    'remix_userkey': 'abc123',
                  },
                }
              : {'success': 0, 'error': 'Incorrect email or password'}));
        } else if (path == '/eapi/user/profile') {
          response.headers.contentType = ContentType.json;
          response.write(jsonEncode(profile));
        } else if (path.startsWith('/dl/')) {
          response.headers.contentType = ContentType.html;
          response.write(limiter);
        } else {
          response.headers.contentType = ContentType.html;
          response.write(bookPage);
        }
        await response.close();
      });
    });
    tearDown(() => server.close(force: true));

    ZlibraryProvider provider() =>
        ZlibraryProvider(mirrors: [base], account: account);

    test('signing in keeps the session, not the password', () async {
      final result = await provider().signIn(' reader@example.com ', 'right');
      expect(result.session!.userKey, 'abc123');
      expect(result.error, isNull);
      expect(account.session!.email, 'reader@example.com');
      final login = seen.single;
      expect(login.method, 'POST');
      expect(Uri.splitQueryString(login.body),
          {'email': 'reader@example.com', 'password': 'right'});
      final kept = File('${dir.path}/session').readAsStringSync();
      expect(kept, contains('abc123'));
      expect(kept, isNot(contains('right')));
    });

    test('a refusal is told in the mirror\'s words; nothing is kept', () async {
      final result = await provider().signIn('reader@example.com', 'wrong');
      expect(result.session, isNull);
      expect(result.error, 'Incorrect email or password');
      expect(account.signedIn, isFalse);
      expect(File('${dir.path}/session').existsSync(), isFalse);
    });

    test('no mirror answering: no session, no error to show', () async {
      final down =
          ZlibraryProvider(mirrors: ['http://127.0.0.1:1'], account: account);
      final result = await down.signIn('reader@example.com', 'right');
      expect((result.session, result.error), (null, null));
    });

    test(
        'book pages and download links go as the account; search and '
        'signing in do not', () async {
      await account
          .signIn(const ZlibrarySession(userId: '4821', userKey: 'abc123'));
      final p = provider();
      await p.resolveBookDownload('$base/book/x/y.html');
      final pages = seen.where((s) => s.path.startsWith('/book/'));
      final links = seen.where((s) => s.path.startsWith('/dl/'));
      expect(pages, isNotEmpty);
      expect(links, isNotEmpty);
      for (final s in [...pages, ...links]) {
        expect(parseCookieHeader(s.cookie),
            {'remix_userid': '4821', 'remix_userkey': 'abc123'},
            reason: s.path);
      }
      seen.clear();
      await p.search(const SearchQuery(text: 'docker'));
      expect(seen, isNotEmpty);
      expect(seen.every((s) => s.cookie == null), isTrue);
      seen.clear();
      await p.signIn('reader@example.com', 'right');
      expect(seen.single.cookie, isNull);
    });

    test('the account\'s cookies sit beside a solved challenge\'s', () async {
      await account
          .signIn(const ZlibrarySession(userId: '4821', userKey: 'abc123'));
      final dio = Dio();
      ZlibraryProvider(dio: dio, mirrors: [base], account: account);
      await dio.get('$base/dl/1',
          options: Options(headers: {'Cookie': 'dw=solved'}));
      expect(parseCookieHeader(seen.single.cookie), {
        'dw': 'solved',
        'remix_userid': '4821',
        'remix_userkey': 'abc123',
      });
    });

    test('signed out, nothing is added', () async {
      await provider().resolveBookDownload('$base/book/x/y.html');
      expect(seen.every((s) => s.cookie == null), isTrue);
    });

    test('the limit page reads as the account\'s limit once signed in',
        () async {
      final anonymous =
          await provider().resolveBookDownload('$base/book/x/y.html');
      expect(anonymous.refusal, contains('Sign in to your Z-Library account'));
      await account
          .signIn(const ZlibrarySession(userId: '4821', userKey: 'abc123'));
      final signedIn =
          await provider().resolveBookDownload('$base/book/x/y.html');
      expect(signedIn.refusal, contains('your Z-Library account reached'));
    });

    test('limits from the profile; a session the mirror forgot', () async {
      expect((await provider().accountLimits()).limits, isNull);
      expect(seen, isEmpty); // signed out: nothing asked

      await account
          .signIn(const ZlibrarySession(userId: '4821', userKey: 'abc123'));
      final ok = await provider().accountLimits();
      expect(
          (ok.limits!.today, ok.limits!.limit, ok.signedOut), (4, 50, false));
      expect(parseCookieHeader(seen.last.cookie)['remix_userkey'], 'abc123');
      // The profile named the account.
      expect(account.session!.label, 'Reader');
      expect(account.session!.userKey, 'abc123');

      profile = {'success': 0, 'error': 'Please login'};
      final gone = await provider().accountLimits();
      expect((gone.limits, gone.signedOut), (null, true));
    });
  });
}
