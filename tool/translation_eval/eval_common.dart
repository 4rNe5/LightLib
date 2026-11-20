// What the translation checks of this folder share: a book and its
// translation paired up, and the counts the app's own detectors give.
// Nothing here is part of the app.

// Dart imports:
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// Project imports:
import 'package:openlib/services/epub_package.dart';
import 'package:openlib/services/translation/book_glossary.dart';
import 'package:openlib/services/translation/paragraph_text.dart';
import 'package:openlib/services/translation/translation_qa.dart';
import 'package:openlib/services/translation/translation_style.dart';

String? env(String name) {
  final v = Platform.environment[name];
  return v == null || v.trim().isEmpty ? null : v.trim();
}

final _hangul = RegExp(r'[가-힣]');

final _wordless = RegExp(r'^[\s「」『』（）()…‥・.。っッー～〜―─!?！？♪]+$');
final _speech = RegExp(r'''^[「『（(“‘"']''');

/// How badly [source] and [translation] fit as a pair: speech against
/// narration, or lengths far apart.
int _misfit(String source, String translation) {
  var cost = 0;
  if (_speech.hasMatch(source) != _speech.hasMatch(translation)) cost += 2;
  final ratio = translation.length / source.length.clamp(1, 1 << 30);
  if (ratio < 0.3 || ratio > 3.5) cost += 1;
  return cost;
}

/// [ja] and [ko] (a chapter and its translation) paired up. The reader's
/// splitter does not count a translation without a letter (“……”) as a
/// paragraph, so [ko] may lack the translations of some wordless lines
/// (「……っ」): which ones is told by what pairs up best after them. Null
/// when they do not pair up.
List<(String, String)>? _pairChapter(List<String> ja, List<String> ko) {
  final extra = ja.length - ko.length;
  if (extra == 0) {
    return [for (var i = 0; i < ja.length; i++) (ja[i], ko[i])];
  }
  if (extra < 0 || extra > 40) return null;
  const far = 1 << 30;
  // best[i][s]: the least misfit of ja[i..] with s lines stepped over so
  // far (ja[i] pairs with ko[i - s]).
  final best = List.generate(ja.length + 1, (_) => List.filled(extra + 1, far));
  best[ja.length][extra] = 0;
  for (var i = ja.length - 1; i >= 0; i--) {
    for (var s = 0; s <= extra; s++) {
      final j = i - s;
      if (j < 0) continue;
      var least = far;
      if (j < ko.length && best[i + 1][s] < far) {
        least = best[i + 1][s] + _misfit(ja[i], ko[j]);
      }
      if (s < extra && _wordless.hasMatch(ja[i]) && best[i + 1][s + 1] < least) {
        least = best[i + 1][s + 1];
      }
      best[i][s] = least;
    }
  }
  if (best[0][0] >= far) return null;
  final pairs = <(String, String)>[];
  var s = 0;
  for (var i = 0; i < ja.length; i++) {
    final j = i - s;
    final paired = j < ko.length && best[i + 1][s] < far
        ? best[i + 1][s] + _misfit(ja[i], ko[j])
        : far;
    if (paired == best[i][s]) {
      pairs.add((ja[i], ko[j]));
    } else {
      s++;
    }
  }
  return pairs;
}

/// A book and the EPUB the app exported with its translation, paragraph
/// for paragraph: (source, translation) where the second is a
/// translation of the first. Paired within each chapter file; a chapter
/// that does not pair up is left out (and said so).
List<(String, String)> pairsOf(String sourcePath, String translatedPath) {
  final a = EpubPackage.open(
      Uint8List.fromList(File(sourcePath).readAsBytesSync()))!;
  final b = EpubPackage.open(
      Uint8List.fromList(File(translatedPath).readAsBytesSync()))!;
  final pairs = <(String, String)>[];
  for (var d = 0; d < a.spine.length && d < b.spine.length; d++) {
    final ja = readerParagraphs(a.text(a.spine[d]) ?? '');
    final ko = readerParagraphs(b.text(b.spine[d]) ?? '');
    final chapter = _pairChapter(ja, ko);
    if (chapter == null) {
      stderr.writeln('${a.spine[d]}: ${ja.length} / ${ko.length} paragraphs, '
          'left out');
      continue;
    }
    pairs.addAll(chapter);
  }
  return [
    for (final (s, t) in pairs)
      if (s != t && _hangul.hasMatch(t)) (s, t),
  ];
}

/// The names the book spells itself (furigana, or written in hiragana),
/// and the well-known places it names: a glossary no model was asked
/// for, enough to count misspelled names with.
BookGlossary glossaryFromBook(String sourcePath) {
  final survey = epubSurvey(Uint8List.fromList(File(sourcePath).readAsBytesSync()));
  final named = [
    for (final c in survey.candidates)
      if (c.reading != null &&
          (c.boyHonorifics + c.girlHonorifics > 0 || c.familyLength != null))
        GlossaryEntry(
            source: c.source,
            target: spellName(c.source, c.reading!),
            reading: c.reading),
  ];
  return upgradeGlossary(
      BookGlossary(complete: true, version: 1, entries: named), survey);
}

