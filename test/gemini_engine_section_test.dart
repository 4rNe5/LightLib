// The engine choice in settings: Gemini's key, model, filters and use.

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/translation/gemini/gemini_api.dart';
import 'package:openlib/services/translation/gemini/gemini_settings.dart';
import 'package:openlib/ui/components/gemini_engine_section.dart';

void main() {
  Widget app() => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('ko'),
        home: Scaffold(
            body: SingleChildScrollView(
                child: GeminiEngineSection(onEngineChanged: () {}))),
      );

  testWidgets('device: only the choice; Gemini: key, model, filters, use',
      (tester) async {
    final settings = GeminiSettings.instance;
    settings.debugSet(useGemini: false, key: '');
    await tester.pumpWidget(app());
    expect(find.text('번역 엔진'), findsOneWidget);
    expect(find.byKey(const ValueKey('geminiKey')), findsNothing);

    settings.debugSet(
        useGemini: true,
        key: 'AIzaTESTKEY1234',
        usage: GeminiUsage(
            day: quotaDay(DateTime.now()),
            requests: 37,
            paragraphs: 3600,
            blockedSafety: 2,
            blockedProhibited: 1,
            dailyLimit: 500,
            freeTier: true));
    await tester.pump();
    expect(find.byKey(const ValueKey('geminiKey')), findsOneWidget);
    expect(find.text('저장된 키 …1234'), findsOneWidget);
    expect(find.byKey(const ValueKey('geminiModel')), findsOneWidget);
    expect(find.text('요청 37 / 500회'), findsOneWidget);
    expect(find.text('무료 등급'), findsOneWidget);
    expect(find.text('필터 막힘 2 · 정책 차단 1'), findsOneWidget);
    for (final h in GeminiHarm.values) {
      expect(find.byKey(ValueKey('geminiSafety-${h.name}')), findsOneWidget);
    }
    expect(find.text('차단 안 함'), findsNWidgets(4));
    expect(find.text('속도 우선'), findsOneWidget);
    expect(find.text('퀄리티 우선'), findsOneWidget);
  });
}
