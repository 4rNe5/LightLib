// Translations already made of a book, set right when its glossary is:
// the names the glossary now writes one way (준타로) are written that way
// in what was translated before (준 타로) - the same letter-for-letter
// rule new translations get ([enforceGlossary]), no model asked.

// Dart imports:
import 'dart:io';

// Project imports:
import 'package:openlib/services/heavy_work.dart';
import 'package:openlib/services/logger.dart';
import 'package:openlib/services/storage/app_files.dart';
import 'package:openlib/services/translation/book_glossary.dart';
import 'package:openlib/services/translation/glossary_service.dart';
import 'package:openlib/services/translation/paragraph_text.dart';
import 'package:openlib/services/translation/series_glossary.dart';
import 'package:openlib/services/translation/translation_cache.dart';
import 'package:openlib/services/translation/translation_qa.dart';

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
      targetLanguage: 'Korean',
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

/// Has a glossary that was set right set the book's translations right
/// too, and a book's glossary take what its series' other volumes
/// settled. Safe to call more than once.
void installTranslationRepair() {
  GlossaryService.seriesOf = seriesGlossaries;
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
