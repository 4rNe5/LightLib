// The reader's glossary sheet: the entries, edited in a dialog.

// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/translation/book_glossary.dart';
import 'package:openlib/services/translation/glossary_service.dart';
import 'package:openlib/ui/components/glossary_sheet.dart';

void main() {
  testWidgets('lists the entries and saves an edit', (tester) async {
    final dir = Directory.systemTemp.createTempSync('glossary_sheet');
    addTearDown(() => dir.deleteSync(recursive: true));
    final service = GlossaryService.instance..directory = () async => dir;
    await tester.runAsync(() => service.save(
        'book.epub',
        const BookGlossary(complete: true, entries: [
          GlossaryEntry(
              source: '和希',
              reading: 'かずき',
              target: '카즈키',
              kind: GlossaryKind.person,
              gender: GlossaryGender.male),
          GlossaryEntry(source: '脇役', target: '모브', kind: GlossaryKind.term),
        ])));
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('ko'),
      home: const Scaffold(body: GlossarySheet(bookFile: 'book.epub')),
    ));
    expect(find.text('카즈키'), findsOneWidget);
    expect(find.text('모브'), findsOneWidget);
    expect(find.text('남'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('glossary-和希')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('glossaryTarget')), '가즈키');
    await tester.tap(find.byKey(const ValueKey('glossarySave')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(find.text('가즈키'), findsOneWidget);
    expect(service.cached('book.epub')!.entries
        .firstWhere((e) => e.source == '和希').edited, isTrue);
  });
}
