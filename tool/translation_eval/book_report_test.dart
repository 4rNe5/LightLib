// Counts what the app's own detectors find in a finished translation: a
// book and the EPUB the app exported with its translation.
//
//   EVAL_SOURCE=book.epub EVAL_TRANSLATED=book.ko.epub \
//   [EVAL_GLOSSARY=glossary.json] \
//   flutter test --no-pub tool/translation_eval/book_report_test.dart
//
// EVAL_SOURCE / EVAL_TRANSLATED may each be several paths with commas
// between, book for book. Without EVAL_GLOSSARY the names are the ones
// the book spells itself (furigana, hiragana names, well-known places).

// Dart imports:
import 'dart:io';

// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/services/translation/book_glossary.dart';
import 'package:openlib/services/translation/translation_qa.dart';

import 'eval_common.dart';

void main() {
  final sources = env('EVAL_SOURCE')?.split(',') ?? const [];
  final translated = env('EVAL_TRANSLATED')?.split(',') ?? const [];

  test('a translated book, counted', () {
    final columns = <String, Map<String, Object>>{};
    for (var b = 0; b < sources.length; b++) {
      final pairs = pairsOf(sources[b], translated[b]);
      final saved = env('EVAL_GLOSSARY')?.split(',');
      final glossary = saved != null && b < saved.length
          ? BookGlossary.decode(File(saved[b]).readAsStringSync())
          : glossaryFromBook(sources[b]);
      final ja = [for (final p in pairs) p.$1];
      final ko = [for (final p in pairs) p.$2];
      final counts = measure(ja, ko, glossary: glossary);
      // The names set right, and what is left after.
      final changes = <(String, String)>[];
      final fixed = [
        for (var i = 0; i < ja.length; i++)
          enforceGlossary(ja[i], ko[i], glossary, changes: changes),
      ];
      final after = measure(ja, fixed, glossary: glossary);
      columns['책 ${b + 1}'] = {
        '용어집 항목(이름)':
            '${glossary.entries.length} (${glossary.entries.where((e) => e.isName).length})',
        ...counts,
        '이름 교정 뒤: 이름이 용어집과 다른 문단': after['이름이 용어집과 다른 문단']!,
        '이름 교정 뒤: 다시 쓸 문단 Gemini (+시제·그녀)':
            after['다시 쓸 문단: Gemini (+시제·그녀)']!,
      };
      final counted = <String, int>{};
      for (final (from, to) in changes) {
        counted['$from→$to'] = (counted['$from→$to'] ?? 0) + 1;
      }
      final top = counted.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      // ignore: avoid_print
      print('책 ${b + 1} 이름 교정: '
          '${top.take(12).map((e) => '${e.key} ×${e.value}').join(', ')}');
    }
    // ignore: avoid_print
    print('\n${table(columns)}');
  },
      skip: sources.isEmpty || translated.length != sources.length
          ? 'needs EVAL_SOURCE and EVAL_TRANSLATED'
          : false);
}
