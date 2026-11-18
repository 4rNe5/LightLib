// One sync run between this device's library and the owner's Supabase
// project: book files, reading positions, saved translations and each
// book's glossary. The rules, apart from where things are kept
// ([SyncLocal], [SyncRemote]):
//
// - A book is its file's MD5 everywhere. EPUBs only (the web reads EPUB).
// - A book this device knew (seen at an earlier sync) and no longer has
//   was deleted here: the remote copy goes too. One the remote marks
//   deleted is removed here, unless this device never saw it.
// - Positions and glossaries: the newer one wins, by the clock of the
//   device it was saved on. One saved before sync existed (no time) goes
//   up only where the remote has none.
// - Translations are maps of source-text hash -> translation, merged by
//   union, so nothing either side translated is lost (where both
//   translated the same text, the remote keeps this device's version and
//   this device keeps its own).
//
// Order: deletions, then what is small and already here (positions,
// translations, glossaries), then book files - each book fetched brings
// its position, translations and glossary with it, so a book is whole
// as soon as it shows up.
//
// The web keeps only the books it was asked to open ([SyncEngine.onDemand]):
// it lists the library from the remote's rows ([RemoteLibrary] - title,
// author, a small cover) and fetches one file when its book is opened
// ([SyncEngine.fetchBook]). Nothing is deleted there because a file is
// not in the browser; a deletion is asked for ([SyncEngine.deleteBook]).
//
// Settings the devices share (the Gemini key) follow the newest-wins rule
// of positions.

// Dart imports:
import 'dart:async';
import 'dart:math' as math;
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
    this.publisher,
    this.description,
    this.hasCover = false,
    this.addedAt,
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
  final String? publisher;

  /// Null: put by a version that sent no details ('' = the book has none).
  final String? description;

  /// A small cover is kept beside the file ([SyncRemote.downloadCover]).
  final bool hasCover;
  final DateTime? addedAt;

  RemoteBook copyWith({
    int? sizeBytes,
    bool? hasFile,
    bool? deleted,
    String? publisher,
    String? description,
    bool? hasCover,
  }) =>
      RemoteBook(
        md5: md5,
        bookId: bookId,
        fileName: fileName,
        title: title,
        author: author,
        format: format,
        sizeBytes: sizeBytes ?? this.sizeBytes,
        hasFile: hasFile ?? this.hasFile,
        deleted: deleted ?? this.deleted,
        publisher: publisher ?? this.publisher,
        description: description ?? this.description,
        hasCover: hasCover ?? this.hasCover,
        addedAt: addedAt,
      );

  Map<String, dynamic> toJson() => {
        'md5': md5,
        'bookId': bookId,
        'fileName': fileName,
        'title': title,
        if (author != null) 'author': author,
        'format': format,
        if (sizeBytes != null) 'sizeBytes': sizeBytes,
        'hasFile': hasFile,
        if (publisher != null) 'publisher': publisher,
        if (description != null) 'description': description,
        'hasCover': hasCover,
        if (addedAt != null) 'addedAt': addedAt!.toIso8601String(),
      };

  static RemoteBook? fromJson(Object? json) {
    if (json is! Map) return null;
    final md5 = json['md5'], bookId = json['bookId'], file = json['fileName'];
    if (md5 is! String || bookId is! String || file is! String) return null;
    return RemoteBook(
      md5: md5,
      bookId: bookId,
      fileName: file,
      title: '${json['title'] ?? ''}',
      author: json['author'] as String?,
      format: '${json['format'] ?? 'epub'}',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
      hasFile: json['hasFile'] == true,
      publisher: json['publisher'] as String?,
      description: json['description'] as String?,
      hasCover: json['hasCover'] == true,
      addedAt: DateTime.tryParse('${json['addedAt'] ?? ''}'),
    );
  }
}

class RemoteProgress {
  const RemoteProgress({
    required this.md5,
    required this.position,
    required this.completed,
    required this.updatedAt,
    this.fraction,
  });

  final String md5;
  final String position;
  final bool completed;
  final DateTime updatedAt;

  /// How far the book was read (0..1); null when the device that saved
  /// the position did not say.
  final double? fraction;

  Map<String, dynamic> toJson() => {
        'position': position,
        'completed': completed,
        'updatedAt': updatedAt.toIso8601String(),
        if (fraction != null) 'fraction': fraction,
      };

