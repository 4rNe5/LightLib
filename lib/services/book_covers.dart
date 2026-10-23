// Covers at full quality, read straight out of each EPUB in the library.
//
// The cover image is found the way readers do (EPUB 3 cover-image, the
// EPUB 2 cover meta, the guide's cover page, the first page's picture)
// and kept as the original file - a JPEG is not decoded and squeezed into
// a small PNG - so the library grid is as sharp as the book. Only a very
// large or unusual image is re-encoded, once.

// Dart imports:
import 'dart:io';
import 'dart:isolate';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/epub_package.dart';
import 'package:openlib/services/logger.dart';

/// A cover image's bytes and file extension (`jpg`, `png`).
@immutable
class CoverImage {
  const CoverImage(this.bytes, this.extension);
  final Uint8List bytes;
  final String extension;
}

/// Longest side kept as is; bigger covers are scaled down to this.
const maxCoverSide = 2400;

String? _imageType(Uint8List b) {
  if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
    return 'jpg';
  }
  if (b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E) {
    return 'png';
  }
  if (b.length > 12 &&
      b[0] == 0x52 &&
      b[1] == 0x49 &&
      b[8] == 0x57 &&
      b[9] == 0x45) {
    return 'webp';
  }
  if (b.length > 3 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) {
    return 'gif';
  }
  return null;
}

/// The cover of the EPUB in [epub], or null when it has none.
CoverImage? epubCover(Uint8List epub) {
  final book = EpubPackage.open(epub);
  if (book == null) return null;
  final opf = book.opf;
  final opfDir = book.opfDir;
  const resolve = EpubPackage.resolve;
  final items = book.items;
  final byId = {for (final i in items) i['id'] ?? '': i};
  bool isImage(Map<String, String>? i) =>
      (i?['media-type'] ?? '').startsWith('image/');
  const attributes = tagAttributes;

  final candidates = <String>[];
  // EPUB 3: properties="cover-image".
  for (final i in items) {
    if ((i['properties'] ?? '').split(' ').contains('cover-image')) {
      candidates.add(resolve(opfDir, i['href'] ?? ''));
    }
  }
  // EPUB 2: <meta name="cover" content="id">.
  for (final m in RegExp(r'<(?:\w+:)?meta\b[^>]*>').allMatches(opf)) {
    final a = attributes(m.group(0)!);
    if (a['name']?.toLowerCase() == 'cover') {
      final item = byId[a['content']];
      if (isImage(item)) candidates.add(resolve(opfDir, item!['href'] ?? ''));
    }
  }
  // The guide's cover page, then the first page of the spine: their
  // first picture.
  final pages = <String>[];
  for (final m in RegExp(r'<(?:\w+:)?reference\b[^>]*>').allMatches(opf)) {
    final a = attributes(m.group(0)!);
    if ((a['type'] ?? '').toLowerCase().contains('cover') &&
        a['href'] != null) {
      pages.add(resolve(opfDir, a['href']!));
    }
  }
  if (book.spine.isNotEmpty) pages.add(book.spine.first);
  for (final page in pages) {
    final html = book.text(page);
    if (html == null) continue;
    final ref = RegExp(
            r'''<(?:\w+:)?(?:img|image)\b[^>]*?(?:xlink:href|href|src)\s*=\s*["']([^"']+)["']''',
            caseSensitive: false)
        .firstMatch(html);
    if (ref != null) {
      candidates.add(resolve(p.posix.dirname(page), ref.group(1)!));
    }
  }
  // Any image called "cover".
  for (final i in items) {
    final name = '${i['id']} ${i['href']}'.toLowerCase();
    if (isImage(i) && name.contains('cover')) {
      candidates.add(resolve(opfDir, i['href'] ?? ''));
    }
  }

  for (final path in candidates) {
    final bytes = book.read(path);
    if (bytes == null || bytes.isEmpty) continue;
    final type = _imageType(bytes);
    if (type == null) continue;
    return _fit(bytes, type);
  }
  return null;
}

/// [bytes] as they are when they are a JPEG or PNG of a sensible size;
/// otherwise decoded once and saved as a JPEG.
CoverImage? _fit(Uint8List bytes, String type) {
  final keep = (type == 'jpg' || type == 'png') && bytes.length < 3 << 20;
  if (keep) {
    final size = _dimensions(bytes, type);
    if (size == null || (size.$1 <= maxCoverSide && size.$2 <= maxCoverSide)) {
      return CoverImage(bytes, type);
    }
  }
  try {
    var image = img.decodeImage(bytes);
    if (image == null) return keep ? CoverImage(bytes, type) : null;
    final longest = image.width > image.height ? image.width : image.height;
    if (longest > maxCoverSide) {
      image = image.width >= image.height
          ? img.copyResize(image,
              width: maxCoverSide, interpolation: img.Interpolation.average)
          : img.copyResize(image,
              height: maxCoverSide, interpolation: img.Interpolation.average);
    }
    return CoverImage(
        Uint8List.fromList(img.encodeJpg(image, quality: 92)), 'jpg');
  } catch (_) {
    return keep ? CoverImage(bytes, type) : null;
  }
}

