// One sync run between this device's library and the owner's Supabase
// project: book files, reading positions, saved translations. The rules,
// apart from where things are kept ([SyncLocal], [SyncRemote]):
//
// - A book is its file's MD5 everywhere. EPUBs only (the web reads EPUB).
// - A book this device knew (seen at an earlier sync) and no longer has
//   was deleted here: the remote copy goes too. One the remote marks
//   deleted is removed here, unless this device never saw it.
// - Positions: the newer one wins, by the clock of the device it was
//   saved on.
// - Translations are maps of source-text hash -> translation, merged by
//   union, so nothing either side translated is lost (where both
//   translated the same text, the remote keeps this device's version and
//   this device keeps its own).

// Dart imports:
import 'dart:async';
import 'dart:typed_data';

class RemoteBook {
  const RemoteBook({
    required this.md5,
    required this.bookId,
    required this.fileName,
    required this.title,
    this.author,
    this.format = 'epub',
    this.sizeBytes,
    this.hasFile = false,
    this.deleted = false,
  });

  final String md5;
  final String bookId;
  final String fileName;
  final String title;
  final String? author;
  final String format;
  final int? sizeBytes;
  final bool hasFile;
  final bool deleted;
}

class RemoteProgress {
  const RemoteProgress({
    required this.md5,
    required this.position,
    required this.completed,
    required this.updatedAt,
  });

  final String md5;
  final String position;
  final bool completed;
  final DateTime updatedAt;
}

class RemoteTranslations {
  const RemoteTranslations({
    required this.md5,
    required this.lang,
    required this.style,
    required this.count,
    required this.updatedAt,
  });

  final String md5;
  final String lang;
  final String style;
  final int count;
  final DateTime updatedAt;

  String get key => translationsKey(md5, lang, style);
}

String translationsKey(String md5, String lang, String style) =>
    '$md5|$lang|$style';

/// The owner's project.
abstract class SyncRemote {
  Future<List<RemoteBook>> books();
  Future<void> putBook(RemoteBook book);
  Future<void> markDeleted(String md5);
  Future<void> uploadBook(String md5, String format, Uint8List bytes);
  Future<Uint8List> downloadBook(String md5, String format);
  Future<void> removeBookFile(String md5, String format);
  Future<List<RemoteProgress>> progress();
  Future<void> putProgress(RemoteProgress progress, {required String device});
  Future<List<RemoteTranslations>> translationIndex();
  Future<Map<String, String>> translationEntries(
      String md5, String lang, String style);

  /// Adds [delta]; returns the saved map's size and time.
  Future<RemoteTranslations> mergeTranslations(
      String md5, String lang, String style, Map<String, String> delta);
}

class LocalBook {
  const LocalBook({
    required this.id,
    required this.fileName,
    required this.title,
    this.author,
    required this.format,
  });

  final String id;
  final String fileName;
  final String title;
  final String? author;
  final String format;
}

/// One book's translations into one language and style, open for merging.
abstract class LocalTranslations {
  Map<String, String> get entries;

  /// Adds [other]'s entries this side does not have; how many were new.
  int absorb(Map<String, String> other);

  /// Writes the set without marking it changed (sync wrote it).
  Future<void> save();
}

/// This device's library.
abstract class SyncLocal {
  /// Which side this is ('android', 'web'), for the remote's records.
  String get device;

  Future<List<LocalBook>> books();

  /// The MD5 of [book]'s file (from its id, remembered, or read).
  Future<String?> md5Of(LocalBook book);
  Future<Uint8List?> readBook(LocalBook book);
  Future<LocalBook?> addBook(RemoteBook book, Uint8List bytes);
  Future<void> removeBook(LocalBook book);

  Future<({String position, bool completed})?> position(String fileName);
  Future<void> applyPosition(
      String fileName, String position, bool completed, DateTime at);

  /// Sync's own small values (names by prefix).
  Future<Map<String, String>> state(String prefix);
  Future<void> setState(String name, String? value);

  /// Translation languages and styles a book can have saved.
  List<String> get translationLanguages;
  List<String> get translationStyles;

  /// Where [fileName]'s set for [lang] and [style] is kept, and the sets
  /// kept now.
  Future<String> translationPath(String fileName, String lang, String style);
  Future<Set<String>> translationPaths();
  Future<LocalTranslations> openTranslations(
      String fileName, String lang, String style);
}

class SyncReport {
  int uploaded = 0;
  int downloaded = 0;
  int removedHere = 0;
  int removedThere = 0;
  int skippedForSpace = 0;

