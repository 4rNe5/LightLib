// A translated copy of an EPUB: each paragraph the translation cache has
// replaced by its translation (the original where there is none), the
// book marked as the target language and set in horizontal writing, so
// any reading app shows the translation.

// Dart imports:
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

// Package imports:
import 'package:archive/archive.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/epub_package.dart';
import 'package:openlib/services/translation/paragraph_text.dart';
import 'package:openlib/services/translation/translation_cache.dart';
import 'package:openlib/services/translation/translation_engine.dart';
import 'package:openlib/services/translation/translation_model_store.dart'
    show translationTargetLanguagePref;
import 'package:openlib/services/translation/translation_models.dart';

class TranslatedEpub {
  const TranslatedEpub(this.bytes, this.translated, this.total);

  final Uint8List bytes;

  /// Paragraphs replaced by a translation, and paragraphs with text.
  final int translated;
  final int total;
}

String _escape(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

/// Horizontal, left to right: a Japanese book is often set vertically.
const _horizontalCss = '<style type="text/css">html, body { '
    'writing-mode: horizontal-tb !important; '
    '-webkit-writing-mode: horizontal-tb !important; '
    '-epub-writing-mode: horizontal-tb !important; }</style>';

/// [xhtml] with each reader paragraph that [translations] (by
/// [TranslationCache.keyFor] of its text) has replaced; counts in
/// [counts] (translated, total).
String translateXhtml(String xhtml, Map<String, String> translations,
    String languageCode, List<int> counts) {
  // The parser's offsets count a CRLF as one character: line ends are
  // made LF first.
  final source = expandSelfClosingTags(
      xhtml.replaceAll('\r\n', '\n').replaceAll('\r', '\n'));
  final doc = html_parser.parse(source, generateSpans: true);
  final body = doc.body;
  if (body == null) return xhtml;
  final edits = <(int, int, String)>[];
  for (final el in body.querySelectorAll(readerParagraphBlocks)) {
    if (el.querySelector(readerParagraphBlocks) != null) continue;
    if (el.querySelector('img, svg, image, video') != null) continue;
    final text = paragraphText(el);
    if (text.isEmpty || !shouldTranslate(text)) continue;
    counts[1]++;
    final translation = translations[TranslationCache.keyFor(text)];
    final open = el.sourceSpan;
    final close = el.endSourceSpan;
    if (translation == null || open == null || close == null) continue;
    final start = open.end.offset;
    final end = close.start.offset;
    if (start > end) continue;
    edits.add((
      start,
      end,
      _escape(translation.trim()).replaceAll('\n', '<br/>'),
    ));
    counts[0]++;
  }
  var out = source;
  // From the end, so earlier offsets stay right.
  edits.sort((a, b) => b.$1.compareTo(a.$1));
  for (final (start, end, text) in edits) {
    out = out.replaceRange(start, end, text);
  }
  // The document's language, and horizontal writing.
  out = out.replaceFirstMapped(
      RegExp(r'<html\b[^>]*>', caseSensitive: false),
      (m) => m.group(0)!.replaceAllMapped(RegExp(r'(\b(?:xml:)?lang=)"[^"]*"'),
          (l) => '${l.group(1)}"$languageCode"'));
  final head = RegExp(r'</head>', caseSensitive: false).firstMatch(out);
  if (head != null) {
    out = out.replaceRange(head.start, head.start, _horizontalCss);
  }
  return out;
}

/// The package document set for the translation: its language, left to
/// right, horizontal, and [titleSuffix] after the title.
String translateOpf(String opf, String languageCode, String titleSuffix) {
  var out = opf.replaceAllMapped(
      RegExp(r'(<dc:language\b[^>]*>)[^<]*(</dc:language>)'),
      (m) => '${m.group(1)}$languageCode${m.group(2)}');
  out = out.replaceAll(RegExp(r'page-progression-direction="rtl"'),
      'page-progression-direction="ltr"');
  out = out.replaceAllMapped(
      RegExp(r'(<meta\b[^>]*name="primary-writing-mode"[^>]*content=")[^"]*'),
      (m) => '${m.group(1)}horizontal-lr');
  if (titleSuffix.isNotEmpty) {
    out = out.replaceFirstMapped(
        RegExp(r'(<dc:title\b[^>]*>)([^<]*)(</dc:title>)'),
        (m) =>
            '${m.group(1)}${m.group(2)}${_escape(titleSuffix)}${m.group(3)}');
  }
  return out;
}

/// The translated copy of the EPUB in [bytes]; null when it is not an
/// EPUB this can read.
TranslatedEpub? buildTranslatedEpub(
  Uint8List bytes,
  Map<String, String> translations, {
  required String languageCode,
  String titleSuffix = '',
}) {
  final book = EpubPackage.open(bytes);
  if (book == null) return null;
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    return null;
  }
  final spine = book.spine.toSet();
  final counts = [0, 0];
  final out = Archive();
  // The mimetype first and stored, as the format asks.
  out.add(ArchiveFile.bytes('mimetype', ascii.encode('application/epub+zip'))
    ..compression = CompressionType.none);
  for (final f in zip.files) {
    if (!f.isFile || f.name == 'mimetype') continue;
    List<int> data = f.content;
    if (spine.contains(f.name)) {
      final text = const Utf8Codec(allowMalformed: true).decode(data);
      data =
          utf8.encode(translateXhtml(text, translations, languageCode, counts));
    } else if (f.name == book.opfPath) {
      data = utf8.encode(translateOpf(
          const Utf8Codec(allowMalformed: true).decode(data),
          languageCode,
          titleSuffix));
    }
    out.add(ArchiveFile.bytes(f.name, data));
  }
  return TranslatedEpub(ZipEncoder().encodeBytes(out), counts[0], counts[1]);
}

/// A saved translated copy of a library book.
class ExportedEpub {
  const ExportedEpub(this.file, this.translated, this.total);
  final File? file;
  final int translated;
  final int total;
}

/// Writes the translated copy of the library book [fileName] (titled
/// [title]) into the app's temporary folder, named after the book and the
/// language; [ExportedEpub.file] is null when nothing is translated yet or
/// the book cannot be read.
Future<ExportedEpub> exportTranslatedEpub(
    {required String fileName, required String title}) async {
  final db = MyLibraryDb.instance;
  final storage = (await db.getPreference('bookStorageDirectory')).toString();
  final language = languageForCode(await db
      .getPreference(translationTargetLanguagePref)
      .catchError((_) => null) as String?);
  final cache = await TranslationEngines.openCache(
      bookFileName: fileName, targetLanguage: language.code);
  final translations = cache.entries;
  final path = p.join(storage, fileName);
  final suffix = ' (${language.nativeName})';
  final result = await Isolate.run(() async => buildTranslatedEpub(
      await File(path).readAsBytes(), translations,
      languageCode: language.code, titleSuffix: suffix));
  if (result == null || result.translated == 0) {
    return ExportedEpub(null, result?.translated ?? 0, result?.total ?? 0);
  }
  final safe =
      '$title$suffix'.replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), '_').trim();
  final dir = Directory(
      p.join((await getTemporaryDirectory()).path, 'translated_books'));
  await dir.create(recursive: true);
  final file = File(p.join(dir.path, '${safe.isEmpty ? 'book' : safe}.epub'));
  await file.writeAsBytes(result.bytes, flush: true);
  return ExportedEpub(file, result.translated, result.total);
}
