// A book's cover, and what its package says of the book, read out of an
// EPUB that is kept somewhere else - fetching only the parts of the file
// that hold them (the zip's directory, the package document, a page or
// two, the picture), never the whole book. A 14 MB book costs a few
// hundred kilobytes.

// Dart imports:
import 'dart:convert';
import 'dart:typed_data';

// Package imports:
import 'package:archive/archive.dart';

// Project imports:
import 'package:openlib/services/book_covers.dart';
import 'package:openlib/services/epub_package.dart';

/// The bytes of the file from [start] up to, not including, [end].
typedef RangeFetch = Future<Uint8List> Function(int start, int end);

class _Entry {
  _Entry(this.method, this.compressedSize, this.size, this.headerAt,
      this.nameLength, this.extraLength);
  final int method;
  final int compressedSize;
  final int size;
  final int headerAt;
  final int nameLength;
  final int extraLength;
}

/// A zip read a piece at a time.
class RemoteZip {
  RemoteZip(this.size, this._fetch);

  /// The whole file's length.
  final int size;
  final RangeFetch _fetch;
  Map<String, _Entry>? _entries;

  /// Bytes fetched so far.
  int fetched = 0;

  // The directory of a book with hundreds of files fits in this; one
  // that does not is fetched by itself.
  static const _tail = 48 * 1024;

  Future<Uint8List> _get(int start, int end) async {
    final from = start.clamp(0, size), to = end.clamp(from, size);
    if (to == from) return Uint8List(0);
    final bytes = await _fetch(from, to);
    fetched += bytes.length;
    if (bytes.length != to - from) {
      throw StateError('asked for ${to - from} bytes, got ${bytes.length}');
    }
    return bytes;
  }

  static int _u16(Uint8List b, int o) => b[o] | (b[o + 1] << 8);
  static int _u32(Uint8List b, int o) =>
      b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

  /// The names in the zip.
  Future<Iterable<String>> names() async => (await _directory()).keys;

  Future<Map<String, _Entry>> _directory() async =>
      _entries ??= await _readDirectory();

  Future<Map<String, _Entry>> _readDirectory() async {
    final tailAt = size > _tail ? size - _tail : 0;
    final tail = await _get(tailAt, size);
    // The record that ends the zip: 22 bytes and a comment, at the end.
    var end = -1;
    for (var i = tail.length - 22; i >= 0; i--) {
      if (_u32(tail, i) == 0x06054b50) {
        end = i;
        break;
      }
    }
    if (end < 0) throw const FormatException('not a zip');
    final length = _u32(tail, end + 12), at = _u32(tail, end + 16);
    final directory = at >= tailAt
        ? Uint8List.sublistView(tail, at - tailAt, at - tailAt + length)
        : await _get(at, at + length);
    final entries = <String, _Entry>{};
    var o = 0;
    while (o + 46 <= directory.length && _u32(directory, o) == 0x02014b50) {
      final nameLength = _u16(directory, o + 28);
      final extraLength = _u16(directory, o + 30);
      final commentLength = _u16(directory, o + 32);
      final name = utf8.decode(
          Uint8List.sublistView(directory, o + 46, o + 46 + nameLength),
          allowMalformed: true);
      entries[name] = _Entry(
          _u16(directory, o + 10),
          _u32(directory, o + 20),
          _u32(directory, o + 24),
          _u32(directory, o + 42),
          nameLength,
          extraLength);
      o += 46 + nameLength + extraLength + commentLength;
    }
    return entries;
  }

