// Translations already made of a book, set right when its glossary is:
// the names the glossary now writes one way (준타로) are written that way
// in what was translated before (준 타로) - the same letter-for-letter
// rule new translations get ([enforceGlossary]), no model asked.

// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter/foundation.dart' show ChangeNotifier;

// Project imports:
import 'package:openlib/services/files.dart' show getFilePath;
import 'package:openlib/services/heavy_work.dart';
import 'package:openlib/services/logger.dart';
import 'package:openlib/services/storage/app_files.dart';
import 'package:openlib/services/translation/book_glossary.dart';
import 'package:openlib/services/translation/glossary_service.dart';
import 'package:openlib/services/translation/paragraph_text.dart';
import 'package:openlib/services/translation/series_glossary.dart';
import 'package:openlib/services/translation/translation_cache.dart';
import 'package:openlib/services/translation/translation_qa.dart';

/// The set the Korean translations are kept in: by the language's code,
/// as the reader and the library open it. Its English name opened a set
/// nobody ever wrote - a name set right repaired nothing, and "every
/// paragraph with this word" marked 0.
const _korean = 'ko';

/// [translations] (by [TranslationCache.keyFor] of their source) of
/// [paragraphs], with [glossary]'s names as it writes them: only the
/// ones that change, by source text.
Map<String, String> repairedNames(List<String> paragraphs,
    String? Function(String source) translationOf, BookGlossary glossary) {
  final out = <String, String>{};
  for (final source in paragraphs.toSet()) {
    final old = translationOf(source);
    if (old == null || old.isEmpty) continue;
    final fixed = enforceGlossary(source, old, glossary);
    if (fixed != old) out[source] = fixed;
  }
  return out;
}

/// Sets right the Korean translations kept of [bookFile]; how many
/// paragraphs changed.
Future<int> repairTranslatedNames({
  required String bookFile,
  required String bookPath,
  required BookGlossary glossary,
  Directory? directory,
}) async {
  if (glossary.isEmpty) return 0;
  final bytes = await AppFiles.instance.readBytes(bookPath);
  if (bytes == null) return 0;
  final paragraphs = await runHeavy(() => epubReaderParagraphs(bytes));
  if (paragraphs == null || paragraphs.isEmpty) return 0;
  var changed = 0;
  for (final lightNovel in const [true, false]) {
    final cache = await TranslationCache.open(
      bookFileName: bookFile,
      targetLanguage: _korean,
      modelId: TranslationCache.sharedModelId(lightNovel: lightNovel),
      directory: directory,
    );
    if (cache.length == 0) continue;
    final fixed = repairedNames(paragraphs, cache.lookup, glossary);
    fixed.forEach(cache.store);
    if (fixed.isNotEmpty) await cache.flush();
    changed += fixed.length;
  }
  return changed;
}

/// Called after saved translations were marked to be made again: the
/// library's translator looks for work.
void Function()? onTranslationsToRedo;

/// Rings when saved translations of a book ([RedoMarks.bookFile]) were
/// marked to be made again. A reader with that book open shows them as
/// they were written, and would not show the new ones (it sends the page
/// each paragraph once): it starts over with what is on screen.
class RedoMarks extends ChangeNotifier {
  String? bookFile;

  void ring(String file) {
    bookFile = file;
    notifyListeners();
  }
}

final redoMarks = RedoMarks();

/// Marks the Korean translations saved of [bookFile]'s paragraphs that
/// have [source] to be made again - all of them, or only the ones written
/// with [written] (the form the glossary had before the reader changed
/// it). A wrong name in the glossary is in every paragraph translated
/// with it: 魔女 = 푸른마녀 made 花の魔女 "꽃의 푸른마녀", and setting the
/// entry right changed nothing that was already saved. How many were
/// marked.
Future<int> redoTranslationsWith({
  required String bookFile,
  required String bookPath,
  required String source,
  String? written,
  Directory? directory,
}) async {
  if (source.isEmpty || (written != null && written.isEmpty)) return 0;
  final bytes = await AppFiles.instance.readBytes(bookPath);
  if (bytes == null) return 0;
  final paragraphs = await runHeavy(() => epubReaderParagraphs(bytes));
  if (paragraphs == null || paragraphs.isEmpty) return 0;
  final with_ = {
    for (final p in paragraphs)
      if (p.contains(source)) p,
  };
  var marked = 0;
  for (final lightNovel in const [true, false]) {
    final cache = await TranslationCache.open(
      bookFileName: bookFile,
      targetLanguage: _korean,
      modelId: TranslationCache.sharedModelId(lightNovel: lightNovel),
      directory: directory,
    );
    if (cache.length == 0) continue;
    marked += cache.redo([
      for (final p in with_)
        if (written == null || (cache.saved(p)?.contains(written) ?? false)) p,
    ]);
    await cache.flush();
  }
  if (marked > 0) {
    AppLogger().info('Translations to make again',
        tag: 'Glossary',
        metadata: {'book': bookFile, 'paragraphs': marked});
    redoMarks.ring(bookFile);
    onTranslationsToRedo?.call();
  }
  return marked;
}

/// Has a glossary that was set right set the book's translations right
/// too, a book's glossary take what its series' other volumes settled,
/// and what the reader sets in one volume go to the others. Safe to call
/// more than once.
void installTranslationRepair() {
  GlossaryService.seriesOf = seriesGlossaries;
  GlossaryService.onEdited = (bookFile, entry, before) async {
    // What was translated with the form the entry had: made again.
    final was = before?.target ?? '';
    if (was.isNotEmpty && was != entry.target) {
      try {
        await redoTranslationsWith(
            bookFile: bookFile,
            bookPath: await getFilePath(bookFile),
            source: entry.source,
            written: was);
      } catch (e) {
        AppLogger().warning('Translations not marked to be made again',
            tag: 'Glossary', error: e);
      }
    }
    await passOnToSeries(bookFile, entry);
  };
  GlossaryService.onUpgraded = (bookFile, bookPath, glossary) {
    repairTranslatedNames(
            bookFile: bookFile, bookPath: bookPath, glossary: glossary)
        .then((changed) {
      if (changed > 0) {
        AppLogger().info('Names set right in translations',
            tag: 'Glossary',
            metadata: {'book': bookFile, 'paragraphs': changed});
      }
    }).catchError((Object e) {
      AppLogger().warning('Translations not set right',
          tag: 'Glossary', error: e);
    });
  };
}
