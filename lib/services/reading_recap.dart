// Reading recap: milestones (checkpoints) for finished books, the
// reading streak, the last four weeks of activity, this month's numbers
// and the genre mix - the figures behind the library's recap cards.

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/library_organization.dart';
import 'package:openlib/state/state.dart' show libraryBooksProvider;

/// Finished-book counts that earn a checkpoint.
const readingMilestones = [
  1, 3, 5, 10, 20, 30, 50, 75, 100, 150, 200, 300, 500, 1000, //
];

/// Where a count sits between two checkpoints.
class Milestone {
  const Milestone({required this.reached, required this.next});

  /// The last checkpoint passed, 0 before the first.
  final int reached;

  /// The next checkpoint, null past the last one.
  final int? next;

  static Milestone of(int completed) {
    var reached = 0;
    int? next;
    for (final m in readingMilestones) {
      if (completed >= m) {
        reached = m;
      } else {
        next = m;
        break;
      }
    }
    return Milestone(reached: reached, next: next);
  }

  /// 0..1 share of the next checkpoint already finished (3 of 5 is
  /// 0.6), so the ring never looks empty right after a checkpoint.
  double progress(int completed) {
    if (next == null) return 1;
    return (completed / next!).clamp(0.0, 1.0);
  }

  /// Books still to finish for the next checkpoint.
  int remaining(int completed) => next == null ? 0 : next! - completed;
}

class ReadingRecap {
  const ReadingRecap({
    required this.total,
    required this.completed,
    required this.inProgress,
    required this.currentStreak,
    required this.longestStreak,
    required this.recentDays,
    required this.completedThisMonth,
    required this.readingDaysThisMonth,
    required this.genres,
    required this.month,
  });

  final int total;
  final int completed;
  final int inProgress;

  /// Days in a row with reading, ending today (or yesterday, while today
  /// has no reading yet).
  final int currentStreak;
  final int longestStreak;

  /// Reading per day for the last [recentDayCount] days, oldest first;
  /// the last entry is today.
  final List<int> recentDays;
  static const recentDayCount = 28;

  final int completedThisMonth;
  final int readingDaysThisMonth;

  /// Books per genre, largest first; books without a genre are left out.
  final List<MapEntry<BookGenre, int>> genres;

  /// The month "this month" refers to (1-12).
  final int month;

  Milestone get milestone => Milestone.of(completed);
  int get recentReadingDays => recentDays.where((h) => h > 0).length;
}

/// Builds the recap from the library and the activity tables at [now].
ReadingRecap computeReadingRecap({
  required List<LibraryBook> books,
  required Map<String, int> readingDays,
  required Map<String, DateTime> completionDates,
  required DateTime now,
}) {
  final today = DateTime(now.year, now.month, now.day);
  // Calendar arithmetic (not Duration) so a daylight-saving day of 23
  // or 25 hours never skips or repeats a date.
  DateTime daysBefore(DateTime day, int n) =>
      DateTime(day.year, day.month, day.day - n);
  int dayIndex(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;
  bool readOn(DateTime day) => (readingDays[MyLibraryDb.dayKey(day)] ?? 0) > 0;

  // Current streak: today counts if read; otherwise start from yesterday
  // so an evening reader's streak does not reset in the morning.
  var current = 0;
  var cursor = readOn(today) ? today : daysBefore(today, 1);
  while (readOn(cursor)) {
    current++;
    cursor = daysBefore(cursor, 1);
  }

  // Longest run over every recorded day.
  final days = readingDays.entries
      .where((e) => e.value > 0)
      .map((e) => DateTime.tryParse(e.key))
      .whereType<DateTime>()
      .toList()
    ..sort();
  var longest = 0;
  var run = 0;
  DateTime? previous;
  for (final day in days) {
    run = previous != null && dayIndex(day) - dayIndex(previous) == 1
        ? run + 1
        : 1;
    if (run > longest) longest = run;
    previous = day;
  }
  if (current > longest) longest = current;

  final recent = [
    for (var i = ReadingRecap.recentDayCount - 1; i >= 0; i--)
      readingDays[MyLibraryDb.dayKey(daysBefore(today, i))] ?? 0,
  ];

  bool thisMonth(DateTime t) => t.year == now.year && t.month == now.month;
  final libraryFiles = {for (final b in books) b.book.getFileName()};
  final completedThisMonth = completionDates.entries
      .where((e) => libraryFiles.contains(e.key) && thisMonth(e.value))
      .length;
  final readingDaysThisMonth = days.where(thisMonth).length;

  final genreCounts = <BookGenre, int>{};
  for (final book in books) {
    final genre = book.genre;
    if (genre != null) genreCounts[genre] = (genreCounts[genre] ?? 0) + 1;
  }
  final genres = genreCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  return ReadingRecap(
    total: books.length,
    completed: books.where((b) => b.status == ReadingStatus.completed).length,
    inProgress: books.where((b) => b.status == ReadingStatus.inProgress).length,
    currentStreak: current,
    longestStreak: longest,
    recentDays: recent,
    completedThisMonth: completedThisMonth,
    readingDaysThisMonth: readingDaysThisMonth,
    genres: genres,
    month: now.month,
  );
}

final readingRecapProvider = FutureProvider<ReadingRecap>((ref) async {
  final books = await ref.watch(libraryBooksProvider.future);
  final db = MyLibraryDb.instance;
  final readingDays =
      await db.getReadingDays().catchError((_) => <String, int>{});
  final completions =
      await db.getCompletionDates().catchError((_) => <String, DateTime>{});
  return computeReadingRecap(
    books: books,
    readingDays: readingDays,
    completionDates: completions,
    now: DateTime.now(),
  );
});
