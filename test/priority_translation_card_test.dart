// The book page's "translate this whole book" card.

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/translation/book_translation_service.dart';
import 'package:openlib/ui/components/priority_translation_card.dart';

void main() {
  Widget app(Widget child) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('ko'),
        home: Scaffold(body: child),
      );

  testWidgets('offers the whole-book translation with what it does',
      (tester) async {
    await tester.pumpWidget(
        app(const PriorityTranslationCard(fileName: 'book.epub')));
    expect(find.byKey(const ValueKey('priorityTranslate')), findsOneWidget);
    expect(find.text('이 책 끝까지 번역'), findsOneWidget);
    expect(find.textContaining('끝날 때까지 쉬지 않고'), findsOneWidget);
    expect(find.byKey(const ValueKey('priorityTranslateStop')), findsNothing);
  });

  testWidgets('while it goes first: progress and a stop button, then done',
      (tester) async {
    final service = BookTranslationService.instance;
    addTearDown(() => service.debugShow());
    service.debugShow(priorityFile: 'book.epub');
    await tester.pumpWidget(
        app(const PriorityTranslationCard(fileName: 'book.epub')));
    expect(find.text('이 책 우선 번역 중'), findsOneWidget);
    expect(find.text('준비 중…'), findsOneWidget);
    expect(find.byKey(const ValueKey('priorityTranslateStop')), findsOneWidget);

    service.debugShow(
        priorityFile: 'book.epub',
        progress: const BookTranslationProgress(
            fileName: 'book.epub',
            title: 'Book',
            done: 120,
            total: 480,
            state: BookTranslationState.translating));
    await tester.pump();
    expect(find.text('120/480 문단 · 25%'), findsOneWidget);
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        0.25);

    service.debugShow(
        progress: const BookTranslationProgress(
            fileName: 'book.epub',
            title: 'Book',
            done: 480,
            total: 480,
            state: BookTranslationState.done));
    await tester.pump();
    expect(find.byKey(const ValueKey('priorityTranslateDone')), findsOneWidget);
    expect(find.byKey(const ValueKey('priorityTranslate')), findsNothing);
  });
}