/// Width and height from a JPEG or PNG header, without decoding.
(int, int)? _dimensions(Uint8List b, String type) {
  if (type == 'png' && b.length > 24) {
    int u32(int o) =>
        (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
    return (u32(16), u32(20));
  }
  if (type == 'jpg') {
    var i = 2;
    while (i + 9 < b.length) {
      if (b[i] != 0xFF) {
        i++;
        continue;
      }
      final marker = b[i + 1];
      final length = (b[i + 2] << 8) | b[i + 3];
      // SOF0..SOF15 except DHT (C4), JPG (C8), DAC (CC).
      if (marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC) {
        final h = (b[i + 5] << 8) | b[i + 6];
        final w = (b[i + 7] << 8) | b[i + 8];
        return (w, h);
      }
      i += 2 + length;
    }
  }
  return null;
}

/// The library's full-quality covers: one file per book in the app's
/// covers folder, made the first time the library shows the book.
class BookCovers extends ChangeNotifier {
  BookCovers._();
  static final BookCovers instance = BookCovers._();

  final AppLogger _logger = AppLogger();
  final Map<String, String> _paths = {};
  final Set<String> _tried = {};
  bool _running = false;
  List<MyBook>? _pending;

  @visibleForTesting
  Future<Directory> Function() directory = _defaultDirectory;

  static Future<Directory> _defaultDirectory() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'covers'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// The file name of [id]'s cover in the covers folder.
  static String fileNameFor(String id, String extension) =>
      '${id.replaceAll(RegExp(r'[^\w.-]'), '_')}.hq.$extension';

  /// The full-quality cover of the book with [id], when there is one.
  String? coverFor(String id) => _paths[id];

  /// Makes the covers of [books] (EPUBs on the device), one at a time in
  /// the background, and tells listeners as each one is ready.
  Future<void> ensure(List<MyBook> books) async {
    _pending = books;
    if (_running) return;
    _running = true;
    try {
      while (_pending != null) {
        final batch = _pending!;
        _pending = null;
        await _run(batch);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _run(List<MyBook> books) async {
    final dir = await directory();
    final storage = (await MyLibraryDb.instance
            .getPreference('bookStorageDirectory')
            .catchError((_) => ''))
        .toString();
    for (final book in books) {
      if (_paths.containsKey(book.id) || !_tried.add(book.id)) continue;
      if ((book.format ?? '').toLowerCase() != 'epub') continue;
      final existing = await _existing(dir, book.id);
      if (existing != null) {
        _paths[book.id] = existing;
        notifyListeners();
        continue;
      }
      final fileName = book.fileName;
      if (fileName == null || storage.isEmpty) continue;
      final path = p.join(storage, fileName);
      if (!await File(path).exists()) continue;
      try {
        final cover = await Isolate.run(
            () async => epubCover(await File(path).readAsBytes()));
        if (cover == null) continue;
        final out =
            File(p.join(dir.path, fileNameFor(book.id, cover.extension)));
        await out.writeAsBytes(cover.bytes, flush: true);
        _paths[book.id] = out.path;
        notifyListeners();
      } catch (e) {
        _logger.warning('Cover not read', tag: 'BookCovers', error: e);
      }
    }
  }

  Future<String?> _existing(Directory dir, String id) async {
    for (final ext in ['jpg', 'png']) {
      final f = File(p.join(dir.path, fileNameFor(id, ext)));
      if (await f.exists() && await f.length() > 0) return f.path;
    }
    return null;
  }

  /// Saves [cover] for [id] now (a book just imported).
  Future<String> save(String id, CoverImage cover) async {
    final dir = await directory();
    final out = File(p.join(dir.path, fileNameFor(id, cover.extension)));
    await out.writeAsBytes(cover.bytes, flush: true);
    _paths[id] = out.path;
    _tried.add(id);
    notifyListeners();
    return out.path;
  }

  /// Forgets [id]'s cover (the book was removed).
  Future<void> remove(String id) async {
    final path = _paths.remove(id);
    _tried.remove(id);
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }
}
