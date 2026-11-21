// SyncLocal on this device's library: the books database, the book folder
// (AppFiles - files on devices, IndexedDB on the web) and the saved
// translations (TranslationCache).

// Dart imports:
import 'dart:typed_data';

// Package imports:
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

// Project imports:
import 'package:openlib/services/book_covers.dart';
import 'package:openlib/services/cover_thumbs.dart';
import 'package:openlib/services/database.dart';
import 'package:openlib/services/files.dart' show deleteFile;
import 'package:openlib/services/heavy_work.dart';
import 'package:openlib/services/local_book_import.dart';
import 'package:openlib/services/platform_utils.dart';
import 'package:openlib/services/storage/app_files.dart';
import 'package:openlib/services/sync/series_sync.dart';
import 'package:openlib/services/sync/sync_engine.dart';
import 'package:openlib/services/translation/claude/claude_settings.dart';
import 'package:openlib/services/translation/gemini/gemini_settings.dart';
import 'package:openlib/services/translation/glossary_service.dart';
import 'package:openlib/services/translation/translation_cache.dart';
import 'package:openlib/services/translation/translation_engine.dart';

/// Preference: the Gemini key is shared with the owner's other devices
/// (1, the default) or kept on this one (0).
const syncGeminiKeyPref = 'syncGeminiKey';

/// The shared setting that carries the Gemini key.
const geminiKeySetting = 'gemini_api_key';

/// Preference: the Claude key is shared with the owner's other devices
/// (1, the default) or kept on this one (0).
const syncClaudeKeyPref = 'syncClaudeKey';

/// The shared setting that carries the Claude key and its workspace.
const claudeKeySetting = 'claude_api_key';

class LibrarySyncLocal implements SyncLocal {
  LibrarySyncLocal({MyLibraryDb? database})
      : _db = database ?? MyLibraryDb.instance;

  final MyLibraryDb _db;
  AppFiles get _files => AppFiles.instance;

  @override
  String get device => PlatformUtils.isWeb ? 'web' : 'android';

  Future<String> _storage() async =>
      (await _db.getPreference('bookStorageDirectory')).toString();

  @override
  Future<List<LocalBook>> books() async => [
        for (final b in await _db.getAll())
          LocalBook(
            id: b.id,
            fileName: b.getFileName(),
            title: b.title,
            author: b.author,
            format: (b.format ?? '').toLowerCase(),
            publisher: b.publisher,
            description: b.description,
          ),
      ];

  @override
  Future<String?> md5Of(LocalBook book) async {
    final fromId = md5FromBookId(book.id);
    if (fromId != null) return fromId;
    final known = await _db.getSyncState('md5:${book.fileName}');
    if (known != null) return known;
    final bytes = await readBook(book);
    if (bytes == null) return null;
    final md5Hex = await runHeavy(() => md5.convert(bytes).toString());
    await _db.setSyncState('md5:${book.fileName}', md5Hex);
    return md5Hex;
  }

  @override
  Future<Uint8List?> readBook(LocalBook book) async =>
      _files.readBytes(p.join(await _storage(), book.fileName));

  @override
  Future<LocalBook?> addBook(RemoteBook book, Uint8List bytes) async {
    final result = await importBookBytes(
      book.fileName,
      bytes,
      id: book.bookId,
      fileName: book.fileName,
      title: book.title.isEmpty ? null : book.title,
      author: book.author,
      database: _db,
    );
    if (result.outcome == LocalImportOutcome.failed) {
      throw StateError(result.error ?? 'import failed');
    }
    final added = await _db.getId(book.bookId);
    if (added == null) return null;
    return LocalBook(
      id: added.id,
      fileName: added.getFileName(),
      title: added.title,
      author: added.author,
      format: (added.format ?? 'epub').toLowerCase(),
    );
  }

