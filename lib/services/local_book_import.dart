// Adding EPUB and PDF files from the device to the library.

// Dart imports:
import 'dart:io';
import 'dart:isolate';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:crypto/crypto.dart';
import 'package:epubx/epubx.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// Project imports:
import 'package:openlib/services/book_covers.dart';
import 'package:openlib/services/cover_thumbs.dart';
import 'package:openlib/services/database.dart';
import 'package:openlib/services/files.dart' show generateBookFileName;
import 'package:openlib/services/heavy_work.dart';
import 'package:openlib/services/logger.dart';
import 'package:openlib/services/storage/app_files.dart';

/// Formats the reader can open from the library.
const importableBookExtensions = ['epub', 'pdf'];

/// Library id prefix for imported books. Their id is not an md5 the
/// shadow libraries know, so "open in site" stays disabled for them.
const localBookIdPrefix = 'local_';

enum LocalImportOutcome { imported, alreadyInLibrary, failed }

@immutable
class LocalImportResult {
  final String path;
  final LocalImportOutcome outcome;
  final String? title;
  final String? error;

  const LocalImportResult(this.path, this.outcome, {this.title, this.error});
}

/// What could be read out of an EPUB without the UI isolate.
@immutable
class EpubFileMetadata {
  final String? title;
  final String? author;
  final String? publisher;
  final String? description;
  final String? language;

  /// The cover at full quality (see [epubCover]).
  final CoverImage? cover;

  const EpubFileMetadata({
    this.title,
    this.author,
    this.publisher,
    this.description,
    this.language,
    this.cover,
  });
}

/// Reads title, author, publisher, description, language and the cover
/// from EPUB [bytes]. Never throws: a field that cannot be read is left
/// null.
Future<EpubFileMetadata> readEpubMetadata(List<int> bytes) async {
  try {
    final book = await EpubReader.openBook(bytes);
    final meta = book.Schema?.Package?.Metadata;
    String? clean(String? s) {
      final t = s?.replaceAll(RegExp(r'\s+'), ' ').trim();
      return (t == null || t.isEmpty) ? null : t;
    }

    // The original image file; epubx's reader only knows the EPUB 2
    // cover meta, and decodes the picture.
    var cover = epubCover(Uint8List.fromList(bytes));
    if (cover == null) {
      try {
        final image = await book.readCover();
        if (image != null) {
          cover = CoverImage(
              Uint8List.fromList(img.encodeJpg(image, quality: 92)), 'jpg');
        }
      } catch (_) {}
    }

    final description =
        clean(meta?.Description?.replaceAll(RegExp(r'<[^>]+>'), ' '));
    return EpubFileMetadata(
      title: clean(book.Title),
      author: clean(book.Author),
      publisher: clean((meta?.Publishers ?? const []).join(', ')),
      description: description,
      language: clean((meta?.Languages ?? const []).firstOrNull),
      cover: cover,
    );
  } catch (_) {
    return const EpubFileMetadata();
  }
}

/// MD5 of a file, off the UI isolate.
Future<String> md5OfFile(String path) => Isolate.run(
    () async => (await md5.bind(File(path).openRead()).first).toString());

/// [readEpubMetadata] for a file, off the UI isolate.
Future<EpubFileMetadata> readEpubMetadataOfFile(String path) =>
    Isolate.run(() async => readEpubMetadata(await File(path).readAsBytes()));

String _formatSize(int bytes) {
  if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
  return '${(bytes / 1024).toStringAsFixed(0)} KB';
}

/// Copies each file into the book storage folder and adds it to the
/// library. A file already in the library (same content) is skipped.
class LocalBookImporter {
  LocalBookImporter({
    MyLibraryDb? database,
    Future<Directory> Function()? coversDirectory,
  })  : _db = database ?? MyLibraryDb.instance,
        _coversDirectory = coversDirectory ?? _defaultCoversDirectory;

  final MyLibraryDb _db;
  final Future<Directory> Function() _coversDirectory;
  final AppLogger _logger = AppLogger();

  static Future<Directory> _defaultCoversDirectory() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'covers'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<List<LocalImportResult>> importAll(List<String> paths) async {
    final results = <LocalImportResult>[];
    for (final path in paths) {
      results.add(await importOne(path));
    }
    return results;
  }

