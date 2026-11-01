// Data the study features bundle (assets/study/, built by
// tool/build_study_data.py): the Korean readings of kanji (KANJIDIC2,
// CC BY-SA 4.0, EDRDG) and the JLPT level of words (open-anki-jlpt-decks,
// MIT).

// Flutter imports:
import 'package:flutter/services.dart';

class StudyData {
  StudyData._();
  static final StudyData instance = StudyData._();

  final Map<String, String> _hanja = {};
  final Map<String, int> _levels = {};
  final Map<String, int> _levelsByReading = {};
  Future<void>? _loading;

  /// Loads the lists once ([bundle] replaceable in tests).
  Future<void> load({AssetBundle? bundle}) => _loading ??= _load(bundle);

  Future<void> _load(AssetBundle? bundle) async {
    final b = bundle ?? rootBundle;
    try {
      parse(await b.loadString('assets/study/hanja_ko.tsv'),
          await b.loadString('assets/study/jlpt.tsv'));
    } catch (_) {
      // Missing in a test bundle: no readings, no levels.
    }
  }

  void parse(String hanja, String jlpt) {
    for (final line in hanja.split('\n')) {
      final tab = line.indexOf('\t');
      if (tab > 0) _hanja[line.substring(0, tab)] = line.substring(tab + 1);
    }
    for (final line in jlpt.split('\n')) {
      final parts = line.split('\t');
      if (parts.length < 3) continue;
      final level = int.tryParse(parts[2]) ?? 0;
      if (level == 0) continue;
      if ((_levels[parts[0]] ?? 0) < level) _levels[parts[0]] = level;
      if ((_levelsByReading[parts[1]] ?? 0) < level) {
        _levelsByReading[parts[1]] = level;
      }
    }
  }

  /// The Korean readings of [kanji] ('대·다·태'), or null.
  String? hanjaReading(String kanji) => _hanja[kanji];

  /// Each kanji of [word] with its Korean reading.
  List<(String, String)> hanjaOf(String word) => [
        for (final rune in word.runes)
          if (_hanja[String.fromCharCode(rune)] case final ko?)
            (String.fromCharCode(rune), ko),
      ];

  /// The word read the Sino-Korean way, first reading of each kanji
  /// (質問 -> 질문); null when a character has none.
  String? sinoKorean(String word) {
    final out = StringBuffer();
    for (final rune in word.runes) {
      final ko = _hanja[String.fromCharCode(rune)];
      if (ko == null) return null;
      out.write(ko.split('·').first);
    }
    return out.isEmpty ? null : out.toString();
  }

  static final _kanaOnly = RegExp(r'^[぀-ヿー]+$');

  /// 5 (N5) .. 1 (N1); 0 when on no list.
  int levelOf(String word, [String? reading]) {
    final l = _levels[word];
    if (l != null) return l;
    if (_kanaOnly.hasMatch(word)) return _levelsByReading[hiragana(word)] ?? 0;
    return 0;
  }

  static String hiragana(String s) => String.fromCharCodes(s.runes.map(
      (c) => c >= 0x30A1 && c <= 0x30F6 ? c - 0x60 : c));
}

/// 'N3' for 3; '' for 0.
String jlptLabel(int level) => level >= 1 && level <= 5 ? 'N$level' : '';