  /// The file [name] (case-insensitively as a fallback), or null when the
  /// zip has none or keeps it in a way this does not read.
  Future<Uint8List?> read(String name) async {
    final entries = await _directory();
    final entry = entries[name] ??
        entries.entries
            .where((e) => e.key.toLowerCase() == name.toLowerCase())
            .map((e) => e.value)
            .firstOrNull;
    if (entry == null || (entry.method != 0 && entry.method != 8)) return null;
    // The header before the data repeats the name; its extra field may
    // be longer than the directory's, so a little more is asked for.
    const slack = 256;
    final guess = 30 + entry.nameLength + entry.extraLength + slack;
    var bytes = await _get(
        entry.headerAt, entry.headerAt + guess + entry.compressedSize);
    if (bytes.length < 30 || _u32(bytes, 0) != 0x04034b50) return null;
    final dataAt = 30 + _u16(bytes, 26) + _u16(bytes, 28);
    if (dataAt + entry.compressedSize > bytes.length) {
      bytes = await _get(
          entry.headerAt, entry.headerAt + dataAt + entry.compressedSize);
      if (dataAt + entry.compressedSize > bytes.length) return null;
    }
    final data =
        Uint8List.sublistView(bytes, dataAt, dataAt + entry.compressedSize);
    if (entry.method == 0) return Uint8List.fromList(data);
    return Uint8List.fromList(
        Inflate(data, uncompressedSize: entry.size).getBytes());
  }
}

/// What a library shows of a book: its cover and the package's words.
class RemoteEpubCard {
  const RemoteEpubCard({this.cover, this.publisher, this.description});

  /// The cover as the book keeps it (full size).
  final CoverImage? cover;
  final String? publisher;
  final String? description;
}

/// Reads [RemoteEpubCard] from an EPUB of [size] bytes through [fetch].
/// Null when the file is not an EPUB this can read in parts.
Future<RemoteEpubCard?> readRemoteEpubCard(int size, RangeFetch fetch) =>
    readEpubCard(RemoteZip(size, fetch));

Future<RemoteEpubCard?> readEpubCard(RemoteZip zip) async {
  const containerPath = 'META-INF/container.xml';
  final container = await zip.read(containerPath);
  if (container == null) return null;
  final rootfile = RegExp(r'<(?:\w+:)?rootfile\b[^>]*>')
      .firstMatch(utf8.decode(container, allowMalformed: true));
  final opfPath =
      rootfile == null ? null : tagAttributes(rootfile.group(0)!)['full-path'];
  if (opfPath == null) return null;
  final opf = await zip.read(opfPath);
  if (opf == null) return null;

  // The book as far as it was fetched, for the code that knows where
  // covers hide.
  final held = <String, Uint8List>{containerPath: container, opfPath: opf};
  EpubPackage? open() {
    final archive = Archive();
    held.forEach(
        (name, bytes) => archive.addFile(ArchiveFile.bytes(name, bytes)));
    return EpubPackage.open(Uint8List.fromList(ZipEncoder().encode(archive)));
  }

  var book = open();
  if (book == null) return null;
  // Pages whose first picture may be the cover (small).
  var more = false;
  for (final page in epubCoverPages(book)) {
    if (held.containsKey(page)) continue;
    final bytes = await zip.read(page);
    if (bytes != null) {
      held[page] = bytes;
      more = true;
    }
  }
  if (more) book = open() ?? book;

  CoverImage? cover;
  for (final path in epubCoverCandidates(book)) {
    final bytes = await zip.read(path);
    if (bytes == null || bytes.isEmpty) continue;
    cover = coverFromBytes(bytes);
    if (cover != null) break;
  }
  return RemoteEpubCard(
    cover: cover,
    publisher: _dc(book.opf, 'publisher'),
    description: _dc(book.opf, 'description'),
  );
}

/// The text of the package's first `dc:[name]`, or null.
String? _dc(String opf, String name) {
  final m = RegExp('<(?:\\w+:)?$name\\b[^>]*>(.*?)</(?:\\w+:)?$name>',
          dotAll: true, caseSensitive: false)
      .firstMatch(opf);
  if (m == null) return null;
  // Escaped once as XML, and often HTML underneath with its own.
  String plain(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&');
  final text = plain(
          plain(m.group(1)!.replaceAll(RegExp(r'<!\[CDATA\[|\]\]>'), ''))
              .replaceAll(RegExp(r'<[^>]+>'), ' '))
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return text.isEmpty ? null : text;
}