/// What the app's detectors count in [translations] of [sources]
/// (consecutive paragraphs; a null or empty translation is one that did
/// not come).
Map<String, Object> measure(List<String> sources, List<String?> translations,
    {BookGlossary glossary = BookGlossary.empty}) {
  var done = 0, leftover = 0, she = 0, sourceShe = 0, leans = 0, stiff = 0;
  var missed = 0, wouldFix = 0, stiffScore = 0;
  final endings = <KoreanEnding, int>{};
  for (var i = 0; i < sources.length; i++) {
    final s = sources[i], t = translations[i];
    if (t == null || t.isEmpty) continue;
    done++;
    if (leftoverSourceScript(t, 'Korean').isNotEmpty) leftover++;
    she += sheCount(t);
    sourceShe += '彼女'.allMatches(s).length;
    if (leansOnShe(s, t)) leans++;
    stiffScore += stiffness(t);
    if (readsStiff(t)) stiff++;
    if (missedNames(s, t, glossary).isNotEmpty) missed++;
    if (enforceGlossary(s, t, glossary) != t) wouldFix++;
    if (isDialogue(s)) continue;
    for (final sentence in sentencesOf(t)) {
      final e = koreanEnding(sentence);
      endings[e] = (endings[e] ?? 0) + 1;
    }
  }
  final past = endings[KoreanEnding.past] ?? 0;
  final present = endings[KoreanEnding.actionPresent] ?? 0;
  final slips = tenseSlips(sources, translations);
  // What each engine would send back to be written again: the checks
  // both run, then a slip of tense (both), 그녀 (Gemini), and stiff
  // paragraphs (Gemini, when the reader turns it on).
  Set<int> sentBack(Set<QaIssue> also, {bool tense = true}) => {
        if (tense) ...slips,
        for (var i = 0; i < sources.length; i++)
          if ((translations[i] ?? '').isNotEmpty &&
              checkTranslation(sources[i], translations[i]!,
                  targetLanguage: 'Korean',
                  glossary: glossary,
                  also: also).isNotEmpty)
            i,
      };
  String share(Set<int> s) =>
      '${s.length} (${done == 0 ? 0 : (100 * s.length / done).toStringAsFixed(1)}%)';
  return {
    '문단(번역됨/전체)': '$done/${sources.length}',
    '한자·가나 남은 문단': leftover,
    '이름이 용어집과 다른 문단': missed,
    '이름 자동 교정이 고칠 문단': wouldFix,
    '지문 과거형 문장': past,
    '지문 동작 현재형 문장': present,
    '동작 현재형 비율 %':
        past + present == 0 ? '-' : (100 * present / (past + present)).toStringAsFixed(1),
    '시제가 튄 문단': slips.length,
    '~것이다 문장': endings[KoreanEnding.explains] ?? 0,
    '그녀 (원문 彼女)': '$she ($sourceShe)',
    '그녀에 기댄 문단': leans,
    '직역투 점수 합': stiffScore,
    '직역투 문단': stiff,
    '다시 쓸 문단: 기존 검사만': share(sentBack(const {}, tense: false)),
    '다시 쓸 문단: 기기 (+시제)': share(sentBack(const {})),
    '다시 쓸 문단: Gemini (+시제·그녀)': share(sentBack(const {QaIssue.pronoun})),
    '다시 쓸 문단: Gemini + 다듬기 옵션':
        share(sentBack(const {QaIssue.pronoun, QaIssue.stiff})),
  };
}

/// [columns] (name → counts) side by side, as a Markdown table.
String table(Map<String, Map<String, Object>> columns) {
  final b = StringBuffer()
    ..writeln('| 항목 | ${columns.keys.join(' | ')} |')
    ..writeln('|---|${'---|' * columns.length}');
  for (final key in columns.values.first.keys) {
    b.writeln(
        '| $key | ${columns.values.map((c) => c[key] ?? '').join(' | ')} |');
  }
  return b.toString();
}

/// An OpenAI-compatible server (llama.cpp's `llama-server`) standing in
/// for the phone's model: one request, greedy, as the app decodes.
class ModelServer {
  ModelServer(this.base);
  final String base;
  final _http = HttpClient()..idleTimeout = const Duration(hours: 1);
  int requests = 0, promptTokens = 0, outputTokens = 0;
  double seconds = 0, outputSeconds = 0;

  Future<String> ask(String user, {String? system, required int maxTokens}) async {
    final watch = Stopwatch()..start();
    final request = await _http.postUrl(Uri.parse('$base/v1/chat/completions'));
    request.headers.contentType = ContentType.json;
    request.add(utf8.encode(jsonEncode({
      'messages': [
        if (system != null) {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
      'temperature': 0,
      'top_k': 1,
      'max_tokens': maxTokens,
      'cache_prompt': true,
    })));
    final response = await request.close();
    final body = await utf8.decodeStream(response);
    if (response.statusCode != 200) {
      throw StateError('server ${response.statusCode}: $body');
    }
    final data = jsonDecode(body) as Map;
    final timings = data['timings'] as Map? ?? const {};
    requests++;
    seconds += watch.elapsedMilliseconds / 1000;
    promptTokens += (timings['prompt_n'] as num? ?? 0).toInt();
    outputTokens += (timings['predicted_n'] as num? ?? 0).toInt();
    outputSeconds += (timings['predicted_ms'] as num? ?? 0) / 1000;
    return ((data['choices'] as List).first['message'] as Map)['content']
            as String? ??
        '';
  }

  String get pace => '$requests요청, ${seconds.round()}s, '
      '${outputSeconds == 0 ? '-' : (outputTokens / outputSeconds).toStringAsFixed(1)} tok/s';

  void close() => _http.close(force: true);
}
