// A Korean title typed into search, turned into the Japanese title the
// work was published under (사망유희로 밥을 먹는다 -> 死亡遊戯で飯を食う。):
// the libraries list Japanese books under their Japanese titles. Asked of
// the translation engine (Gemini, or the model on the phone), only when
// the reader taps for it, and kept.

// Dart imports:
import 'dart:convert';

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/translation/translation_engine.dart';
import 'package:openlib/services/translation/translator.dart';

final _hangul = RegExp(r'[가-힣ᄀ-ᇿ㄰-㆏]');
final _japanese = RegExp(r'[぀-ヿ㐀-鿿々〆]');

/// Whether [text] has Korean letters in it.
bool hasHangul(String text) => _hangul.hasMatch(text);

const originalTitleHead =
    'A reader typed, in Korean, the title of a Japanese light novel, web '
    'novel or manga: its Korean edition\'s title, a translation of the '
    'title, or a nickname. Give the title the work was published under in '
    'Japan, exactly as written there (kanji and kana), without volume '
    'numbers, labels or subtitles. Answer with JSON only:\n'
    '{"titles": ["the most likely original title", "other candidates, at '
    'most 2"]}\n'
    'When you do not know the work, answer {"titles": []}.';

String originalTitlePrompt(String korean) =>
    '$originalTitleHead\n\nKorean title: ${korean.trim()}';

/// The Japanese titles in an answer: written in Japanese, without
/// duplicates, at most three.
List<String> parseOriginalTitles(String? answer) {
  if (answer == null) return const [];
  final start = answer.indexOf('{');
  final end = answer.lastIndexOf('}');
  if (start < 0 || end <= start) return const [];
  try {
    final data = jsonDecode(answer.substring(start, end + 1));
    final titles = data is Map ? data['titles'] : null;
    if (titles is! List) return const [];
    final out = <String>[];
    for (final t in titles) {
      final s = '$t'.trim();
      if (s.isEmpty || !_japanese.hasMatch(s) || out.contains(s)) continue;
      out.add(s);
      if (out.length == 3) break;
    }
    return out;
  } catch (_) {
    return const [];
  }
}

class OriginalTitles {
  OriginalTitles({
    Future<Translator?> Function()? engine,
    MyLibraryDb? database,
  })  : _engine = engine ?? _defaultEngine,
        _database = database;

  static final OriginalTitles instance = OriginalTitles();
  static const _pref = 'originalTitles';

  final Future<Translator?> Function() _engine;
  final MyLibraryDb? _database;
  MyLibraryDb get _db => _database ?? MyLibraryDb.instance;
  Map<String, List<String>>? _known;

  static Future<Translator?> _defaultEngine() async {
    if (await TranslationEngines.cacheModelId() == null) return null;
    return TranslationEngines.forReader();
  }

  Future<Map<String, List<String>>> _load() async {
    if (_known != null) return _known!;
    final known = <String, List<String>>{};
    try {
      final saved = await _db.getPreference(_pref);
      if (saved is String && saved.isNotEmpty) {
        final data = jsonDecode(saved);
        if (data is Map) {
          for (final MapEntry(:key, :value) in data.entries) {
            if (value is List) known['$key'] = [for (final v in value) '$v'];
          }
        }
      }
    } catch (_) {}
    return _known = known;
  }

  static String _key(String korean) =>
      korean.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  /// Titles found before for [korean], if any.
  Future<List<String>?> known(String korean) async =>
      (await _load())[_key(korean)];

  /// The Japanese titles of [korean]; null when nothing can answer (no
  /// translation set up), empty when the engine does not know the work.
  Future<List<String>?> lookup(String korean) async {
    final kept = await known(korean);
    if (kept != null && kept.isNotEmpty) return kept;
    final engine = await _engine();
    if (engine == null) return null;
    try {
      final answer = await engine.complete(originalTitlePrompt(korean),
          maxTokens: 120,
          priority: TranslationPriority.visible,
          head: originalTitleHead);
      final titles = parseOriginalTitles(answer);
      if (titles.isNotEmpty) {
        final known = await _load();
        known[_key(korean)] = titles;
        // A short memory: the latest 200 lookups.
        while (known.length > 200) {
          known.remove(known.keys.first);
        }
        await _db
            .savePreference(_pref, jsonEncode(known))
            .catchError((_) {});
      }
      return titles;
    } finally {
      await engine.dispose();
    }
  }
}
