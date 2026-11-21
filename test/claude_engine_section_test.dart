// The engine choice in settings, with Claude: three engines to choose
// from, Claude's key and workspace, its models with their prices, and
// what today's requests cost.

// Dart imports:
import 'dart:convert';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/translation/claude/claude_api.dart';
import 'package:openlib/services/translation/claude/claude_client.dart';
import 'package:openlib/services/translation/claude/claude_settings.dart';
import 'package:openlib/services/translation/gemini/gemini_api.dart';
import 'package:openlib/services/translation/gemini/gemini_settings.dart';
import 'package:openlib/ui/components/claude_engine_section.dart';
import 'package:openlib/ui/components/gemini_engine_section.dart';

class _Refuses implements HttpClientAdapter {
  int asked = 0;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    asked++;
    return ResponseBody.fromString(
        jsonEncode({
          'type': 'error',
          'error': {
            'type': 'invalid_request_error',
            'message': 'anthropic-workspace-id header is required',
          },
        }),
        400,
        headers: {
          'content-type': ['application/json']
        });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  final claude = ClaudeSettings.instance;
  final gemini = GeminiSettings.instance;
  final haiku = claudeModelFor('claude-haiku-5-5');
  final sonnet = claudeModelFor('claude-sonnet-5-5');

  Widget app(Widget child) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('ko'),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  setUp(() {
    gemini.debugSet(useGemini: false, key: '');
    claude.debugSet(
        useClaude: false,
        key: '',
        workspace: '',
        model: sonnet,
        thinking: GeminiThinking.speed,
        usageBy: {});
  });

  testWidgets(
      'three engines; Claude shows its own settings and none of '
      'Gemini\'s', (tester) async {
    // (The choice is saved before translation is told to start over, and
    // a test does not wait for the database: what is checked here is the
    // choice itself.)
    await tester.pumpWidget(app(GeminiEngineSection(onEngineChanged: () {})));
    expect(find.text('기기'), findsOneWidget);
    expect(find.text('Gemini'), findsOneWidget);
    expect(find.text('Claude'), findsOneWidget);
    expect(find.byKey(const ValueKey('claudeKey')), findsNothing);

    await tester.tap(find.text('Claude'));
    await tester.pump();
    expect(claude.useClaude, isTrue);
    expect(gemini.useGemini, isFalse);
    expect(find.byKey(const ValueKey('claudeKey')), findsOneWidget);
    expect(find.byKey(const ValueKey('claudeWorkspace')), findsOneWidget);
    expect(find.byKey(const ValueKey('claudeModel')), findsOneWidget);
    expect(find.byKey(const ValueKey('geminiKey')), findsNothing);
    expect(find.byKey(const ValueKey('geminiSafety-sexual')), findsNothing);
    // No key yet: nothing used to show.
    expect(find.byKey(const ValueKey('claudeUsage')), findsNothing);

    await tester.tap(find.text('Gemini'));
    await tester.pump();
    expect(claude.useClaude, isFalse);
    expect(gemini.useGemini, isTrue);
    expect(find.byKey(const ValueKey('claudeKey')), findsNothing);
    expect(find.byKey(const ValueKey('geminiKey')), findsOneWidget);

    await tester.tap(find.text('기기'));
    await tester.pump();
    expect(claude.useClaude, isFalse);
    expect(gemini.useGemini, isFalse);
    expect(find.byKey(const ValueKey('geminiKey')), findsNothing);
  });

  testWidgets('today\'s cost is the chosen model\'s; the others\' beside it',
      (tester) async {
    final day = quotaDay(DateTime.now());
    claude.debugSet(useClaude: true, key: 'sk-ant-test-key-4321', usageBy: {
      sonnet.id: GeminiUsage(
          day: day,
          requests: 12,
          promptTokens: 500000,
          outputTokens: 100000,
          paragraphs: 960),
      haiku.id: GeminiUsage(
          day: day, requests: 3, promptTokens: 1000000, outputTokens: 200000),
    });
    await tester.pumpWidget(app(ClaudeEngineBody(onEngineChanged: () {})));
    expect(find.text('저장된 키 …4321'), findsOneWidget);
    expect(find.text('오늘 사용량 · Claude Sonnet 5.5'), findsOneWidget);
    expect(find.text('요청 12회'), findsOneWidget);
    expect(find.text('번역 문단 960'), findsOneWidget);
    // 0.5M in at $2 and 0.1M out at $10.
    expect(find.text('오늘 요금 약 \$2.00'), findsOneWidget);
    expect(find.text('100만 토큰당 입력 \$2.00 / 출력 \$10.00'), findsOneWidget);
    expect(find.text('Claude Haiku 5.5: 오늘 요청 3회, 약 \$0.200'), findsOneWidget);

    // (As the picker does, without the database.)
    claude.debugSet(model: haiku);
    await tester.pump();
    expect(find.text('오늘 사용량 · Claude Haiku 5.5'), findsOneWidget);
    expect(find.text('요청 3회'), findsOneWidget);
    expect(find.text('오늘 요금 약 \$0.200'), findsOneWidget);
    expect(find.text('100만 토큰당 입력 \$0.10 / 출력 \$0.50'), findsOneWidget);
    expect(find.text('Claude Sonnet 5.5: 오늘 요청 12회, 약 \$2.00'), findsOneWidget);
  });

  testWidgets('no credit left is said in the card', (tester) async {
    claude.debugSet(useClaude: true, key: 'sk-ant-test-key-4321');
    claude.recordLimit(
        const GeminiError(GeminiErrorKind.quotaExhausted, 'no credit'));
    await tester.pumpWidget(app(ClaudeEngineBody(onEngineChanged: () {})));
    expect(find.byKey(const ValueKey('claudeExhausted')), findsOneWidget);
  });

  testWidgets('a key the API refuses is not kept, and its reason is shown',
      (tester) async {
    claude.debugSet(useClaude: true, key: '');
    final api = _Refuses();
    await tester.pumpWidget(app(ClaudeEngineBody(
        onEngineChanged: () {},
        client: ClaudeClient(
            dio: Dio()..httpClientAdapter = api,
            settings: claude,
            sleep: (_) async {}))));
    await tester.enterText(
        find.byKey(const ValueKey('claudeKey')), 'sk-ant-not-in-a-workspace');
    await tester.runAsync(
        () => tester.tap(find.byKey(const ValueKey('claudeTest'))));
    // The answer comes in real time: waited for as long as it takes (a
    // fixed 50 ms was too short when the whole suite runs at once).
    final status = find.byKey(const ValueKey('claudeTestStatus'));
    for (var i = 0; i < 100 && status.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(api.asked, 1);
    expect(claude.hasKey, isFalse);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('claudeTestStatus')))
            .data,
        '키를 쓸 수 없습니다: anthropic-workspace-id header is required');
  });
}