  /// Books missing here that were not deleted elsewhere (too many at once).
  int deletesHeld = 0;
  int positionsSent = 0;
  int positionsReceived = 0;
  int translationsSent = 0;
  int translationsReceived = 0;
  final List<String> errors = [];

  bool get changedHere =>
      downloaded > 0 ||
      removedHere > 0 ||
      positionsReceived > 0 ||
      translationsReceived > 0;

  @override
  String toString() => 'up $uploaded, down $downloaded, '
      'removed here $removedHere / there $removedThere, '
      'no space $skippedForSpace, positions $positionsSent/$positionsReceived, '
      'translations $translationsSent/$translationsReceived'
      '${errors.isEmpty ? '' : ', errors ${errors.length}'}';
}

class SyncEngine {
  SyncEngine({
    required this.local,
    required this.remote,
    this.storageLimit = 950 * 1024 * 1024,
    this.mergeChunk = 400,
    this.massDeleteFloor = 3,
    this.massDeleteShare = 0.25,
  });

  final SyncLocal local;
  final SyncRemote remote;

  /// Bytes of book files the remote may hold (Supabase's free plan has
  /// 1 GB of storage).
  final int storageLimit;

  /// Translations sent per request.
  final int mergeChunk;

  /// More than this many books, and more than this share of the books
  /// this device had, missing at once: not a deletion (see [_books]).
  final int massDeleteFloor;
  final double massDeleteShare;

  /// Runs everything; [positionsOnly] for the quick run after a page
  /// turn.
  Future<SyncReport> run({bool positionsOnly = false}) async {
    final report = SyncReport();
    final books = await _localBooks();
    if (!positionsOnly) await _books(books, report);
    await _positions(books, report);
    if (!positionsOnly) await _translations(books, report);
    return report;
  }

  /// This device's EPUBs by MD5.
  Future<Map<String, LocalBook>> _localBooks() async {
    final out = <String, LocalBook>{};
    for (final book in await local.books()) {
      if (book.format.toLowerCase() != 'epub') continue;
      final md5 = await local.md5Of(book);
      if (md5 != null) out[md5] = book;
    }
    return out;
  }

  Future<void> _books(Map<String, LocalBook> here, SyncReport report) async {
    final there = {for (final b in await remote.books()) b.md5: b};
    final seen = (await local.state('seen:'))
        .keys
        .map((k) => k.substring('seen:'.length))
        .toSet();
    var used = 0;
    for (final b in there.values) {
      if (b.hasFile && !b.deleted) used += b.sizeBytes ?? 0;
    }

    // This device's books: removed here when deleted elsewhere, sent when
    // the remote has no file.
    for (final MapEntry(key: md5, value: book) in here.entries.toList()) {
      final remoteBook = there[md5];
      try {
        if (remoteBook != null && remoteBook.deleted && seen.contains(md5)) {
          await local.removeBook(book);
          here.remove(md5);
          await local.setState('seen:$md5', null);
          report.removedHere++;
          continue;
        }
        if (remoteBook == null || !remoteBook.hasFile || remoteBook.deleted) {
          final bytes = await local.readBook(book);
          if (bytes == null) continue;
          if (used + bytes.length > storageLimit) {
            report.skippedForSpace++;
            continue;
          }
          await remote.uploadBook(md5, 'epub', bytes);
          used += bytes.length;
          await remote.putBook(RemoteBook(
            md5: md5,
            bookId: book.id,
            fileName: book.fileName,
            title: book.title,
            author: book.author,
            sizeBytes: bytes.length,
            hasFile: true,
          ));
          report.uploaded++;
        }
        await local.setState('seen:$md5', '1');
      } catch (e) {
        report.errors.add('book ${book.fileName}: $e');
      }
    }

    // The remote's books: fetched when new here, deleted there when this
    // device had them and no longer does - unless many went at once (a
    // book folder that moved or could not be read empties the library
    // without anyone deleting a book): then nothing is deleted.
    final gone = [
      for (final b in there.values)
        if (!b.deleted &&
            b.hasFile &&
            !here.containsKey(b.md5) &&
            seen.contains(b.md5))
          b.md5,
    ];
    final holdDeletes = gone.length > massDeleteFloor &&
        gone.length > seen.length * massDeleteShare;
    if (holdDeletes) report.deletesHeld = gone.length;
    for (final remoteBook in there.values) {
      if (remoteBook.deleted || !remoteBook.hasFile) continue;
      if (here.containsKey(remoteBook.md5)) continue;
      try {
        if (seen.contains(remoteBook.md5)) {
          if (holdDeletes) continue;
          await remote.markDeleted(remoteBook.md5);
          await remote.removeBookFile(remoteBook.md5, remoteBook.format);
          await local.setState('seen:${remoteBook.md5}', null);
          report.removedThere++;
          continue;
        }
        final bytes =
            await remote.downloadBook(remoteBook.md5, remoteBook.format);
        final added = await local.addBook(remoteBook, bytes);
        if (added != null) {
          here[remoteBook.md5] = added;
          await local.setState('seen:${remoteBook.md5}', '1');
          report.downloaded++;
        }
      } catch (e) {
        report.errors.add('book ${remoteBook.fileName}: $e');
      }
    }
  }

