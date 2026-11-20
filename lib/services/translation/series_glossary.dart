// The other volumes of a book's series in the library, for their
// glossaries: a name volume 2 gives a reading for is written the same in
// volume 1, and what the reader set once holds for the series. Which
// books are one series: what their titles say, and what the reader
// grouped in the library (that grouping has the last word where the two
// disagree).

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/files.dart' show getFilePath;
import 'package:openlib/services/logger.dart';
import 'package:openlib/services/search_results.dart' show seriesKey, volumeOf;
import 'package:openlib/services/translation/book_glossary.dart';
import 'package:openlib/services/translation/glossary_service.dart';
import 'package:openlib/services/translation/translation_repair.dart';

/// Preference: 0 keeps every volume's glossary to itself (nothing taken
/// from the series' other volumes, nothing passed on to them). On unless
/// turned off.
const seriesGlossaryPref = 'seriesGlossaryShare';

/// Whether a series' volumes share what their glossaries settled.
Future<bool> seriesGlossaryShared() async {
  try {
    return await MyLibraryDb.instance.getPreference(seriesGlossaryPref) != 0;
  } catch (_) {
    return true;
  }
}

/// The files among [titles] (file name → title) that are other volumes
/// of the series [bookFile] belongs to: by their titles, and by the
/// series the reader put them in ([grouped]: file name → series). Two
/// books the reader put in different series are not one series, whatever
/// their titles say.
List<String> sameSeries(String bookFile, Map<String, String> titles,
    {Map<String, String> grouped = const {}}) {
  final title = titles[bookFile];
  if (title == null) return const [];
  final key = seriesKey(volumeOf(title).series);
  final mine = grouped[bookFile];
  return [
    for (final MapEntry(key: file, value: other) in titles.entries)
      if (file != bookFile)
        if (mine != null && grouped[file] == mine)
          file
        else if (key.isNotEmpty &&
            seriesKey(volumeOf(other).series) == key &&
            (mine == null || grouped[file] == null))
          file,
  ];
}

/// The other volumes of [bookFile]'s series in the library, by file
/// name.
Future<List<String>> seriesFiles(String bookFile) async {
  final books = await MyLibraryDb.instance.getAll();
  final series = await MyLibraryDb.instance
      .getSeriesForAll()
      .catchError((_) => <String, String>{});
  return sameSeries(bookFile, {
    for (final b in books) b.getFileName(): b.title
  }, grouped: {
    for (final b in books)
      if (series[b.id] != null) b.getFileName(): series[b.id]!,
  });
}

/// The glossaries the library has for the other volumes of [bookFile]'s
/// series (none when the reader keeps each volume's to itself).
Future<List<BookGlossary>> seriesGlossaries(String bookFile) async {
  if (!await seriesGlossaryShared()) return const [];
  final out = <BookGlossary>[];
  for (final file in await seriesFiles(bookFile)) {
    final glossary = await GlossaryService.instance.load(file);
    if (glossary.complete && !glossary.isEmpty) out.add(glossary);
  }
  return out;
}

/// [glossary] agreeing with [others] of its series on the names it has
/// itself (no name is added): what another volume knew better - the
/// reader set it, or that book gave its reading - is written here too.
BookGlossary agreeWithSeries(
    BookGlossary glossary, Iterable<BookGlossary> others) {
  final mine = {for (final e in glossary.entries) e.source};
  return inheritSeries(
      glossary,
      [
        for (final o in others)
          o.copyWith(entries: [
            for (final e in o.entries)
              if (mine.contains(e.source)) e,
          ]),
      ],
      mine.join('\n'));
}

/// Books just put in one series ([files]): each one's glossary takes what
/// the others' settled about the names it has, and its saved
/// translations follow. How many glossaries changed.
Future<int> shareWithinSeries(List<String> files,
    {Future<String> Function(String file)? pathOf}) async {
  if (!await seriesGlossaryShared()) return 0;
  final glossaries = <String, BookGlossary>{};
  for (final file in files) {
    final g = await GlossaryService.instance.load(file);
    if (g.complete && !g.isEmpty) glossaries[file] = g;
  }
  var changed = 0;
  for (final file in glossaries.keys.toList()) {
    final next = agreeWithSeries(glossaries[file]!, [
      for (final other in glossaries.entries)
        if (other.key != file) other.value,
    ]);
    if (identical(next, glossaries[file])) continue;
    glossaries[file] = next;
    changed++;
    await GlossaryService.instance.save(file, next);
    try {
      final path = await (pathOf ?? getFilePath)(file);
      await repairTranslatedNames(
          bookFile: file, bookPath: path, glossary: next);
    } catch (e) {
      AppLogger()
          .warning('Translations not set right', tag: 'Glossary', error: e);
    }
  }
  return changed;
}

/// [glossary] with what the reader just set in another volume of its
/// series ([entry]): the same word is written the same way. Null when
/// nothing changes - the glossary does not have the word (a volume that
/// has no such name is not given one), or has it so already.
BookGlossary? withSeriesEdit(BookGlossary glossary, GlossaryEntry entry) {
  final mine =
      glossary.entries.where((e) => e.source == entry.source).firstOrNull;
  if (mine == null) return null;
  if (mine.target == entry.target &&
      mine.gender == entry.gender &&
      mine.edited) {
    return null;
  }
  return glossary.copyWith(entries: [
    for (final e in glossary.entries)
      if (e.source == entry.source)
        e.copyWith(target: entry.target, gender: entry.gender, edited: true)
      else
        e,
  ]);
}

/// What the reader set in [bookFile] ([entry]), written in the series'
/// other volumes: their glossaries, then the names in what was already
/// translated of them. The files whose glossaries changed.
Future<List<String>> passOnToSeries(String bookFile, GlossaryEntry entry,
    {Future<String> Function(String file)? pathOf}) async {
  if (!await seriesGlossaryShared()) return const [];
  final changed = <String>[];
  for (final file in await seriesFiles(bookFile)) {
    final glossary = await GlossaryService.instance.load(file);
    final next = withSeriesEdit(glossary, entry);
    if (next == null) continue;
    await GlossaryService.instance.save(file, next);
    changed.add(file);
    try {
      final path = await (pathOf ?? getFilePath)(file);
      // What that volume has translated with its old form is made again.
      final was = glossary.entries
          .where((e) => e.source == entry.source)
          .firstOrNull
          ?.target;
      if (was != null && was.isNotEmpty && was != entry.target) {
        await redoTranslationsWith(
            bookFile: file, bookPath: path, source: entry.source, written: was);
      }
      await repairTranslatedNames(
          bookFile: file, bookPath: path, glossary: next);
    } catch (e) {
      AppLogger()
          .warning('Translations not set right', tag: 'Glossary', error: e);
    }
  }
  if (changed.isNotEmpty) {
    AppLogger().info('Glossary edit passed on to the series',
        tag: 'Glossary',
        metadata: {'book': bookFile, 'volumes': changed.length});
  }
  return changed;
}
