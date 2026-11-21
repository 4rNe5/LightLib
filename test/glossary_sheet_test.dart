// The reader's glossary sheet: the entries, edited in a dialog.

// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/storage/app_files.dart';
import 'package:openlib/services/storage/idb_app_files.dart';
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

  // (The tests below wait for what the sheet writes, then go on: a write
  // to a real file begun under a widget test's clock never comes back,
  // so they keep the glossaries in memory.)
  void inMemory() {
    final files = AppFiles.instance;
    AppFiles.instance = IdbAppFiles(newIdbFactoryMemory());
    addTearDown(() => AppFiles.instance = files);
    GlossaryService.instance.directory = () async => Directory('/glossaries');
  }

  Widget app(Widget sheet) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('ko'),
        home: Scaffold(body: sheet),
      );
  const witch =
      GlossaryEntry(source: '魔女', target: '푸른마녀', kind: GlossaryKind.person);

  testWidgets('a word set right outside the reader: its paragraphs asked to '
      'be translated again, in this book or in the whole series',
      (tester) async {
    inMemory();
    final service = GlossaryService.instance;
    await tester.runAsync(() => service.save('v2.epub',
        const BookGlossary(complete: true, entries: [witch])));
    final asked = <(List<String>, String)>[];
    await tester.pumpWidget(app(GlossarySheet(
      bookFile: 'v2.epub',
      seriesOf: (_) async => ['v1.epub', 'v3.epub'],
      redoWord: (files, source) async {
        asked.add((files, source));
        return 254;
      },
    )));
    await tester.pumpAndSettle();

    // Nothing asked: the entry is only set right.
    await tester.tap(find.byKey(const ValueKey('glossary-魔女')));
    await tester.pumpAndSettle();
    expect(find.text('안 함'), findsOneWidget);
    expect(find.text('이 책'), findsOneWidget);
    expect(find.text('시리즈 전체'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('glossaryTarget')), '마녀');
    await tester.tap(find.byKey(const ValueKey('glossarySave')));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(find.text('마녀'), findsOneWidget);
    expect(asked, isEmpty);

    // This book.
    await tester.tap(find.byKey(const ValueKey('glossary-魔女')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('이 책'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('glossarySave')));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(asked.single.$1, ['v2.epub']);
    expect(asked.single.$2, '魔女');
    expect(find.text('254문단을 다시 번역합니다'), findsOneWidget);

    // Every volume of its series.
    await tester.tap(find.byKey(const ValueKey('glossary-魔女')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('시리즈 전체'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('glossarySave')));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(asked.last.$1, ['v2.epub', 'v1.epub', 'v3.epub']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a book that is in no series: only "this book" is offered; '
      'nothing to make again is said so', (tester) async {
    inMemory();
    final service = GlossaryService.instance;
    await tester.runAsync(() => service.save('alone.epub',
        const BookGlossary(complete: true, entries: [witch])));
    await tester.pumpWidget(app(GlossarySheet(
      bookFile: 'alone.epub',
      seriesOf: (_) async => const [],
      redoWord: (files, source) async => 0,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('glossary-魔女')));
    await tester.pumpAndSettle();
    expect(find.text('이 책'), findsOneWidget);
    expect(find.text('시리즈 전체'), findsNothing);
    await tester.tap(find.text('이 책'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('glossarySave')));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(find.textContaining('다시 번역할 문단이 없습니다'), findsOneWidget);
  });

  testWidgets('a series\' glossary: what its volumes have between them, a '
      'word set right in every volume that has it, and translated again '
      'in all of them', (tester) async {
    inMemory();
    final service = GlossaryService.instance;
    await tester.runAsync(() async {
      await service.save(
          's1.epub',
          const BookGlossary(complete: true, entries: [
            witch,
            GlossaryEntry(
                source: '大利', target: '다이리', kind: GlossaryKind.person),
          ]));
      await service.save('s2.epub',
          const BookGlossary(complete: true, entries: [witch]));
    });
    final asked = <(List<String>, String)>[];
    await tester.pumpWidget(app(GlossarySheet(
      bookFile: 's1.epub',
      series: const ['s1.epub', 's2.epub'],
      seriesName: '마법 지팡이',
      redoWord: (files, source) async {
        asked.add((files, source));
        return 12;
      },
    )));
    await tester.pumpAndSettle();
    expect(find.text('마법 지팡이 용어집'), findsOneWidget);
    // A word both volumes have shows once.
    expect(find.byKey(const ValueKey('glossary-魔女')), findsOneWidget);
    expect(find.byKey(const ValueKey('glossary-大利')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('glossary-魔女')));
    await tester.pumpAndSettle();
    // Of a series: not "this book".
    expect(find.text('이 책'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('glossaryTarget')), '마녀');
    await tester.tap(find.text('시리즈 전체'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('glossarySave')));
    // (Two volumes written one after the other, then the asking.)
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump(const Duration(milliseconds: 40));
    }
    await tester.pumpAndSettle();
    for (final file in ['s1.epub', 's2.epub']) {
      final e = service
          .cached(file)!
          .entries
          .firstWhere((e) => e.source == '魔女');
      expect(e.target, '마녀', reason: file);
      expect(e.edited, isTrue, reason: file);
    }
    expect(asked.single.$1, ['s1.epub', 's2.epub']);
    expect(asked.single.$2, '魔女');
    expect(tester.takeException(), isNull);
  });
}