  static RemoteProgress? fromJson(String md5, Object? json) {
    if (json is! Map) return null;
    final at = DateTime.tryParse('${json['updatedAt'] ?? ''}');
    if (at == null) return null;
    return RemoteProgress(
      md5: md5,
      position: '${json['position'] ?? ''}',
      completed: json['completed'] == true,
      updatedAt: at,
      fraction: (json['fraction'] as num?)?.toDouble(),
    );
  }
}

/// A setting as the remote keeps it.
class RemoteSetting {
  const RemoteSetting(this.value, this.updatedAt);
  final String value;
  final DateTime updatedAt;
}

/// The library as the remote lists it, for a device that does not keep
/// every file: the books that have one, where each was read, and how many
/// paragraphs are translated (by book, then language).
class RemoteLibrary {
  const RemoteLibrary({
    this.books = const [],
    this.progress = const {},
    this.translated = const {},
  });

  final List<RemoteBook> books;
  final Map<String, RemoteProgress> progress;
  final Map<String, Map<String, int>> translated;

  Map<String, dynamic> toJson() => {
        'books': [for (final b in books) b.toJson()],
        'progress': {
          for (final e in progress.entries) e.key: e.value.toJson(),
        },
        'translated': translated,
      };

  static RemoteLibrary fromJson(Object? json) {
    if (json is! Map) return const RemoteLibrary();
    final progress = <String, RemoteProgress>{};
    final rows = json['progress'];
    if (rows is Map) {
      rows.forEach((k, v) {
        final p = RemoteProgress.fromJson('$k', v);
        if (p != null) progress['$k'] = p;
      });
    }
    final translated = <String, Map<String, int>>{};
    final counts = json['translated'];
    if (counts is Map) {
      counts.forEach((k, v) {
        if (v is Map) {
          translated['$k'] = {
            for (final e in v.entries)
              if (e.value is num) '${e.key}': (e.value as num).toInt(),
          };
        }
      });
    }
    return RemoteLibrary(
      books: [
        for (final b in (json['books'] as List? ?? const []))
          if (RemoteBook.fromJson(b) case final book?) book,
      ],
      progress: progress,
      translated: translated,
    );
  }
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

/// The time given to a position or glossary saved before sync existed:
/// older than anything another device saved.
final unknownAge = DateTime.fromMillisecondsSinceEpoch(1, isUtc: true);

/// The owner's project.
abstract class SyncRemote {
  Future<List<RemoteBook>> books();
  Future<void> putBook(RemoteBook book);
  Future<void> markDeleted(String md5);
  Future<void> uploadBook(String md5, String format, Uint8List bytes);

  /// The file; [onProgress] hears how much of it has come.
  Future<Uint8List> downloadBook(String md5, String format,
      {void Function(int received, int? total)? onProgress});

  /// Removes the file and its cover.
  Future<void> removeBookFile(String md5, String format);

  /// A small JPEG of the book's cover, kept beside its file.
  Future<void> uploadCover(String md5, Uint8List jpeg);
  Future<Uint8List?> downloadCover(String md5);
  Future<List<RemoteProgress>> progress();
  Future<void> putProgress(RemoteProgress progress, {required String device});
  Future<List<RemoteTranslations>> translationIndex();
  Future<Map<String, String>> translationEntries(
      String md5, String lang, String style);

  /// Adds [delta]; returns the saved map's size and time.
  Future<RemoteTranslations> mergeTranslations(
      String md5, String lang, String style, Map<String, String> delta);

  /// When each book's glossary was saved, by MD5.
  Future<Map<String, DateTime>> glossaryIndex();
  Future<String?> glossary(String md5);

  /// Keeps [data] unless the remote's is newer than [at].
  Future<void> putGlossary(String md5, String data, DateTime at,
      {required String device});

  /// The shared settings, by name.
  Future<Map<String, RemoteSetting>> settings();

  /// Keeps [value] unless the remote's is newer than [at].
  Future<void> putSetting(String name, String value, DateTime at,
      {required String device});
  Future<void> removeSetting(String name);
}

class LocalBook {
  const LocalBook({
    required this.id,
    required this.fileName,
    required this.title,
    this.author,
    required this.format,
    this.publisher,
    this.description,
  });

  final String id;
  final String fileName;
  final String title;
  final String? author;
  final String format;
  final String? publisher;
  final String? description;
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

  /// [fileName]'s glossary as saved (JSON), or null.
  Future<String?> glossary(String fileName);

  /// A glossary from another device: saved without counting as a change
  /// made here.
  Future<void> applyGlossary(String fileName, String data, DateTime at);

