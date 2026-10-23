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
