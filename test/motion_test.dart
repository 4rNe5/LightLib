// What moves, and when: something that is to move right after heavy work
// waits for frames to come on time again; what is on screen while a book
// opens stands still once it has arrived.

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/database.dart';
import 'package:openlib/services/library_organization.dart';
import 'package:openlib/ui/components/book_opening.dart';
import 'package:openlib/ui/components/motion.dart';

void main() {
  group('EvenFrames', () {
    testWidgets('frames on time: after a few of them', (tester) async {
      var even = 0;
      final wait = EvenFrames(onEven: () => even++)..start();
      addTearDown(wait.dispose);
      // The first tick only says when the waiting began; five steps on
      // time after it.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(even, 0, reason: 'frame $i');
      }
      await tester.pump(const Duration(milliseconds: 16));
      expect(even, 1);
      expect(wait.waiting, isFalse);
      // Once only.
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(even, 1);
    });

    testWidgets('a late frame starts the count again', (tester) async {
      var even = 0;
      final wait = EvenFrames(onEven: () => even++)..start();
      addTearDown(wait.dispose);
      await tester.pump(const Duration(milliseconds: 16));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      // (The page under it is still working: a frame came 90 ms late.)
      await tester.pump(const Duration(milliseconds: 90));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(even, 0);
      }
      await tester.pump(const Duration(milliseconds: 16));
      expect(even, 1);
    });

    testWidgets('frames that never come on time: not for ever',
        (tester) async {
      var even = 0;
      final wait = EvenFrames(onEven: () => even++)..start();
      addTearDown(wait.dispose);
      for (var i = 0; i < 7; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(even, 0, reason: '${i * 100} ms');
      }
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(even, 1);
    });

    testWidgets('given up: nothing is called', (tester) async {
      var even = 0;
      final wait = EvenFrames(onEven: () => even++)..start();
      await tester.pump(const Duration(milliseconds: 16));
      wait.dispose();
      await tester.pump(const Duration(seconds: 2));
      expect(even, 0);
    });
  });

  // On a phone the page being loaded works on the thread frames are drawn
  // on: a cover that kept drifting while it waited was a frame to draw
  // all through the loading, and the way into the book stuttered.
  testWidgets('the opening picture stands still once it is up',
      (tester) async {
    final book = LibraryBook(
      book: MyBook(
        id: 'a',
        title: 'A made-up book',
        author: 'Its writer',
        thumbnail: null,
        link: 'https://example.com/a',
        publisher: null,
        info: null,
        format: 'epub',
        description: null,
      ),
      status: ReadingStatus.inProgress,
      fraction: 0.4,
    );
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: BookOpeningView(
          book: book, label: 'Opening at 40%…', progress: book.progress),
    ));
    expect(find.text('A made-up book'), findsWidgets);
    expect(find.text('Opening at 40%…'), findsOneWidget);
    // What comes in (the name rising, the bar filling) ends...
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 16));
    // ...and then no frame is asked for, however long the book takes.
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pump(const Duration(seconds: 5));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });
}