  /// A small JPEG of [book]'s cover for the other devices' libraries, or
  /// null when it has none.
  Future<Uint8List?> coverThumbnail(LocalBook book);

  /// Names of the settings this device shares (none when the owner
  /// turned that off here).
  Future<List<String>> syncedSettings();

  /// The value of the setting [name] here ('' = not set).
  Future<String> setting(String name);

  /// A setting from another device: saved without counting as a change
  /// made here.
  Future<void> applySetting(String name, String value);
}

enum SyncStage { checking, translations, uploading, downloading }

/// Where a run is: [done] of [total] in [stage], on the book [title].
class SyncProgress {
  const SyncProgress(this.stage, {this.done = 0, this.total = 0, this.title});
  final SyncStage stage;
  final int done;
  final int total;
  final String? title;

  /// Book files or translations move (worth telling the reader about).
  bool get transfers => stage != SyncStage.checking && total > 0;
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
  int glossariesSent = 0;
  int glossariesReceived = 0;
  int coversSent = 0;
  int settingsSent = 0;
  int settingsReceived = 0;
  final List<String> errors = [];

  bool get changedHere =>
      downloaded > 0 ||
      removedHere > 0 ||
      positionsReceived > 0 ||
      translationsReceived > 0 ||
      glossariesReceived > 0;

  bool get changedAnything =>
      changedHere ||
      uploaded > 0 ||
      removedThere > 0 ||
      positionsSent > 0 ||
      translationsSent > 0 ||
      glossariesSent > 0;

  @override
  String toString() => 'up $uploaded, down $downloaded, '
      'removed here $removedHere / there $removedThere, '
      'no space $skippedForSpace, positions $positionsSent/$positionsReceived, '
      'translations $translationsSent/$translationsReceived, '
      'glossaries $glossariesSent/$glossariesReceived, covers $coversSent, '
      'settings $settingsSent/$settingsReceived'
      '${errors.isEmpty ? '' : ', errors ${errors.length}'}';
}

/// What a run read once and every step uses.
class _Run {
  _Run(this.report);
  final SyncReport report;
  Map<String, RemoteProgress> progress = {};
  Map<String, RemoteTranslations> translations = {};
  Map<String, DateTime> glossaries = {};
  Map<String, String> positionStamps = {};
  Map<String, String> positionSent = {};
  Map<String, String> glossaryStamps = {};
  Map<String, String> glossarySent = {};
  Map<String, String> fractions = {};
  Map<String, String> dirty = {};
  Map<String, String> seenAt = {};
  Set<String> kept = {};
  bool firstRun = false;
}

class SyncEngine {
  SyncEngine({
    required this.local,
    required this.remote,
    this.storageLimit = 950 * 1024 * 1024,
    this.mergeChunk = 400,
    this.massDeleteFloor = 3,
    this.massDeleteShare = 0.25,
    this.transfers = 3,
    this.onDemand = false,
    this.onProgress,
    this.onLocalChange,
    this.onRemote,
  });

  final SyncLocal local;
  final SyncRemote remote;

  /// Bytes of book files the remote may hold (Supabase's free plan has
  /// 1 GB of storage).
  final int storageLimit;

  /// Translations sent per request.
  final int mergeChunk;

  /// More than this many books, and more than this share of the books
  /// this device had, missing at once: not a deletion (see [_deletions]).
  final int massDeleteFloor;
  final double massDeleteShare;

  /// Book files moved at once.
  final int transfers;

  /// This device keeps only the books it was asked for ([fetchBook]): a
  /// run brings no file, and a file missing here deletes nothing.
  final bool onDemand;

  /// The library as the remote lists it, as a run learns it (at its start
  /// and again when it ends).
  final void Function(RemoteLibrary library)? onRemote;

  /// Where the run is (for a progress bar or notification).
  final void Function(SyncProgress progress)? onProgress;

  /// A book came or went here (the library refreshes).
  final void Function()? onLocalChange;

