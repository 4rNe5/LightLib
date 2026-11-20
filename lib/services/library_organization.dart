// Flutter imports:
import 'package:flutter/foundation.dart';

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/search_results.dart' show volumeOf;

/// How the library list is ordered. Each mode has a stable persisted key
/// so the choice survives restarts.
enum LibrarySortMode {
  dateAddedDesc('dateAddedDesc'),
  dateAddedAsc('dateAddedAsc'),
  titleAsc('titleAsc'),
  titleDesc('titleDesc'),
  authorAsc('authorAsc'),
  authorDesc('authorDesc'),
  fileSizeDesc('fileSizeDesc'),
  fileSizeAsc('fileSizeAsc'),
  readingStatus('readingStatus');

  const LibrarySortMode(this.key);

  final String key;

  static LibrarySortMode fromKey(String key) =>
      LibrarySortMode.values.firstWhere(
        (m) => m.key == key,
        orElse: () => LibrarySortMode.dateAddedDesc,
      );

  String get label {
    switch (this) {
      case LibrarySortMode.dateAddedDesc:
        return 'Newest added';
      case LibrarySortMode.dateAddedAsc:
        return 'Oldest added';
      case LibrarySortMode.titleAsc:
        return 'Title A-Z';
      case LibrarySortMode.titleDesc:
        return 'Title Z-A';
      case LibrarySortMode.authorAsc:
        return 'Author A-Z';
      case LibrarySortMode.authorDesc:
        return 'Author Z-A';
      case LibrarySortMode.fileSizeDesc:
        return 'Largest file';
      case LibrarySortMode.fileSizeAsc:
        return 'Smallest file';
      case LibrarySortMode.readingStatus:
        return 'Reading status';
    }
  }
}

/// A book's reading state, derived from the saved position: nothing
/// saved means unread, a saved position marked finished means completed,
/// anything else is in progress.
enum ReadingStatus { unread, inProgress, completed }

/// A book's genre, chosen by the user. Stored by [key] so the list can
/// grow without breaking saved choices.
enum BookGenre {
  lightNovel('lightNovel'),
  comic('comic'),
  novel('novel'),
  englishNovel('englishNovel'),
  essay('essay'),
  science('science'),
  humanities('humanities'),
  business('business'),
  paper('paper'),
  textbook('textbook'),
  other('other');

  const BookGenre(this.key);

  final String key;

  static BookGenre? fromKey(String? key) {
    for (final g in BookGenre.values) {
      if (g.key == key) return g;
    }
    return null;
  }
}

/// A [MyBook] enriched with everything sorting and filtering need: the
/// tags it carries, its reading status and its file size in bytes.
@immutable
class LibraryBook {
  final MyBook book;
  final Set<String> tags;
  final ReadingStatus status;
  final int? fileSizeBytes;
  final BookGenre? genre;

  /// The series the reader put it in, if any.
  final String? series;

  const LibraryBook({
    required this.book,
    this.tags = const {},
    this.status = ReadingStatus.unread,
    this.fileSizeBytes,
    this.genre,
    this.series,
  });

  String get id => book.id;
  String get title => book.title;
  String get author => book.author ?? '';
}

/// A series the reader made, its volumes in reading order.
@immutable
class LibrarySeries {
  const LibrarySeries(this.name, this.volumes);
  final String name;
  final List<LibraryBook> volumes;
}

/// The series among [books], in the order their first volumes come in
/// [books]; each one's volumes by the number in their titles (a title
/// that names none after those that do, by title).
List<LibrarySeries> librarySeries(List<LibraryBook> books) {
  final groups = <String, List<LibraryBook>>{};
  for (final b in books) {
    final name = b.series;
    if (name != null && name.isNotEmpty) (groups[name] ??= []).add(b);
  }
  return [
    for (final MapEntry(key: name, value: volumes) in groups.entries)
      LibrarySeries(
          name,
          volumes
            ..sort((x, y) {
              final a = volumeOf(x.title).number, b = volumeOf(y.title).number;
              if (a != null && b != null && a != b) return a.compareTo(b);
              if ((a == null) != (b == null)) return a == null ? 1 : -1;
              return x.title.compareTo(y.title);
            })),
  ];
}