  @override
  Future<void> removeBook(LocalBook book) async {
    final row = await _db.getId(book.id);
    final thumb = row?.thumbnail ?? '';
    if (PlatformUtils.isWeb &&
        isLocalImagePath(thumb) &&
        !CoverThumbs.isThumb(thumb)) {
      // A full cover goes with the file; the small one stays for the
      // library (the book may still be on the remote).
      await _files.delete(localImageFilePath(thumb)).catchError((_) {});
    }
    await deleteFile(p.join(await _storage(), book.fileName));
    await TranslationCache.deleteForBook(book.fileName).catchError((_) {});
    await GlossaryService.instance.remove(book.fileName);
    await _db.delete(book.id);
    await _db.deleteBookState(book.fileName);
  }

  @override
  Future<({String position, bool completed})?> position(String fileName) =>
      _db.getBookRow(fileName);

  @override
  Future<void> applyPosition(
          String fileName, String position, bool completed, DateTime at) =>
      _db.applySyncedPosition(fileName, position, completed, at);

  @override
  Future<Map<String, String>> state(String prefix) => _db.getSyncStates(prefix);

  @override
  Future<void> setState(String name, String? value) =>
      _db.setSyncState(name, value);

  @override
  List<String> get translationLanguages => TranslationCache.languages;

  @override
  List<String> get translationStyles => [
        TranslationCache.sharedModelId(lightNovel: true),
        TranslationCache.sharedModelId(lightNovel: false),
      ];

  @override
  Future<String> translationPath(
          String fileName, String lang, String style) async =>
      p.normalize(p.join(await TranslationCache.folderPath(),
          '${TranslationCache.fileIdFor(fileName, lang, style)}.json'));

  @override
  Future<Set<String>> translationPaths() async =>
      (await _files.list(await TranslationCache.folderPath()))
          .map(p.normalize)
          .toSet();

  @override
  Future<LocalTranslations> openTranslations(
      String fileName, String lang, String style) async {
    final path = await translationPath(fileName, lang, style);
    final wasOpen = TranslationCache.isOpen(path);
    final cache = await TranslationCache.open(
      bookFileName: fileName,
      targetLanguage: lang,
      modelId: style,
      // What older versions kept per model joins the set when it is made
      // here first.
      mergeFrom: await TranslationEngines.legacyCacheIds(
          lightNovel:
              style == TranslationCache.sharedModelId(lightNovel: true)),
    );
    return _CacheSet(cache, keepOpen: wasOpen);
  }

  @override
  Future<String?> glossary(String fileName) =>
      GlossaryService.instance.savedText(fileName);

  @override
  Future<void> applyGlossary(String fileName, String data, DateTime at) async {
    await GlossaryService.instance.applySynced(fileName, data);
    final ms = '${at.millisecondsSinceEpoch}';
    await _db.setSyncState('gls:$fileName', ms);
    await _db.setSyncState('glsSent:$fileName', ms);
  }

  @override
  Future<Uint8List?> coverThumbnail(LocalBook book) async {
    // The web keeps each small cover (its library draws them).
    final md5 = PlatformUtils.isWeb ? await md5Of(book) : null;
    if (md5 != null) {
      final kept = await CoverThumbs.read(md5);
      if (kept != null) return kept;
    }
    final thumb = (await _db.getId(book.id))?.thumbnail ?? '';
    final bytes = isLocalImagePath(thumb)
        ? await _files.readBytes(localImageFilePath(thumb))
        : null;
    // A book downloaded in the app has a web address for a cover (the
    // catalog's), and nothing was sent for it: its own cover, out of its
    // file.
    final full = bytes ?? await _ownCover(book);
    if (full == null) return null;
    final jpeg = await CoverThumbs.jpeg(full);
    if (jpeg != null && md5 != null) await CoverThumbs.write(md5, jpeg);
    return jpeg;
  }

  /// The cover inside the book's file; a file found to have none is not
  /// opened for it again.
  Future<Uint8List?> _ownCover(LocalBook book) async {
    if (book.format != 'epub') return null;
    final mark = 'nocover:${book.fileName}';
    if (await _db.getSyncState(mark) != null) return null;
    final epub = await readBook(book);
    if (epub == null) return null;
    final cover = await _coverIn(epub);
    if (cover == null) await _db.setSyncState(mark, '1');
    return cover?.bytes;
  }