  /// Runs everything; [quick] leaves book files alone (positions,
  /// translations and glossaries only - the run while reading).
  Future<SyncReport> run({bool quick = false}) async {
    final report = SyncReport();
    onProgress?.call(const SyncProgress(SyncStage.checking));
    final here = await _localBooks();
    final there =
        quick ? null : {for (final b in await remote.books()) b.md5: b};
    final seen = (await local.state('seen:'))
        .keys
        .map((k) => k.substring('seen:'.length))
        .toSet();
    if (there != null) await _deletions(here, there, seen, report);

    final run = await _load(report);
    if (there != null) _tell(there, run);
    for (final MapEntry(key: md5, value: book) in here.entries) {
      await _position(md5, book, run);
      await _glossary(md5, book, run);
    }
    await _translations(here, run);

    if (there != null) {
      await _transfers(here, there, seen, run);
      await _covers(here, there, run);
      await _settings(report);
      _tell(there, run);
    }
    if (run.firstRun) await local.setState('trinit', '1');
    return report;
  }

  void _tell(Map<String, RemoteBook> there, _Run run) {
    final tell = onRemote;
    if (tell == null) return;
    final translated = <String, Map<String, int>>{};
    for (final t in run.translations.values) {
      final byLang = translated[t.md5] ??= {};
      // The fuller of a language's two styles.
      byLang[t.lang] = math.max(byLang[t.lang] ?? 0, t.count);
    }
    tell(RemoteLibrary(
      books: [
        for (final b in there.values)
          if (b.hasFile && !b.deleted) b,
      ],
      progress: Map.of(run.progress),
      translated: translated,
    ));
  }

  /// Only the shared settings (one was changed here).
  Future<SyncReport> runSettings() async {
    final report = SyncReport();
    await _settings(report);
    return report;
  }

  /// Fetches one book the remote has and this device does not (the web,
  /// when it is opened), with its position, translations and glossary.
  /// The book as it is here, or null when it could not be added.
  Future<LocalBook?> fetchBook(RemoteBook remoteBook,
      {void Function(int received, int? total)? onProgress}) async {
    for (final MapEntry(key: md5, value: book)
        in (await _localBooks()).entries) {
      if (md5 == remoteBook.md5) return book;
    }
    final bytes = await remote.downloadBook(remoteBook.md5, remoteBook.format,
        onProgress: onProgress);
    final added = await local.addBook(remoteBook, bytes);
    if (added == null) return null;
    await local.setState('seen:${remoteBook.md5}', '1');
    final run = await _load(SyncReport());
    await _position(remoteBook.md5, added, run);
    await _glossary(remoteBook.md5, added, run);
    await _translations({remoteBook.md5: added}, run, quiet: true);
    onLocalChange?.call();
    return added;
  }

  /// Deletes the book everywhere: here, and on the remote (the other
  /// devices follow at their next run).
  Future<void> deleteBook(String md5) async {
    final book = (await _localBooks())[md5];
    if (book != null) await local.removeBook(book);
    await local.setState('seen:$md5', null);
    RemoteBook? row;
    for (final b in await remote.books()) {
      if (b.md5 == md5) row = b;
    }
    if (row != null && !row.deleted) {
      await remote.markDeleted(md5);
      await remote.removeBookFile(md5, row.format);
    }
    if (book != null) onLocalChange?.call();
  }

  /// Removes this device's copy of a book the remote keeps (the web
  /// freeing space): what was read and translated goes up first. False
  /// when the remote does not have the file (it would be lost).
  Future<bool> dropLocalCopy(String md5) async {
    final book = (await _localBooks())[md5];
    if (book == null) return true;
    RemoteBook? row;
    for (final b in await remote.books()) {
      if (b.md5 == md5) row = b;
    }
    if (row == null || row.deleted || !row.hasFile) return false;
    final run = await _load(SyncReport());
    await _position(md5, book, run);
    await _glossary(md5, book, run);
    await _translations({md5: book}, run, quiet: true);
    if (run.report.errors.isNotEmpty) return false;
    await local.removeBook(book);
    await local.setState('seen:$md5', null);
    onLocalChange?.call();
    return true;
  }

  /// Brings one book up to date both ways (when it is opened): its
  /// position, translations and glossary. Null when the book is not here.
  Future<SyncReport?> runBook(String fileName) async {
    final report = SyncReport();
    LocalBook? book;
    for (final b in await local.books()) {
      if (b.fileName == fileName) book = b;
    }
    if (book == null) return null;
    final md5 = await local.md5Of(book);
    if (md5 == null) return null;
    final run = await _load(report);
    await _position(md5, book, run);
    await _glossary(md5, book, run);
    await _translations({md5: book}, run);
    return report;
  }

