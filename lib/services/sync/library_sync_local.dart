// SyncLocal on this device's library: the books database, the book folder
// (AppFiles - files on devices, IndexedDB on the web) and the saved
// translations (TranslationCache).

// Dart imports:
import 'dart:typed_data';

// Package imports:
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/files.dart' show deleteFile;
import 'package:openlib/services/heavy_work.dart';
import 'package:openlib/services/local_book_import.dart';
import 'package:openlib/services/platform_utils.dart';
import 'package:openlib/services/storage/app_files.dart';
import 'package:openlib/services/sync/sync_engine.dart';
import 'package:openlib/services/translation/glossary_service.dart';
import 'package:openlib/services/translation/translation_cache.dart';
import 'package:openlib/services/translation/translation_engine.dart';

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
