// A book's words by JLPT level, counted by the reader page (kuromoji over
// every section, reader_web/src/study.js) and read here: how much of the
// book is above the reader's level, and which of those words it uses most.

// Flutter imports:
import 'package:flutter/foundation.dart';

@immutable
class LevelCount {
  const LevelCount(this.tokens, this.unique);
  final int tokens;
  final int unique;
}

@immutable
class BookWord {
  const BookWord(this.base, this.reading, this.level, this.count,
      [this.sentence = '']);
  final String base;
  final String reading;
  final int level;
  final int count;

  /// Where it first appears.
  final String sentence;
}

@immutable
class BookDifficulty {
  const BookDifficulty({
    required this.tokens,
    required this.unique,
    required this.byLevel,
    required this.words,
  });

  /// Content words (nouns, verbs, adjectives, adverbs ...) in the book.
  final int tokens;
  final int unique;

  /// 5 (N5) .. 1 (N1), and 0 for words on no list.
  final Map<int, LevelCount> byLevel;

  /// Each level's most frequent words.
  final List<BookWord> words;

  factory BookDifficulty.fromJson(Map<String, dynamic> j) {
    final levels = <int, LevelCount>{};
    final by = j['byLevel'];
    if (by is Map) {
      for (final MapEntry(:key, :value) in by.entries) {
        final l = int.tryParse('$key');
        if (l == null || value is! Map) continue;
        levels[l] = LevelCount((value['tokens'] as num?)?.toInt() ?? 0,
            (value['unique'] as num?)?.toInt() ?? 0);
      }
    }
    return BookDifficulty(
      tokens: (j['tokens'] as num?)?.toInt() ?? 0,
      unique: (j['unique'] as num?)?.toInt() ?? 0,
      byLevel: levels,
      words: [
        for (final w in (j['words'] is List ? j['words'] as List : const []))
          if (w is Map && '${w['base'] ?? ''}'.isNotEmpty)
            BookWord('${w['base']}', '${w['reading'] ?? ''}',
                (w['level'] as num?)?.toInt() ?? 0,
                (w['count'] as num?)?.toInt() ?? 0, '${w['sentence'] ?? ''}'),
      ],
    );
  }

  Map<String, Object> toJson() => {
        'tokens': tokens,
        'unique': unique,
        'byLevel': {
          for (final MapEntry(:key, :value) in byLevel.entries)
            '$key': {'tokens': value.tokens, 'unique': value.unique},
        },
        'words': [
          for (final w in words)
            {
              'base': w.base,
              'reading': w.reading,
              'level': w.level,
              'count': w.count,
              'sentence': w.sentence,
            },
        ],
      };

  /// Whether [wordLevel] is above a reader at [level] (5 = N5 .. 1 = N1);
  /// words on no list count as above.
  static bool harder(int wordLevel, int level) =>
      wordLevel == 0 || wordLevel < level;

  /// The share of the book's words (by use) at [wordLevel].
  double share(int wordLevel) =>
      tokens == 0 ? 0 : (byLevel[wordLevel]?.tokens ?? 0) / tokens;

  /// The share of the book's words (by use) above [level], counting only
  /// listed words: words on no list are mostly names, sounds and rare
  /// words a reader looks past.
  double harderShare(int level) {
    var listed = 0;
    var above = 0;
    for (final MapEntry(key: l, value: c) in byLevel.entries) {
      if (l == 0) continue;
      listed += c.tokens;
      if (l < level) above += c.tokens;
    }
    return listed == 0 ? 0 : above / listed;
  }

  /// The words above [level] the book uses most, without its names
  /// ([names], from the glossary) and single unlisted kanji (most are
  /// names too).
  List<BookWord> frequentHarder(int level,
      {Set<String> names = const {}, int limit = 40}) {
    final out = words.where((w) {
      if (!harder(w.level, level)) return false;
      if (names.contains(w.base)) return false;
      if (w.level == 0 && w.base.runes.length == 1) return false;
      if (w.count < 2) return false;
      return true;
    }).toList()
      ..sort((a, b) {
        // Listed words first: they are the ones worth learning.
        final listed = (a.level == 0 ? 1 : 0) - (b.level == 0 ? 1 : 0);
        return listed != 0 ? listed : b.count.compareTo(a.count);
      });
    return out.take(limit).toList();
  }
}