  static Future<CoverImage?> _coverIn(Uint8List epub) =>
      runHeavy(() => epubCover(epub));

  @override
  Future<List<String>> syncedSettings() async {
    Future<bool> on(String pref) async =>
        await _db.getPreference(pref).catchError((_) => null) != 0;
    // (Before the run reads when each setting changed: what the reader
    // did to the series here counts as changed now.)
    await _reconcileSeries();
    return [
      if (await on(syncGeminiKeyPref)) geminiKeySetting,
      if (await on(syncClaudeKeyPref)) claudeKeySetting,
      seriesSetting,
    ];
  }

  @override
  Future<String> setting(String name) async {
    switch (name) {
      case geminiKeySetting:
        await GeminiSettings.instance.load();
        return GeminiSettings.instance.apiKey;
      case claudeKeySetting:
        await ClaudeSettings.instance.load();
        return ClaudeSettings.instance.sharedValue;
      case seriesSetting:
        return encodeSeries(await _sharedSeries());
    }
    return '';
  }

  @override
  Future<void> applySetting(String name, String value) async {
    switch (name) {
      case geminiKeySetting:
        await GeminiSettings.instance.applySynced(value);
      case claudeKeySetting:
        await ClaudeSettings.instance.applySynced(value);
      case seriesSetting:
        await _reconcileSeries(theirs: decodeSeries(value));
    }
  }

  /// The series as the account has them, as far as this device knows.
  Future<Map<String, String>> _sharedSeries() async => decodeSeries(
      '${await _db.getPreference(seriesSharedPref).catchError((_) => null) ?? ''}');

  /// Brings the shared map and this device's books together. What the
  /// reader changed here since the last run is written into the map (and
  /// the setting counts as changed now); [theirs], when a run brought
  /// it, stands for every book it speaks of, and what only this device
  /// knew stays; then each book here is in the series the map says.
  Future<void> _reconcileSeries({Map<String, String>? theirs}) async {
    final shared = await _sharedSeries();
    final was = encodeSeries(shared);
    if (theirs != null) shared.addAll(theirs);
    final rows = await _db.getSeriesForAll();
    final marks = theirs != null
        ? const <String, String>{}
        : await _db.getSyncStates(MyLibraryDb.seriesChangeMark);
    final md5s = await _db.getSyncStates('md5:');
    var told = false;
    for (final book in await books()) {
      final marked =
          marks.containsKey('${MyLibraryDb.seriesChangeMark}${book.id}');
      final here = rows[book.id] ?? '';
      // (A file is read for its MD5 only for the reader's own change.)
      final md5 = md5FromBookId(book.id) ??
          md5s['md5:${book.fileName}'] ??
          (marked ? await md5Of(book) : null);
      if (md5 == null) continue;
      final known = shared[md5];
      if (marked) {
        if (known != here && (here.isNotEmpty || (known ?? '').isNotEmpty)) {
          shared[md5] = here;
          told = true;
        }
      } else if (known == null) {
        // Grouped before the devices shared this.
        if (here.isNotEmpty) {
          shared[md5] = here;
          told = true;
        }
      } else if (known != here) {
        await _db
            .setSeries([book.id], known.isEmpty ? null : known, fromSync: true);
      }
    }
    for (final mark in marks.keys) {
      await _db.setSyncState(mark, null);
    }
    final now = encodeSeries(shared);
    if (now != was) await _db.savePreference(seriesSharedPref, now);
    if (told) {
      await _db.setSyncState(
          'set:$seriesSetting', '${DateTime.now().millisecondsSinceEpoch}');
    }
  }
}

class _CacheSet implements LocalTranslations {
  _CacheSet(this._cache, {required this.keepOpen});
  final TranslationCache _cache;
  final bool keepOpen;

  @override
  Map<String, String> get entries => _cache.entries;

  @override
  int absorb(Map<String, String> other) => _cache.absorb(other);

  @override
  Future<void> save() async {
    await _cache.flush(quiet: true);
    if (!keepOpen) _cache.forget();
  }
}