/// A name to offer for a series made of books called [titles]: the
/// series most of the titles name, as their titles write it.
String suggestedSeriesName(Iterable<String> titles) {
  final count = <String, int>{};
  for (final t in titles) {
    final series = volumeOf(t).series.trim();
    if (series.isNotEmpty) count[series] = (count[series] ?? 0) + 1;
  }
  if (count.isEmpty) return '';
  // (The first of the most frequent: the order the books were chosen in.)
  var best = count.keys.first;
  for (final MapEntry(key: series, value: n) in count.entries) {
    if (n > count[best]!) best = series;
  }
  return best;
}

/// Sorts books by [mode]. Two books comparing equal fall back to the
/// date-added order (the list as stored), so sorting never shuffles
/// unrelated items.
List<LibraryBook> sortLibrary(List<LibraryBook> books, LibrarySortMode mode) {
  final sorted = List<LibraryBook>.of(books);
  String t(LibraryBook b) => b.title.toLowerCase();
  String a(LibraryBook b) => b.author.toLowerCase();
  switch (mode) {
    case LibrarySortMode.dateAddedDesc:
    case LibrarySortMode.dateAddedAsc:
      break; // stored order already applies
    case LibrarySortMode.titleAsc:
      sorted.sort((x, y) => t(x).compareTo(t(y)));
    case LibrarySortMode.titleDesc:
      sorted.sort((x, y) => t(y).compareTo(t(x)));
    case LibrarySortMode.authorAsc:
      sorted.sort((x, y) {
        final c = a(x).compareTo(a(y));
        return c != 0 ? c : t(x).compareTo(t(y));
      });
    case LibrarySortMode.authorDesc:
      sorted.sort((x, y) {
        final c = a(y).compareTo(a(x));
        return c != 0 ? c : t(x).compareTo(t(y));
      });
    case LibrarySortMode.fileSizeDesc:
      sorted.sort(
          (x, y) => (y.fileSizeBytes ?? -1).compareTo(x.fileSizeBytes ?? -1));
    case LibrarySortMode.fileSizeAsc:
      sorted.sort((x, y) =>
          (x.fileSizeBytes ?? 1 << 40).compareTo(y.fileSizeBytes ?? 1 << 40));
    case LibrarySortMode.readingStatus:
      sorted.sort((x, y) {
        final c = x.status.index.compareTo(y.status.index);
        return c != 0 ? c : t(x).compareTo(t(y));
      });
  }
  if (mode == LibrarySortMode.dateAddedAsc) {
    return sorted.reversed.toList();
  }
  return sorted;
}

/// Keeps only the books matching every active filter. A null tag or
/// status filter means "no filter"; an empty tag filter set also
/// means "no filter". A [query] matches case-insensitively against
/// the metadata captured when the book was added: title, author,
/// publisher and the info line (which carries year and language).
List<LibraryBook> filterLibrary(
  List<LibraryBook> books, {
  Set<String>? tagFilter,
  ReadingStatus? statusFilter,
  BookGenre? genreFilter,
  String? query,
}) {
  final needle = query?.trim().toLowerCase();
  return books.where((b) {
    if (genreFilter != null && b.genre != genreFilter) return false;
    if (tagFilter != null && tagFilter.isNotEmpty) {
      if (!tagFilter.any(b.tags.contains)) return false;
    }
    if (statusFilter != null && b.status != statusFilter) return false;
    if (needle != null && needle.isNotEmpty) {
      final haystack = [
        b.title,
        b.author,
        b.book.publisher ?? '',
        b.book.info ?? '',
      ].join(' ').toLowerCase();
      if (!haystack.contains(needle)) return false;
    }
    return true;
  }).toList();
}
