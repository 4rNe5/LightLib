// Settings: the Z-Library account sheet - signing in (a refusal's reason,
// no answer, the browser instead), who is signed in and today's downloads,
// a session the mirror no longer knows.

// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/zlibrary_account.dart';
import 'package:openlib/ui/components/zlibrary_account_sheet.dart';

void main() {
  late Directory dir;
  late ZlibraryAccount account;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('zlib_sheet');
    account = ZlibraryAccount()..path = () async => '${dir.path}/session';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Widget sheet({
    ZlibSignIn? signIn,
    ZlibLimits? limits,
    Future<ZlibrarySession?> Function(BuildContext)? browser,
  }) =>
      MaterialApp(
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ZlibraryAccountSheet(
            account: account,
            signIn: signIn,
            limits: limits ??
                () async => (
                      limits: const ZlibraryLimits(today: 4, limit: 50),
                      signedOut: false
                    ),
            browserSignIn: browser,
            browserSignOut: () async {},
          ),
        ),
      );

  testWidgets('a wrong password shows the reason; the right one signs in',
      (tester) async {
    account.debugSet(null);
    final asked = <(String, String)>[];
    await tester.pumpWidget(sheet(signIn: (email, password) async {
      asked.add((email, password));
      if (password != 'right') {
        return (session: null, error: 'Incorrect email or password');
      }
      const s = ZlibrarySession(
          userId: '1', userKey: 'k', email: 'reader@example.com');
      account.debugSet(s);
      return (session: s, error: null);
    }));
    await tester.pump();
    expect(find.text('로그인'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('zlibEmail')), 'reader@example.com');
    await tester.enterText(find.byKey(const ValueKey('zlibPassword')), 'no');
    await tester.tap(find.byKey(const ValueKey('zlibSignIn')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Incorrect email or password'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('zlibPassword')), 'right');
    await tester.tap(find.byKey(const ValueKey('zlibSignIn')));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(asked.last, ('reader@example.com', 'right'));
    expect(find.text('reader@example.com'), findsOneWidget);
    expect(find.text('오늘 4 / 50권 받음'), findsOneWidget);
    expect(find.byKey(const ValueKey('zlibPassword')), findsNothing);
  });

  testWidgets('no answer: says so, and the browser is a tap away',
      (tester) async {
    account.debugSet(null);
    await tester.pumpWidget(sheet(
      signIn: (_, __) async => (session: null, error: null),
      browser: (_) async =>
          const ZlibrarySession(userId: '9', userKey: 'browser'),
    ));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('zlibEmail')), 'a@b.c');
    await tester.enterText(find.byKey(const ValueKey('zlibPassword')), 'x');
    await tester.tap(find.byKey(const ValueKey('zlibSignIn')));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('로그인하지 못했습니다'), findsOneWidget);
    // debugSet stands in for the file write a test cannot wait for.
    account.debugSet(const ZlibrarySession(userId: '9', userKey: 'browser'));
    await tester.pump();
    expect(find.byKey(const ValueKey('zlibSignedIn')), findsOneWidget);
  });

  testWidgets('signed in: a session the mirror forgot, and signing out',
      (tester) async {
    account.debugSet(const ZlibrarySession(
        userId: '1', userKey: 'k', email: 'reader@example.com'));
    await tester
        .pumpWidget(sheet(limits: () async => (limits: null, signedOut: true)));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('zlibExpired')), findsOneWidget);
    expect(find.byKey(const ValueKey('zlibSignOut')), findsOneWidget);
  });
}
