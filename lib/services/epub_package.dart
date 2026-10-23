// The parts of an EPUB the app reads itself - files, manifest, spine -
// straight from the zip, without epubx's parser (which only knows parts
// of EPUB 3 and drops paragraphs some books' markup hides from it).

// Dart imports:
import 'dart:convert';
import 'dart:typed_data';

// Package imports:
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

final _attr = RegExp(r'''([\w:-]+)\s*=\s*("([^"]*)"|'([^']*)')''');

/// The attributes of one start tag, names lowercased.
Map<String, String> tagAttributes(String tag) => {
      for (final m in _attr.allMatches(tag))
        m.group(1)!.toLowerCase(): m.group(3) ?? m.group(4) ?? '',
    };

String _decodeHref(String href) {
  final clean = href.split('#').first;
  try {
    return Uri.decodeComponent(clean);
  } catch (_) {
    return clean;
  }
}

class EpubPackage {
  EpubPackage._(this._files, this.opfPath, this.opf, this.items, this.spine);

  final Map<String, ArchiveFile> _files;

  /// The package document's path in the zip, and its text.
  final String opfPath;
  final String opf;

  /// Manifest items' attributes (`id`, `href`, `media-type`, `properties`).
  final List<Map<String, String>> items;

  /// Paths in the zip of the spine's documents, in reading order.
  final List<String> spine;

  String get opfDir => p.posix.dirname(opfPath);

  /// [href] (relative to [base], a directory in the zip) as a zip path.
  static String resolve(String base, String href) => p.posix
      .normalize(p.posix.join(base == '.' ? '' : base, _decodeHref(href)));

  /// Opens [bytes]; null when they are not an EPUB.
  static EpubPackage? open(Uint8List bytes) {
    final Archive zip;
    try {
      zip = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      return null;
    }
    final files = {for (final f in zip.files) f.name: f};
    String? text(String path) {
      final content = files[path]?.content;
      return content == null
          ? null
          : const Utf8Codec(allowMalformed: true).decode(content);
    }

    final container = text('META-INF/container.xml');
    if (container == null) return null;
    final rootfile =
        RegExp(r'<(?:\w+:)?rootfile\b[^>]*>').firstMatch(container);
    final opfPath = rootfile == null
        ? null
        : tagAttributes(rootfile.group(0)!)['full-path'];
    if (opfPath == null) return null;
    final opf = text(opfPath);
    if (opf == null) return null;
    final items = [
      for (final m in RegExp(r'<(?:\w+:)?item\b[^>]*>').allMatches(opf))
        tagAttributes(m.group(0)!),
    ];
    final byId = {for (final i in items) i['id'] ?? '': i};
    final dir = p.posix.dirname(opfPath);
    final spine = <String>[
      for (final m in RegExp(r'<(?:\w+:)?itemref\b[^>]*>').allMatches(opf))
        if (byId[tagAttributes(m.group(0)!)['idref']]?['href'] case final href?)
          resolve(dir, href),
    ];
    return EpubPackage._(files, opfPath, opf, items, spine);
  }

  /// The file at [path] (case-insensitively as a fallback), or null.
  Uint8List? read(String path) {
    final file = _files[path] ??
        _files.entries
            .where((e) => e.key.toLowerCase() == path.toLowerCase())
            .map((e) => e.value)
            .firstOrNull;
    final content = file?.content;
    return content == null ? null : Uint8List.fromList(content);
  }

  String? text(String path) {
    final bytes = read(path);
    return bytes == null
        ? null
        : const Utf8Codec(allowMalformed: true).decode(bytes);
  }
}

final _ruby = RegExp(r'<ruby\b[^>]*>(.*?)</ruby>', dotAll: true);
final _rt = RegExp(r'<rt\b[^>]*>(.*?)</rt>', dotAll: true);
final _rb = RegExp(r'<rb\b[^>]*>(.*?)</rb>', dotAll: true);
final _tags = RegExp(r'<[^>]+>');
final _allKanji = RegExp(r'^[一-鿿々]+$');
final _smallKana = RegExp('[ゃゅょャュョぁぃぅぇぉァィゥェォ]');

/// Readings the book gives in ruby (furigana) for names and rare words:
/// kanji written at least three times with the same reading, two or more
/// kanji long (or one with a reading of three or more sounds). They tell
/// a translation model how a character's name is read - 和希 is かずき,
/// not わき.
Map<String, String> epubRubyReadings(EpubPackage book) {
  final counts = <String, Map<String, int>>{};
  for (final path in book.spine) {
    final xhtml = book.text(path);
    if (xhtml == null || !xhtml.contains('<ruby')) continue;
    for (final m in _ruby.allMatches(xhtml)) {
      final inner = m.group(1)!;
      final reading = _rt
          .allMatches(inner)
          .map((r) => r.group(1)!.replaceAll(_tags, ''))
          .join()
          .trim();
      final base = (inner.contains('<rb')
              ? _rb.allMatches(inner).map((r) => r.group(1)!).join()
              : inner.replaceAll(_rt, ''))
          .replaceAll(_tags, '')
          .trim();
      if (base.isEmpty || reading.isEmpty || !_allKanji.hasMatch(base)) {
        continue;
      }
      final byReading = counts.putIfAbsent(base, () => {});
      byReading[reading] = (byReading[reading] ?? 0) + 1;
    }
  }
  final out = <String, String>{};
  counts.forEach((base, byReading) {
    final best = byReading.entries.reduce((a, b) => a.value >= b.value ? a : b);
    final total = byReading.values.fold<int>(0, (a, b) => a + b);
    final morae = best.key.replaceAll(_smallKana, '').length;
    if (total >= 3 && (base.length >= 2 || morae >= 3)) out[base] = best.key;
  });
  return out;
}

/// The entries of [readings] that occur in [texts], longest first (so
/// 石井和希 comes before 和希), at most [limit].
List<MapEntry<String, String>> readingsIn(
    Map<String, String> readings, Iterable<String> texts,
    {int limit = 24}) {
  final joined = texts.join('\n');
  final hits = readings.entries.where((e) => joined.contains(e.key)).toList()
    ..sort((a, b) => b.key.length.compareTo(a.key.length));
  return hits.take(limit).toList();
}