  Future<LocalImportResult> importOne(String sourcePath) async {
    final ext = p.extension(sourcePath).replaceFirst('.', '').toLowerCase();
    if (!importableBookExtensions.contains(ext)) {
      return LocalImportResult(sourcePath, LocalImportOutcome.failed,
          error: 'Unsupported file type: .$ext');
    }
    try {
      final source = File(sourcePath);
      final size = await source.length();
      final md5Hex = await md5OfFile(sourcePath);
      final id = '$localBookIdPrefix$md5Hex';
      if (await _db.checkIdExists(id)) {
        final existing = await _db.getId(id);
        return LocalImportResult(
            sourcePath, LocalImportOutcome.alreadyInLibrary,
            title: existing?.title);
      }

      var meta = const EpubFileMetadata();
      if (ext == 'epub') {
        meta = await readEpubMetadataOfFile(sourcePath);
      }
      final title = meta.title ?? p.basenameWithoutExtension(sourcePath);

      final storage =
          (await _db.getPreference('bookStorageDirectory')).toString();
      var fileName = generateBookFileName(
          title: title, author: meta.author, format: ext, md5: md5Hex);
      if (await File(p.join(storage, fileName)).exists()) {
        // Same name, different content: keep both.
        fileName = '${p.basenameWithoutExtension(fileName)}_'
            '${md5Hex.substring(0, 8)}.$ext';
      }
      await source.copy(p.join(storage, fileName));

      String thumbnail = '';
      final cover = meta.cover;
      if (cover != null) {
        final covers = await _coversDirectory();
        final coverFile = File(
            p.join(covers.path, BookCovers.fileNameFor(id, cover.extension)));
        await coverFile.writeAsBytes(cover.bytes);
        thumbnail = coverFile.path;
      }

      await _db.insert(MyBook(
        id: id,
        title: title,
        author: meta.author ?? 'Unknown',
        thumbnail: thumbnail,
        link: '',
        publisher: meta.publisher ?? '',
        info: [
          ext.toUpperCase(),
          _formatSize(size),
          if (meta.language != null) meta.language!,
        ].join(', '),
        format: ext,
        description: meta.description ?? '',
        fileName: fileName,
      ));
      _logger.info('Imported local book',
          tag: 'LocalBookImport', metadata: {'fileName': fileName});
      return LocalImportResult(sourcePath, LocalImportOutcome.imported,
          title: title);
    } catch (e) {
      _logger.warning('Local book import failed',
          tag: 'LocalBookImport', error: e);
      return LocalImportResult(sourcePath, LocalImportOutcome.failed,
          error: e.toString());
    }
  }
}

/// The MD5 a library id already carries: an Anna's Archive id is the
/// file's MD5, an imported book's id is [localBookIdPrefix] + its MD5.
/// Null for other ids.
String? md5FromBookId(String id) {
  final m = RegExp('^(?:$localBookIdPrefix)?([0-9a-f]{32})\$')
      .firstMatch(id.toLowerCase());
  return m?.group(1);
}

/// Adds a book given as bytes - a file picked in the browser, a book
/// another device synced - to the library: the file goes to the book
/// folder ([AppFiles], so IndexedDB on the web), the cover next to the
/// app's other covers. [id], [fileName], [title] and [author] keep what
/// another device called the book.
Future<LocalImportResult> importBookBytes(
  String name,
  Uint8List bytes, {
  String? id,
  String? fileName,
  String? title,
  String? author,
  MyLibraryDb? database,
}) async {
  final db = database ?? MyLibraryDb.instance;
  final files = AppFiles.instance;
  final ext = p.extension(fileName ?? name).replaceFirst('.', '').toLowerCase();
  if (!importableBookExtensions.contains(ext)) {
    return LocalImportResult(name, LocalImportOutcome.failed,
        error: 'Unsupported file type: .$ext');
  }
  try {
    final md5Hex = md5.convert(bytes).toString();
    final bookId = id ?? '$localBookIdPrefix$md5Hex';
    if (await db.checkIdExists(bookId)) {
      final existing = await db.getId(bookId);
      return LocalImportResult(name, LocalImportOutcome.alreadyInLibrary,
          title: existing?.title);
    }
    final meta = ext == 'epub'
        ? await runHeavy(() => readEpubMetadata(bytes))
        : const EpubFileMetadata();
    final bookTitle = title ?? meta.title ?? p.basenameWithoutExtension(name);
    final storage = (await db.getPreference('bookStorageDirectory')).toString();
    var target = fileName ??
        generateBookFileName(
            title: bookTitle,
            author: author ?? meta.author,
            format: ext,
            md5: md5Hex);
    if (await files.exists(p.join(storage, target))) {
      // Same name, different content: keep both.
      target = '${p.basenameWithoutExtension(target)}_'
          '${md5Hex.substring(0, 8)}.$ext';
    }
    await files.writeBytes(p.join(storage, target), bytes);
    await db.setSyncState('md5:$target', md5Hex);

    var thumbnail = '';
    final cover = meta.cover;
    if (cover != null && kIsWeb) {
      // The web draws small covers only (and other devices' libraries
      // get the same one).
      final small = await CoverThumbs.jpeg(cover.bytes);
      if (small != null) {
        await CoverThumbs.write(md5Hex, small);
        thumbnail = await CoverThumbs.path(md5Hex);
      }
    } else if (cover != null) {
      thumbnail = p.join(await files.supportPath(), 'covers',
          BookCovers.fileNameFor(bookId, cover.extension));
      await files.writeBytes(thumbnail, cover.bytes);
    }

    await db.insert(MyBook(
      id: bookId,
      title: bookTitle,
      author: author ?? meta.author ?? 'Unknown',
      thumbnail: thumbnail,
      link: '',
      publisher: meta.publisher ?? '',
      info: [
        ext.toUpperCase(),
        _formatSize(bytes.length),
        if (meta.language != null) meta.language!,
      ].join(', '),
      format: ext,
      description: meta.description ?? '',
      fileName: target,
    ));
    return LocalImportResult(name, LocalImportOutcome.imported,
        title: bookTitle);
  } catch (e) {
    AppLogger().warning('Book import failed', tag: 'LocalBookImport', error: e);
    return LocalImportResult(name, LocalImportOutcome.failed,
        error: e.toString());
  }
}

/// Whether [thumbnail] is a file on the device rather than a URL.
bool isLocalImagePath(String? thumbnail) {
  if (thumbnail == null || thumbnail.isEmpty) return false;
  return thumbnail.startsWith('/') ||
      thumbnail.startsWith('file://') ||
      RegExp(r'^[A-Za-z]:[\\/]').hasMatch(thumbnail);
}

String localImageFilePath(String thumbnail) => thumbnail.startsWith('file://')
    ? Uri.parse(thumbnail).toFilePath()
    : thumbnail;
