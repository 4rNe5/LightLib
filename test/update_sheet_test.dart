// The update sheet: download with progress, then install; a build
// already downloaded opens on "Install now"; "Later" snoozes.

// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/ui/components/update_sheet.dart';

Widget _host(UpdateSheet sheet) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(body: sheet),
    );

void main() {
  testWidgets('downloads with progress, then installs', (tester) async {
    final progress = Completer<UpdateProgress>();
    final done = Completer<String?>();
    final installed = <String>[];
    await tester.pumpWidget(_host(UpdateSheet(
      label: '1.7.2 (build 36)',
      currentLabel: '1.7.2 (build 35)',
      changes: '### 1.7.2 (build 36)\n- fix: something',
      pageUrl: 'https://github.com/4rNe5/LightLib/releases',
      sizeBytes: 140 * 1024 * 1024,
      download: (onProgress, cancel) {
        progress.complete(onProgress);
        return done.future;
      },
      install: (path) async {
        installed.add(path);
        return true;
      },
      onLater: () async {},
    )));
    expect(find.text('A new version is out'), findsOneWidget);
    expect(find.text('1.7.2 (build 35)'), findsOneWidget);
    expect(find.text('1.7.2 (build 36)'), findsWidgets);
    expect(find.text('fix: something'), findsOneWidget);
    expect(find.text('Download and install · 140.0 MB'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('updatePrimary')));
    await tester.pump();
    (await progress.future)(0.5, 70, 140);
    await tester.pump();
    expect(find.text('50%'), findsOneWidget);

    done.complete('/tmp/LightLib-36.apk');
    await tester.pumpAndSettle();
    expect(installed, ['/tmp/LightLib-36.apk']);
    expect(find.text('Update ready to install'), findsOneWidget);
    expect(find.text('Install now'), findsOneWidget);
  });

  testWidgets('a downloaded build installs right away; Later snoozes',
      (tester) async {
    var snoozed = false;
    final installed = <String>[];
    await tester.pumpWidget(_host(UpdateSheet(
      label: 'b',
      currentLabel: 'a',
      changes: '',
      pageUrl: 'https://example.com',
      preparedPath: '/tmp/ready.apk',
      download: (_, __) async => throw StateError('no download'),
      install: (path) async {
        installed.add(path);
        return true;
      },
      onLater: () async => snoozed = true,
    )));
    expect(find.text('Update ready to install'), findsOneWidget);
    expect(find.text('No change notes for this build.'), findsOneWidget);
    await tester.tap(find.text('Install now'));
    await tester.pumpAndSettle();
    expect(installed, ['/tmp/ready.apk']);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(snoozed, isTrue);
  });

  testWidgets('a failed download offers a retry', (tester) async {
    await tester.pumpWidget(_host(UpdateSheet(
      label: 'b',
      currentLabel: 'a',
      changes: '- x',
      pageUrl: 'https://example.com',
      download: (_, __) async => throw StateError('offline'),
      install: (_) async => true,
      onLater: () async {},
    )));
    await tester.tap(find.byKey(const ValueKey('updatePrimary')));
    await tester.pumpAndSettle();
    expect(find.text('The update could not be downloaded.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
