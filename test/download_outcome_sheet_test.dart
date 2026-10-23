// The sheet that follows "Add to my library": started (with the fast
// badge) and not started (with the reason), in a narrow phone width.

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/ui/components/download_outcome_sheet.dart';

void main() {
  Future<void> open(WidgetTester tester, {required bool success}) async {
    tester.view.physicalSize = const Size(1080, 2000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ko'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showDownloadOutcomeSheet(
                context,
                success: success,
                title: success ? '다운로드를 시작했어요' : '다운로드를 시작하지 못했어요',
                bookTitle: '迷子になっていた幼女を助けたら、お隣に住む美少女留学生が家に遊びに来るようになった件について',
                message: success ? '완료되면 내 서재에 추가돼요.' : '오늘의 다운로드 한도에 도달했습니다.',
                badge: success ? '빠른 다운로드' : null,
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  testWidgets('started: title, book, badge, OK closes it', (tester) async {
    await open(tester, success: true);
    expect(find.byKey(const ValueKey('downloadStartedSheet')), findsOneWidget);
    expect(find.text('빠른 다운로드'), findsOneWidget);
    expect(find.text('확인'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('downloadOutcomeOk')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('downloadStartedSheet')), findsNothing);
  });

  testWidgets('not started: the reason and a close button', (tester) async {
    await open(tester, success: false);
    expect(find.byKey(const ValueKey('downloadFailedSheet')), findsOneWidget);
    expect(find.text('오늘의 다운로드 한도에 도달했습니다.'), findsOneWidget);
    expect(find.text('닫기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
