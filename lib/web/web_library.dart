// The web's library: the books in this browser and the ones the account
// keeps, as one list. A book the account has shows at once (title,
// author, a small cover) whether or not its file is here.

// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/local_book_import.dart' show md5FromBookId;
import 'package:openlib/services/sync/remote_library.dart';
import 'package:openlib/services/sync/sync_engine.dart';

/// One book of the library: in this browser ([local]), in the account
/// ([remote]), or both.
@immutable
class WebBook {
  const WebBook({
    this.md5,
    this.local,
    this.remote,
    this.fraction,
    this.completed = false,
    this.readAt,
    this.translated = const {},
  });

  final String? md5;
  final MyBook? local;
  final RemoteBook? remote;

  /// How far it was read (0..1), or null when no device said.
  final double? fraction;
  final bool completed;

  /// When it was last read, on whichever device.
  final DateTime? readAt;

  /// Paragraphs translated, by language.
  final Map<String, int> translated;

  String get key => md5 ?? local!.id;
  bool get downloaded => local != null;
  bool get onAccount => remote != null;
  String get title => local?.title ?? remote?.title ?? '';

  String get author {
    final a = (local?.author ?? remote?.author ?? '').trim();
    return a == 'Unknown' ? '' : a;
  }

  String get publisher => (local?.publisher ?? remote?.publisher ?? '').trim();
  String get description =>
      (local?.description ?? remote?.description ?? '').trim();
  int? get sizeBytes => remote?.sizeBytes;
  DateTime? get addedAt => remote?.addedAt;
  bool get finished => completed || (fraction ?? 0) >= 0.995;
  bool get started => readAt != null || (fraction ?? 0) > 0;

  /// Whether [query] (lower case) is in what a search looks at.
  bool matches(String query) =>
      title.toLowerCase().contains(query) ||
      author.toLowerCase().contains(query) ||
      publisher.toLowerCase().contains(query);
}

enum WebFilter { all, reading, downloaded, finished }

enum WebSort { recent, title, author, added }

class WebLibrary extends ChangeNotifier {
  WebLibrary({MyLibraryDb? database, RemoteLibraryStore? remote})
      : _db = database ?? MyLibraryDb.instance,
        _remote = remote ?? RemoteLibraryStore.instance {
    _remote.addListener(_remoteChanged);
  }

  final MyLibraryDb _db;
  final RemoteLibraryStore _remote;
  List<WebBook>? _books;
  bool _disposed = false;
  int _generation = 0;

  /// Every book; null until the first read.
  List<WebBook>? get books => _books;

  void _remoteChanged() => unawaited(reload());

  /// Reads what is in this browser and merges it with the account's list.
  Future<void> reload() async {
    final generation = ++_generation;
    final local = [
      for (final b in await _db.getAll())
        if ((b.format ?? '').toLowerCase() == 'epub') b,
    ];
    final md5s = await _db.getSyncStates('md5:');
    final fractions = await _db.getSyncStates('frac:');
    final stamps = await _db.getSyncStates('pos:');
    if (_disposed || generation != _generation) return;
    _books = mergeLibrary(
      local: local,
      remote: _remote.library,
      md5Of: (b) => md5FromBookId(b.id) ?? md5s['md5:${b.getFileName()}'],
      fractionOf: (b) =>
          double.tryParse(fractions['frac:${b.getFileName()}'] ?? ''),
      readAtOf: (b) {
        final ms = int.tryParse(stamps['pos:${b.getFileName()}'] ?? '');
        // 1 ms: a position from before sync kept times.
        return ms == null || ms <= 1
            ? null
            : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
      },
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _remote.removeListener(_remoteChanged);
    super.dispose();
  }
}

/// The books here and the account's as one list (a book on both sides
/// once, by its file's MD5).
List<WebBook> mergeLibrary({
  required List<MyBook> local,
  required RemoteLibrary remote,
  required String? Function(MyBook book) md5Of,
  required double? Function(MyBook book) fractionOf,
  required DateTime? Function(MyBook book) readAtOf,
}) {
  final rows = {for (final b in remote.books) b.md5: b};
  final out = <WebBook>[];
  final here = <String>{};
  for (final book in local) {
    final md5 = md5Of(book);
    if (md5 != null) here.add(md5);
    final theirs = md5 == null ? null : remote.progress[md5];
    final mine = readAtOf(book);
    // The newer reading says how far.
    final theirsNewer =
        theirs != null && (mine == null || theirs.updatedAt.isAfter(mine));
    out.add(WebBook(
      md5: md5,
      local: book,
      remote: md5 == null ? null : rows[md5],
      fraction: theirsNewer ? theirs.fraction : fractionOf(book),
      completed: theirs?.completed ?? false,
      readAt: theirsNewer ? theirs.updatedAt : mine ?? _known(theirs),
      translated: remote.translated[md5] ?? const {},
    ));
  }
  for (final row in remote.books) {
    if (here.contains(row.md5)) continue;
    final theirs = remote.progress[row.md5];
    out.add(WebBook(
      md5: row.md5,
      remote: row,
      fraction: theirs?.fraction,
      completed: theirs?.completed ?? false,
      readAt: _known(theirs),
      translated: remote.translated[row.md5] ?? const {},
    ));
  }
  return out;
}

DateTime? _known(RemoteProgress? p) =>
    p == null || !p.updatedAt.isAfter(unknownAge) ? null : p.updatedAt;

/// [books] as the library shows them for [filter], [query] and [sort].
List<WebBook> arrangeLibrary(
  List<WebBook> books, {
  WebFilter filter = WebFilter.all,
  String query = '',
  WebSort sort = WebSort.recent,
}) {
  final q = query.trim().toLowerCase();
  final shown = [
    for (final b in books)
      if (switch (filter) {
            WebFilter.all => true,
            WebFilter.reading => b.started && !b.finished,
            WebFilter.downloaded => b.downloaded,
            WebFilter.finished => b.finished,
          } &&
          (q.isEmpty || b.matches(q)))
        b,
  ];
  final never = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  int byTitle(WebBook a, WebBook b) =>
      a.title.toLowerCase().compareTo(b.title.toLowerCase());
  shown.sort(switch (sort) {
    WebSort.title => byTitle,
    WebSort.author => (a, b) {
        final c = a.author.toLowerCase().compareTo(b.author.toLowerCase());
        return c != 0 ? c : byTitle(a, b);
      },
    WebSort.added => (a, b) {
        final c = (b.addedAt ?? never).compareTo(a.addedAt ?? never);
        return c != 0 ? c : byTitle(a, b);
      },
    WebSort.recent => (a, b) {
        final c = (b.readAt ?? never).compareTo(a.readAt ?? never);
        if (c != 0) return c;
        final d = (b.addedAt ?? never).compareTo(a.addedAt ?? never);
        return d != 0 ? d : byTitle(a, b);
      },
  });
  return shown;
}

/// The book to offer for "continue reading": the one read last and not
/// finished.
WebBook? continueReading(List<WebBook> books) {
  WebBook? best;
  for (final b in books) {
    if (b.readAt == null || b.finished) continue;
    if (best == null || b.readAt!.isAfter(best.readAt!)) best = b;
  }
  return best;
}

/// "3.4 MB".
String formatBytes(int bytes) {
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).clamp(1, 1023).round()} KB';
  }
  final mb = bytes / (1024 * 1024);
  return mb >= 100 || mb == mb.roundToDouble()
      ? '${mb.round()} MB'
      : '${mb.toStringAsFixed(1)} MB';
}