  Future<void> _positions(
      Map<String, LocalBook> here, SyncReport report) async {
    final there = {for (final p in await remote.progress()) p.md5: p};
    final changed = await local.state('pos:');
    final sent = await local.state('posSent:');
    for (final MapEntry(key: md5, value: book) in here.entries) {
      try {
        final localMs = int.tryParse(changed['pos:${book.fileName}'] ?? '');
        final sentMs = int.tryParse(sent['posSent:${book.fileName}'] ?? '');
        final remoteAt = there[md5]?.updatedAt;
        final localAt = localMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(localMs, isUtc: true);
        final unsent = localMs != null && (sentMs == null || localMs > sentMs);
        if (unsent && (remoteAt == null || localAt!.isAfter(remoteAt))) {
          final row = await local.position(book.fileName);
          if (row == null) continue;
          await remote.putProgress(
              RemoteProgress(
                md5: md5,
                position: row.position,
                completed: row.completed,
                updatedAt: localAt!,
              ),
              device: local.device);
          await local.setState('posSent:${book.fileName}', '$localMs');
          report.positionsSent++;
        } else if (remoteAt != null &&
            (localAt == null || remoteAt.isAfter(localAt))) {
          final p = there[md5]!;
          await local.applyPosition(
              book.fileName, p.position, p.completed, p.updatedAt);
          report.positionsReceived++;
        }
      } catch (e) {
        report.errors.add('position ${book.fileName}: $e');
      }
    }
  }

  Future<void> _translations(
      Map<String, LocalBook> here, SyncReport report) async {
    final index = {for (final t in await remote.translationIndex()) t.key: t};
    final dirty = await local.state('trdirty:');
    final seenAt = await local.state('trseen:');
    final firstRun = (await local.state('trinit')).isEmpty;
    final kept = await local.translationPaths();

    for (final MapEntry(key: md5, value: book) in here.entries) {
      for (final lang in local.translationLanguages) {
        for (final style in local.translationStyles) {
          final key = translationsKey(md5, lang, style);
          final info = index[key];
          final path = await local.translationPath(book.fileName, lang, style);
          final localChanged = dirty.containsKey('trdirty:$path') ||
              (firstRun && kept.contains(path));
          final remoteChanged = info != null &&
              seenAt['trseen:$key'] != info.updatedAt.toIso8601String();
          if (!localChanged && !remoteChanged) continue;
          try {
            final set =
                await local.openTranslations(book.fileName, lang, style);
            final theirs = info == null
                ? const <String, String>{}
                : await remote.translationEntries(md5, lang, style);
            report.translationsReceived += set.absorb(theirs);
            final delta = <String, String>{
              for (final MapEntry(:key, :value) in set.entries.entries)
                if (theirs[key] != value) key: value,
            };
            var latest = info?.updatedAt;
            final keys = delta.keys.toList();
            for (var i = 0; i < keys.length; i += mergeChunk) {
              final part = {
                for (final k in keys.skip(i).take(mergeChunk)) k: delta[k]!,
              };
              latest = (await remote.mergeTranslations(md5, lang, style, part))
                  .updatedAt;
            }
            report.translationsSent += delta.length;
            await set.save();
            // Only the change seen at the start is done; a newer one
            // (the reader went on translating) waits for the next run.
            final stamp = dirty['trdirty:$path'];
            final now = (await local.state('trdirty:$path'))['trdirty:$path'];
            if (now == stamp) await local.setState('trdirty:$path', null);
            if (latest != null) {
              await local.setState('trseen:$key', latest.toIso8601String());
            }
          } catch (e) {
            report.errors.add('translations ${book.fileName} $lang: $e');
          }
        }
      }
    }
    if (firstRun) await local.setState('trinit', '1');
  }
}