  Future<_Run> _load(SyncReport report) async {
    final run = _Run(report);
    final results = await Future.wait([
      remote.progress(),
      remote.translationIndex(),
      remote.glossaryIndex(),
    ]);
    run.progress = {
      for (final p in results[0] as List<RemoteProgress>) p.md5: p,
    };
    run.translations = {
      for (final t in results[1] as List<RemoteTranslations>) t.key: t,
    };
    run.glossaries = results[2] as Map<String, DateTime>;
    run.positionStamps = await local.state('pos:');
    run.positionSent = await local.state('posSent:');
    run.glossaryStamps = await local.state('gls:');
    run.glossarySent = await local.state('glsSent:');
    run.fractions = await local.state('frac:');
    run.dirty = await local.state('trdirty:');
    run.seenAt = await local.state('trseen:');
    run.firstRun = (await local.state('trinit')).isEmpty;
    run.kept = await local.translationPaths();
    return run;
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

  Future<void> _deletions(
      Map<String, LocalBook> here,
      Map<String, RemoteBook> there,
      Set<String> seen,
      SyncReport report) async {
    // Deleted elsewhere: removed here.
    for (final MapEntry(key: md5, value: book) in here.entries.toList()) {
      final remoteBook = there[md5];
      if (remoteBook == null || !remoteBook.deleted || !seen.contains(md5)) {
        continue;
      }
      try {
        await local.removeBook(book);
        here.remove(md5);
        seen.remove(md5);
        await local.setState('seen:$md5', null);
        report.removedHere++;
        onLocalChange?.call();
      } catch (e) {
        report.errors.add('book ${book.fileName}: $e');
      }
    }

    // A device that keeps only some books deletes by being asked to.
    if (onDemand) return;

    // Gone from here: deleted there - unless many went at once (a book
    // folder that moved or could not be read empties the library without
    // anyone deleting a book): then nothing is deleted.
    final gone = [
      for (final b in there.values)
        if (!b.deleted &&
            b.hasFile &&
            !here.containsKey(b.md5) &&
            seen.contains(b.md5))
          b,
    ];
    if (gone.length > massDeleteFloor &&
        gone.length > seen.length * massDeleteShare) {
      report.deletesHeld = gone.length;
      return;
    }
    for (final remoteBook in gone) {
      try {
        await remote.markDeleted(remoteBook.md5);
        await remote.removeBookFile(remoteBook.md5, remoteBook.format);
        there[remoteBook.md5] = RemoteBook(
            md5: remoteBook.md5,
            bookId: remoteBook.bookId,
            fileName: remoteBook.fileName,
            title: remoteBook.title,
            deleted: true);
        seen.remove(remoteBook.md5);
        await local.setState('seen:${remoteBook.md5}', null);
        report.removedThere++;
      } catch (e) {
        report.errors.add('book ${remoteBook.fileName}: $e');
      }
    }
  }

  /// Book files: this device's that the remote lacks go up, the remote's
  /// that this device lacks come down (with their position, translations
  /// and glossary), [transfers] at a time.
  Future<void> _transfers(Map<String, LocalBook> here,
      Map<String, RemoteBook> there, Set<String> seen, _Run run) async {
    final report = run.report;
    var used = 0;
    for (final b in there.values) {
      if (b.hasFile && !b.deleted) used += b.sizeBytes ?? 0;
    }
    final uploads = <MapEntry<String, LocalBook>>[];
    for (final entry in here.entries) {
      final remoteBook = there[entry.key];
      if (remoteBook == null || !remoteBook.hasFile || remoteBook.deleted) {
        uploads.add(entry);
      } else if (!seen.contains(entry.key)) {
        await local.setState('seen:${entry.key}', '1');
      }
    }
    final downloads = [
      for (final b in there.values)
        if (!onDemand &&
            !b.deleted &&
            b.hasFile &&
            !here.containsKey(b.md5) &&
            // Held back above (many missing at once): not fetched again.
            !seen.contains(b.md5))
          b,
    ];

    var done = 0;
    await _pool(uploads, (entry) async {
      final MapEntry(key: md5, value: book) = entry;
      onProgress?.call(SyncProgress(SyncStage.uploading,
          done: done, total: uploads.length, title: book.title));
      try {
        final bytes = await local.readBook(book);
        if (bytes == null) return;
        if (used + bytes.length > storageLimit) {
          report.skippedForSpace++;
          return;
        }
        used += bytes.length;
        await remote.uploadBook(md5, 'epub', bytes);
        final row = RemoteBook(
          md5: md5,
          bookId: book.id,
          fileName: book.fileName,
          title: book.title,
          author: book.author,
          sizeBytes: bytes.length,
          hasFile: true,
          publisher: book.publisher,
          description: book.description ?? '',
          addedAt: DateTime.now().toUtc(),
        );
        await remote.putBook(row);
        there[md5] = row;
        await local.setState('seen:$md5', '1');
        report.uploaded++;
      } catch (e) {
        report.errors.add('book ${book.fileName}: $e');
      } finally {
        done++;
      }
    });

    done = 0;
    await _pool(downloads, (remoteBook) async {
      onProgress?.call(SyncProgress(SyncStage.downloading,
          done: done, total: downloads.length, title: remoteBook.title));
      try {
        final bytes =
            await remote.downloadBook(remoteBook.md5, remoteBook.format);
        final added = await local.addBook(remoteBook, bytes);
        if (added == null) return;
        here[remoteBook.md5] = added;
        await local.setState('seen:${remoteBook.md5}', '1');
        report.downloaded++;
        // The book is whole when it shows up: where it was read, what was
        // translated, its names.
        await _position(remoteBook.md5, added, run);
        await _glossary(remoteBook.md5, added, run);
        await _translations({remoteBook.md5: added}, run, quiet: true);
        onLocalChange?.call();
      } catch (e) {
        report.errors.add('book ${remoteBook.fileName}: $e');
      } finally {
        done++;
      }
    });
    if (uploads.isNotEmpty || downloads.isNotEmpty) {
      final last =
          downloads.isNotEmpty ? SyncStage.downloading : SyncStage.uploading;
      final total = downloads.isNotEmpty ? downloads.length : uploads.length;
      onProgress?.call(SyncProgress(last, done: total, total: total));
    }
  }

  /// What another device's library shows of each book here: its details
  /// (rows put by a version that sent none) and a small cover.
  Future<void> _covers(Map<String, LocalBook> here,
      Map<String, RemoteBook> there, _Run run) async {
    for (final MapEntry(key: md5, value: book) in here.entries) {
      var row = there[md5];
      if (row == null || row.deleted || !row.hasFile) continue;
      try {
        if (row.description == null) {
          row = row.copyWith(
              publisher: book.publisher, description: book.description ?? '');
          await remote.putBook(row);
          there[md5] = row;
        }
        if (!row.hasCover) {
          final jpeg = await local.coverThumbnail(book);
          if (jpeg == null) continue;
          await remote.uploadCover(md5, jpeg);
          there[md5] = row.copyWith(hasCover: true);
          run.report.coversSent++;
        }
      } catch (e) {
        run.report.errors.add('cover ${book.fileName}: $e');
      }
    }
  }

  /// The shared settings: the newer side wins, by the clock of the device
  /// that changed it; one set before sync existed goes up only where the
  /// remote has none.
  Future<void> _settings(SyncReport report) async {
    final List<String> names;
    try {
      names = await local.syncedSettings();
    } catch (e) {
      report.errors.add('settings: $e');
      return;
    }
    if (names.isEmpty) return;
    try {
      final theirs = await remote.settings();
      final stamps = await local.state('set:');
      final sent = await local.state('setSent:');
      for (final name in names) {
        final remoteSetting = theirs[name];
        final remoteAt = remoteSetting?.updatedAt;
        final localMs = int.tryParse(stamps['set:$name'] ?? '');
        final sentMs = int.tryParse(sent['setSent:$name'] ?? '');
        Future<void> take() async {
          await local.applySetting(name, remoteSetting!.value);
          final ms = '${remoteAt!.millisecondsSinceEpoch}';
          await local.setState('set:$name', ms);
          await local.setState('setSent:$name', ms);
          report.settingsReceived++;
        }

        Future<void> send(DateTime at, {bool evenEmpty = false}) async {
          final value = await local.setting(name);
          if (value.isEmpty && !evenEmpty) return;
          await remote.putSetting(name, value, at, device: local.device);
          final ms = '${at.millisecondsSinceEpoch}';
          await local.setState('set:$name', ms);
          await local.setState('setSent:$name', ms);
          report.settingsSent++;
        }

        if (localMs == null) {
          if (remoteSetting != null) {
            await take();
          } else {
            await send(unknownAge);
          }
          continue;
        }
        final localAt =
            DateTime.fromMillisecondsSinceEpoch(localMs, isUtc: true);
        final unsent = sentMs == null || localMs > sentMs;
        if (unsent && (remoteAt == null || localAt.isAfter(remoteAt))) {
          // A key taken away here is taken away everywhere.
          await send(localAt, evenEmpty: true);
        } else if (remoteAt != null && remoteAt.isAfter(localAt)) {
          await take();
        }
      }
    } catch (e) {
      report.errors.add('settings: $e');
    }
  }

  Future<void> _pool<T>(
      List<T> items, Future<void> Function(T item) task) async {
    var next = 0;
    Future<void> worker() async {
      while (next < items.length) {
        await task(items[next++]);
      }
    }

    await Future.wait([
      for (var i = 0; i < math.min(transfers, items.length); i++) worker(),
    ]);
  }

  Future<void> _position(String md5, LocalBook book, _Run run) async {
    final report = run.report;
    try {
      final localMs =
          int.tryParse(run.positionStamps['pos:${book.fileName}'] ?? '');
      final sentMs =
          int.tryParse(run.positionSent['posSent:${book.fileName}'] ?? '');
      final theirs = run.progress[md5];
      final remoteAt = theirs?.updatedAt;
      double? fraction() {
        final f = double.tryParse(run.fractions['frac:${book.fileName}'] ?? '');
        return f == null || f.isNaN ? null : f.clamp(0, 1).toDouble();
      }

      Future<void> take() async {
        await local.applyPosition(
            book.fileName, theirs!.position, theirs.completed, remoteAt!);
        final f = theirs.fraction;
        await local.setState('frac:${book.fileName}', f == null ? null : '$f');
        if (f == null) {
          run.fractions.remove('frac:${book.fileName}');
        } else {
          run.fractions['frac:${book.fileName}'] = '$f';
        }
        _stampPosition(book.fileName, remoteAt, run);
        report.positionsReceived++;
      }

      if (localMs == null) {
        if (theirs != null) {
          await take();
          return;
        }
        // Saved before sync existed: up, as older than anything else.
        final row = await local.position(book.fileName);
        if (row == null || (row.position.isEmpty && !row.completed)) return;
        final mine = RemoteProgress(
            md5: md5,
            position: row.position,
            completed: row.completed,
            updatedAt: unknownAge,
            fraction: fraction());
        await remote.putProgress(mine, device: local.device);
        run.progress[md5] = mine;
        await _markPositionSent(book.fileName, unknownAge, run);
        report.positionsSent++;
        return;
      }
      final localAt = DateTime.fromMillisecondsSinceEpoch(localMs, isUtc: true);
      final unsent = sentMs == null || localMs > sentMs;
      if (unsent && (remoteAt == null || localAt.isAfter(remoteAt))) {
        final row = await local.position(book.fileName);
        if (row == null) return;
        final mine = RemoteProgress(
          md5: md5,
          position: row.position,
          completed: row.completed,
          updatedAt: localAt,
          fraction: fraction(),
        );
        await remote.putProgress(mine, device: local.device);
        run.progress[md5] = mine;
        await local.setState('posSent:${book.fileName}', '$localMs');
        run.positionSent['posSent:${book.fileName}'] = '$localMs';
        report.positionsSent++;
      } else if (remoteAt != null && remoteAt.isAfter(localAt)) {
        await take();
      }
    } catch (e) {
      report.errors.add('position ${book.fileName}: $e');
    }
  }

  void _stampPosition(String fileName, DateTime at, _Run run) {
    final ms = '${at.millisecondsSinceEpoch}';
    run.positionStamps['pos:$fileName'] = ms;
    run.positionSent['posSent:$fileName'] = ms;
  }

  Future<void> _markPositionSent(String fileName, DateTime at, _Run run) async {
    final ms = '${at.millisecondsSinceEpoch}';
    await local.setState('pos:$fileName', ms);
    await local.setState('posSent:$fileName', ms);
    _stampPosition(fileName, at, run);
  }

  Future<void> _glossary(String md5, LocalBook book, _Run run) async {
    final report = run.report;
    final file = book.fileName;
    try {
      final localMs = int.tryParse(run.glossaryStamps['gls:$file'] ?? '');
      final sentMs = int.tryParse(run.glossarySent['glsSent:$file'] ?? '');
      final remoteAt = run.glossaries[md5];
      Future<void> take() async {
        final data = await remote.glossary(md5);
        if (data == null) return;
        await local.applyGlossary(file, data, remoteAt!);
        final ms = '${remoteAt.millisecondsSinceEpoch}';
        run.glossaryStamps['gls:$file'] = ms;
        run.glossarySent['glsSent:$file'] = ms;
        report.glossariesReceived++;
      }

      Future<void> send(DateTime at) async {
        final data = await local.glossary(file);
        if (data == null) return;
        await remote.putGlossary(md5, data, at, device: local.device);
        final ms = '${at.millisecondsSinceEpoch}';
        await local.setState('gls:$file', ms);
        await local.setState('glsSent:$file', ms);
        run.glossaryStamps['gls:$file'] = ms;
        run.glossarySent['glsSent:$file'] = ms;
        report.glossariesSent++;
      }

      if (localMs == null) {
        if (remoteAt != null) {
          await take();
          return;
        }
        // Made before sync existed: up, as older than anything else.
        await send(unknownAge);
        return;
      }
      final localAt = DateTime.fromMillisecondsSinceEpoch(localMs, isUtc: true);
      final unsent = sentMs == null || localMs > sentMs;
      if (unsent && (remoteAt == null || localAt.isAfter(remoteAt))) {
        await send(localAt);
      } else if (remoteAt != null && remoteAt.isAfter(localAt)) {
        await take();
      }
    } catch (e) {
      report.errors.add('glossary $file: $e');
    }
  }

  /// Translations of [books] both ways; [quiet] reports no progress (a
  /// book being fetched already does).
  Future<void> _translations(Map<String, LocalBook> books, _Run run,
      {bool quiet = false}) async {
    final report = run.report;
    final work = <({
      String md5,
      LocalBook book,
      String lang,
      String style,
      String path
    })>[];
    for (final MapEntry(key: md5, value: book) in books.entries) {
      for (final lang in local.translationLanguages) {
        for (final style in local.translationStyles) {
          final key = translationsKey(md5, lang, style);
          final info = run.translations[key];
          final path = await local.translationPath(book.fileName, lang, style);
          final localChanged = run.dirty.containsKey('trdirty:$path') ||
              (run.firstRun && run.kept.contains(path));
          final remoteChanged = info != null &&
              run.seenAt['trseen:$key'] != info.updatedAt.toIso8601String();
          if (localChanged || remoteChanged) {
            work.add((
              md5: md5,
              book: book,
              lang: lang,
              style: style,
              path: path,
            ));
          }
        }
      }
    }
    for (var i = 0; i < work.length; i++) {
      final w = work[i];
      if (!quiet) {
        onProgress?.call(SyncProgress(SyncStage.translations,
            done: i, total: work.length, title: w.book.title));
      }
      final key = translationsKey(w.md5, w.lang, w.style);
      final info = run.translations[key];
      try {
        final set =
            await local.openTranslations(w.book.fileName, w.lang, w.style);
        final theirs = info == null
            ? const <String, String>{}
            : await remote.translationEntries(w.md5, w.lang, w.style);
        report.translationsReceived += set.absorb(theirs);
        final delta = <String, String>{
          for (final MapEntry(:key, :value) in set.entries.entries)
            if (theirs[key] != value) key: value,
        };
        var latest = info?.updatedAt;
        final keys = delta.keys.toList();
        for (var j = 0; j < keys.length; j += mergeChunk) {
          final part = {
            for (final k in keys.skip(j).take(mergeChunk)) k: delta[k]!,
          };
          latest =
              (await remote.mergeTranslations(w.md5, w.lang, w.style, part))
                  .updatedAt;
        }
        report.translationsSent += delta.length;
        await set.save();
        // Only the change seen at the start is done; a newer one (the
        // reader went on translating) waits for the next run.
        final stamp = run.dirty['trdirty:${w.path}'];
        final now =
            (await local.state('trdirty:${w.path}'))['trdirty:${w.path}'];
        if (now == stamp) await local.setState('trdirty:${w.path}', null);
        run.dirty.remove('trdirty:${w.path}');
        if (latest != null) {
          await local.setState('trseen:$key', latest.toIso8601String());
          run.seenAt['trseen:$key'] = latest.toIso8601String();
          if (info != null) {
            run.translations[key] = RemoteTranslations(
                md5: w.md5,
                lang: w.lang,
                style: w.style,
                count: info.count,
                updatedAt: latest);
          }
        }
      } catch (e) {
        report.errors.add('translations ${w.book.fileName} ${w.lang}: $e');
      }
    }
    if (!quiet && work.isNotEmpty) {
      onProgress?.call(SyncProgress(SyncStage.translations,
          done: work.length, total: work.length));
    }
  }
}
