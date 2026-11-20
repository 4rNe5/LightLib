// The other volumes of a book's series in the library, for their
// glossaries: a name volume 2 gives a reading for is written the same in
// volume 1, and what the reader set once holds for the series.

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/search_results.dart' show seriesKey, volumeOf;
import 'package:openlib/services/translation/book_glossary.dart';
import 'package:openlib/services/translation/glossary_service.dart';

/// The files among [titles] (file name → title) that are other volumes
/// of the series [bookFile] belongs to, by their titles.
List<String> sameSeries(String bookFile, Map<String, String> titles) {
  final title = titles[bookFile];
  if (title == null) return const [];
  final key = seriesKey(volumeOf(title).series);
  if (key.isEmpty) return const [];
  return [
    for (final MapEntry(key: file, value: other) in titles.entries)
      if (file != bookFile && seriesKey(volumeOf(other).series) == key) file,
  ];
}

/// The glossaries the library has for the other volumes of [bookFile]'s
/// series.
Future<List<BookGlossary>> seriesGlossaries(String bookFile) async {
  final books = await MyLibraryDb.instance.getAll();
  final files = sameSeries(
      bookFile, {for (final b in books) b.getFileName(): b.title});
  final out = <BookGlossary>[];
  for (final file in files) {
    final glossary = await GlossaryService.instance.load(file);
    if (glossary.complete && !glossary.isEmpty) out.add(glossary);
  }
  return out;
}
