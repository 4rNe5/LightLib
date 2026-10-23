// The translation scheduler: priority order, a library book stepping
// aside for the reader, rests after look-ahead work, and the pause while
// the user scrolls.

// Dart imports:
import 'dart:async';

// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/services/translation/translation_scheduler.dart';

void main() {
  TranslationScheduler<String> scheduler({void Function()? onYield}) =>
      TranslationScheduler<String>(
        onYield: onYield,
        interactionQuiet: const Duration(milliseconds: 150),
        maxVisibleHold: const Duration(milliseconds: 400),
        tick: const Duration(milliseconds: 5),
      );

  test('runs on-screen work first and stops a library book for it', () async {
    final started = <String>[];
    var yields = 0;
    final s = scheduler(onYield: () => yields++);
    final gate = Completer<void>();
    var bookRuns = 0;

    final book = s.submit((token) async {
      started.add('book');
      bookRuns++;
      if (bookRuns == 1) await gate.future;
      token.check();
      return 'book';
    }, TranslationPriority.background);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(s.running, TranslationPriority.background);

    Future<String> job(String name, TranslationPriority p) =>
        s.submit((token) async {
          started.add(name);
          return name;
        }, p);
    final later = job('book2', TranslationPriority.background);
    final ahead = job('ahead', TranslationPriority.ahead);
    final visible = job('visible', TranslationPriority.visible);
    // The book's generation is asked to stop as soon as the reader asks.
    expect(yields, 1);
    gate.complete();

    expect(await visible, 'visible');
    expect(await ahead, 'ahead');
    expect(await book, 'book');
    expect(await later, 'book2');
    // The stopped book paragraph ran again, after the reader's work.
    expect(started, ['book', 'visible', 'ahead', 'book', 'book2']);
  });

  test('rests after look-ahead work, never before on-screen work', () async {
    final s = scheduler();
    final times = <String, DateTime>{};
    Future<String> job(String name, TranslationPriority p, int ms) =>
        s.submit((token) async {
          times['$name-start'] = DateTime.now();
          await Future<void>.delayed(Duration(milliseconds: ms));
          times['$name-end'] = DateTime.now();
          return name;
        }, p);

    await job('a1', TranslationPriority.ahead, 200);
    final a2 = job('a2', TranslationPriority.ahead, 10);
    await a2;
    final gap = times['a2-start']!.difference(times['a1-end']!);
    // Half as long as the 200 ms request took.
    expect(gap.inMilliseconds, greaterThanOrEqualTo(90));

    await job('a3', TranslationPriority.ahead, 200);
    await job('v', TranslationPriority.visible, 10);
    final visibleGap = times['v-start']!.difference(times['a3-end']!);
    expect(visibleGap.inMilliseconds, lessThan(60));
  });

  test('waits while the user scrolls; a page on screen waits only so long',
      () async {
    final s = scheduler();
    final stop = DateTime.now().add(const Duration(milliseconds: 900));
    // The user keeps scrolling for 0.9 s.
    final scrolling = () async {
      while (DateTime.now().isBefore(stop)) {
        s.noteInteraction();
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
    }();

    final asked = DateTime.now();
    DateTime? visibleAt, aheadAt;
    final visible = s.submit((_) async {
      visibleAt = DateTime.now();
      return 'v';
    }, TranslationPriority.visible);
    final ahead = s.submit((_) async {
      aheadAt = DateTime.now();
      return 'a';
    }, TranslationPriority.ahead);
    await Future.wait([visible, ahead, scrolling]);

    final visibleWait = visibleAt!.difference(asked).inMilliseconds;
    expect(visibleWait, greaterThanOrEqualTo(350));
    expect(visibleWait, lessThan(700));
    // Look-ahead work waits for the scrolling to end, plus the quiet time.
    expect(aheadAt!.isAfter(stop), isTrue);
  });

  test('errors reach the caller and the queue keeps going', () async {
    final s = scheduler();
    final failed = s.submit(
        (_) async => throw StateError('boom'), TranslationPriority.visible);
    final ok = s.submit((_) async => 'ok', TranslationPriority.visible);
    await expectLater(failed, throwsStateError);
    expect(await ok, 'ok');
    s.close();
    await expectLater(s.submit((_) async => 'x', TranslationPriority.visible),
        throwsStateError);
  });

  test('thread cap leaves cores for the UI on phones only', () {
    expect(recommendedThreads(cores: 8, mobile: true), 4);
    expect(recommendedThreads(cores: 6, mobile: true), 3);
    expect(recommendedThreads(cores: 4, mobile: true), 2);
    expect(recommendedThreads(cores: 2, mobile: true), 1);
    expect(recommendedThreads(cores: 16, mobile: false), 0);
  });
}
