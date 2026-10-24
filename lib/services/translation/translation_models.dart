// The on-device translation models the app offers, and the languages.

// Dart imports:
import 'dart:convert';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Project imports:
import 'package:openlib/services/translation/book_glossary.dart';

/// How a model file is executed.
enum TranslationRuntime {
  /// `.litertlm` through LiteRT-LM: GPU first, CPU when the GPU fails.
  liteRtLm,

  /// `.gguf` through llama.cpp on the CPU.
  llamaCpp,
}

/// The runtime a model file needs, from its extension; null when the file
/// is not a model the app can run.
TranslationRuntime? runtimeForFile(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.litertlm')) return TranslationRuntime.liteRtLm;
  if (lower.endsWith('.gguf')) return TranslationRuntime.llamaCpp;
  return null;
}

/// A downloadable model.
@immutable
class TranslationModelPreset {
  final String id;
  final String name;
  final String fileName;
  final String url;
  final int sizeBytes;

  /// SHA-256 of the file as published (the Hugging Face LFS object id).
  final String sha256;
  final TranslationRuntime runtime;
  final String license;

  /// The instruction format the model was trained on.
  final TranslationPromptFormat promptFormat;

  const TranslationModelPreset({
    required this.id,
    required this.name,
    required this.fileName,
    required this.url,
    required this.sizeBytes,
    required this.sha256,
    required this.runtime,
    required this.license,
    this.promptFormat = TranslationPromptFormat.general,
  });
}

/// How a request is worded for a model: the instruction format it was
/// trained on. A dedicated translation model asked with another model's
/// instructions translates worse and slower (measured: Hy-MT2 with the
/// general rule list left Japanese in 10% of lines and took twice as
/// long), so each model family gets its own.
enum TranslationPromptFormat {
  /// Instruction-following chat models (Gemma): the rule list below.
  general,

  /// Tencent Hy-MT2: its published translation instructions, with the
  /// style instruction when light-novel style is on.
  hyMt,

  /// Japanese-to-Korean dialogue fine-tunes trained on
  /// `현재 대사:` prompts with the lines around it.
  jaKoDialogue;

  static TranslationPromptFormat? fromName(String? name) {
    for (final f in values) {
      if (f.name == name) return f;
    }
    return null;
  }

  /// Formats that only translate into one language.
  bool supportsTarget(String targetLanguage) =>
      this != jaKoDialogue || targetLanguage == 'Korean';
}

/// The format a model file most likely expects: its preset's, else a
/// guess from the file name, else [TranslationPromptFormat.general].
TranslationPromptFormat detectPromptFormat(String fileName) {
  final preset = presetForFile(fileName);
  if (preset != null) return preset.promptFormat;
  final name = fileName.toLowerCase().replaceAll('_', '-');
  if (name.contains('hy-mt') ||
      name.contains('hymt') ||
      name.contains('hunyuan-mt')) {
    return TranslationPromptFormat.hyMt;
  }
  if (name.contains('ja-ko') || name.contains('jako')) {
    return TranslationPromptFormat.jaKoDialogue;
  }
  return TranslationPromptFormat.general;
}

/// Gemma 4 E2B, the model the benchmark picked: the most accurate of the
/// small models tried on Japanese, and the one with an official LiteRT-LM
/// build for Android GPUs. The same `.litertlm` file runs on the CPU.
const gemma4E2bLiteRt = TranslationModelPreset(
  id: 'gemma-4-e2b-litertlm',
  name: 'Gemma 4 E2B (LiteRT, GPU)',
  fileName: 'gemma-4-E2B-it.litertlm',
  url: 'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/'
      'resolve/main/gemma-4-E2B-it.litertlm',
  sizeBytes: 2588147712,
  sha256: '181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c',
  runtime: TranslationRuntime.liteRtLm,
  license: 'Apache-2.0',
);

/// Gemma 4 E4B: the most accurate model measured (chrF++ 61.5 on the
/// light-novel set, against 52.7-57.1 for E2B). Its per-layer embeddings
/// stay in the file, memory-mapped: on CPU it used ~600 MB of working
/// memory, the rest file pages the system can drop. About 2.5x slower
/// than E2B; on a phone GPU with MTP, Google measured 37-49 tokens/s.
const gemma4E4bLiteRt = TranslationModelPreset(
  id: 'gemma-4-e4b-litertlm',
  name: 'Gemma 4 E4B (LiteRT, GPU, best quality)',
  fileName: 'gemma-4-E4B-it.litertlm',
  url: 'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/'
      'resolve/main/gemma-4-E4B-it.litertlm',
  sizeBytes: 3659530240,
  sha256: '0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0',
  runtime: TranslationRuntime.liteRtLm,
  license: 'Apache-2.0',
);

/// The same model as GGUF for llama.cpp, for devices where LiteRT-LM
/// cannot load at all.
const gemma4E2bGguf = TranslationModelPreset(
  id: 'gemma-4-e2b-gguf-q4_0',
  name: 'Gemma 4 E2B Q4_0 (llama.cpp, CPU)',
  fileName: 'gemma-4-E2B-it-Q4_0.gguf',
  url: 'https://huggingface.co/ggml-org/gemma-4-E2B-it-GGUF/'
      'resolve/main/gemma-4-E2B-it-Q4_0.gguf',
  sizeBytes: 2841481184,
  sha256: '8e30dff3ac4c8434c49a7036fa15564bdbb6044e42bf04550bf1a096ad7e6a52',
  runtime: TranslationRuntime.llamaCpp,
  license: 'Apache-2.0',
);

/// Tencent Hy-MT2 1.8B, a dedicated translation model (33 languages,
/// Apache-2.0), official llama.cpp build. Q8_0: Hy-MT2 loses noticeably
/// at 4 bits (chrF++ 50.5 -> 44.3 on light-novel lines), so 8 bits is the
/// one to use.
const hyMt2Q8 = TranslationModelPreset(
  id: 'hy-mt2-1.8b-q8_0',
  name: 'Hy-MT2 1.8B Q8_0 (llama.cpp, CPU)',
  fileName: 'Hy-MT2-1.8B-Q8_0.gguf',
  url: 'https://huggingface.co/tencent/Hy-MT2-1.8B-GGUF/'
      'resolve/main/Hy-MT2-1.8B-Q8_0.gguf',
  sizeBytes: 1908528192,
  sha256: '5c3fe0b1408a5ceb0143184ef247b11b579c525f4b02b060e6c851bb76fef1a4',
  runtime: TranslationRuntime.llamaCpp,
  license: 'Apache-2.0',
  promptFormat: TranslationPromptFormat.hyMt,
);

/// The same model at 4 bits, for phones short on storage or memory.
const hyMt2Q4km = TranslationModelPreset(
  id: 'hy-mt2-1.8b-q4_k_m',
  name: 'Hy-MT2 1.8B Q4_K_M (llama.cpp, CPU, smaller)',
  fileName: 'Hy-MT2-1.8B-Q4_K_M.gguf',
  url: 'https://huggingface.co/tencent/Hy-MT2-1.8B-GGUF/'
      'resolve/main/Hy-MT2-1.8B-Q4_K_M.gguf',
  sizeBytes: 1133080448,
  sha256: 'dc5f44fcf1fa496ee7ad725982c0c8c553a4de00259b53af84c4b89fb0c06699',
  runtime: TranslationRuntime.llamaCpp,
  license: 'Apache-2.0',
  promptFormat: TranslationPromptFormat.hyMt,
);

const translationModelPresets = [
  gemma4E4bLiteRt,
  gemma4E2bLiteRt,
  gemma4E2bGguf,
  hyMt2Q8,
  hyMt2Q4km,
];

TranslationModelPreset? presetForFile(String fileName) {
  for (final preset in translationModelPresets) {
    if (preset.fileName == fileName) return preset;
  }
  return null;
}

/// A target language: its code and the English name the prompt uses.
@immutable
class TranslationLanguage {
  final String code;
  final String englishName;

  /// The name shown in the language picker, in that language.
  final String nativeName;

  const TranslationLanguage(this.code, this.englishName, this.nativeName);
}

const translationLanguages = [
  TranslationLanguage('ko', 'Korean', '한국어'),
  TranslationLanguage('en', 'English', 'English'),
  TranslationLanguage('ja', 'Japanese', '日本語'),
  TranslationLanguage('zh', 'Simplified Chinese', '简体中文'),
  TranslationLanguage('zh-TW', 'Traditional Chinese', '繁體中文'),
  TranslationLanguage('es', 'Spanish', 'Español'),
  TranslationLanguage('fr', 'French', 'Français'),
  TranslationLanguage('de', 'German', 'Deutsch'),
  TranslationLanguage('ru', 'Russian', 'Русский'),
  TranslationLanguage('pt', 'Portuguese', 'Português'),
  TranslationLanguage('it', 'Italian', 'Italiano'),
  TranslationLanguage('vi', 'Vietnamese', 'Tiếng Việt'),
  TranslationLanguage('th', 'Thai', 'ไทย'),
  TranslationLanguage('id', 'Indonesian', 'Bahasa Indonesia'),
];

TranslationLanguage languageForCode(String? code) {
  for (final language in translationLanguages) {
    if (language.code == code) return language;
  }
  return translationLanguages.first;
}

/// The English name for a book's `dc:language` value (`ja`, `ja-JP`,
/// `jpn`), or null when it is missing or unknown - the prompt then lets
/// the model detect the source language.
String? sourceLanguageName(String? bookLanguage) {
  final code = (bookLanguage ?? '').trim().toLowerCase();
  if (code.isEmpty) return null;
  const threeLetter = {
    'jpn': 'ja',
    'kor': 'ko',
    'eng': 'en',
    'zho': 'zh',
    'chi': 'zh',
    'spa': 'es',
    'fra': 'fr',
    'fre': 'fr',
    'deu': 'de',
    'ger': 'de',
    'rus': 'ru',
    'por': 'pt',
    'ita': 'it',
    'vie': 'vi',
    'tha': 'th',
    'ind': 'id',
  };
  final base = code.split(RegExp('[-_]')).first;
  final normalized = threeLetter[base] ?? base;
  if (normalized == 'zh' &&
      (code.contains('tw') || code.contains('hk') || code.contains('hant'))) {
    return 'Traditional Chinese';
  }
  for (final language in translationLanguages) {
    if (language.code.split('-').first == normalized) {
      return language.englishName;
    }
  }
  return null;
}

/// Whether [text] contains Japanese kana.
bool containsKana(String text) => RegExp(r'[぀-ゟ゠-ヿｦ-ﾟ]').hasMatch(text);

/// Whether translations use the light-novel style rules (speech levels,
/// quirks, honorifics, -다 narration) or plain neutral rules. Loaded from
/// [translationLightNovelStylePref]; on by default.
class TranslationStyle {
  TranslationStyle._();

  static bool lightNovel = true;

  /// Translations made with each style are cached apart, so switching
  /// shows (and fills) the matching set instead of mixing them.
  static String cacheModelId(String modelFileName) {
    final base = lightNovel ? modelFileName : '$modelFileName+plain';
    final format = TranslationPromptFormats.formatFor(modelFileName);
    // General-format ids stay as before so existing caches still match.
    return format == TranslationPromptFormat.general
        ? base
        : '$base+${format.name}';
  }
}

/// Prompt formats the user chose for model files (overriding detection),
/// kept as one JSON preference. Loaded at startup; read synchronously.
class TranslationPromptFormats {
  TranslationPromptFormats._();

  static const pref = 'translationPromptFormats';

  static Map<String, TranslationPromptFormat> overrides = {};

  static TranslationPromptFormat formatFor(String fileName) =>
      overrides[fileName] ?? detectPromptFormat(fileName);

  static Map<String, TranslationPromptFormat> decode(String? json) {
    if (json == null || json.isEmpty) return {};
    try {
      final map = jsonDecode(json);
      if (map is! Map) return {};
      return {
        for (final e in map.entries)
          if (TranslationPromptFormat.fromName('${e.value}') != null)
            '${e.key}': TranslationPromptFormat.fromName('${e.value}')!,
      };
    } catch (_) {
      return {};
    }
  }

  static String encode(Map<String, TranslationPromptFormat> map) =>
      jsonEncode({for (final e in map.entries) e.key: e.value.name});
}

const translationLightNovelStylePref = 'translationLightNovelStyle';

/// Neutral rules for any book: accurate, natural, nothing added.
List<String> _plainRules(String targetLanguage) => [
      'Translate everything into accurate, natural $targetLanguage. '
          'Leave no word untranslated and add nothing.',
      'Keep the tone and register of the original.',
      'Keep names, technical terms, numbers and amounts exactly. Keep line '
          'breaks.',
    ];

/// Style rules for fiction, sharpened for Japanese light novels (the
/// reason this reader translates at all) and for Korean output.
List<String> _styleRules({
  required String targetLanguage,
  required bool japaneseSource,
}) {
  final rules = <String>[
    'Translate everything into natural, fluent $targetLanguage prose, '
        'as a professional fiction translator would. Leave no word '
        'untranslated and add nothing.',
    "Keep each character's voice: casual or polite speech, rough or "
        'refined, childish or archaic speech must stay that way.',
    'Keep names, places, skill and item names, numbers and amounts '
        'exactly. Keep line breaks.',
    'Render sound effects and onomatopoeia with natural $targetLanguage '
        'equivalents.',
  ];
  if (japaneseSource) {
    rules.addAll([
      'This is a Japanese light novel. Keep its lively, conversational '
          'tone, stammering (せ、先輩), elongated or cut-off words, and '
          'punctuation such as ……, ――, ！？ and ♪.',
      'Speech quirks carry character: です/ます is polite, だ/ぜ/ねー is '
          'casual, っす is a junior\'s casual-polite speech, ですわ/'
          'ですこと is a noble lady\'s speech, のだ is a cute or haughty '
          'boast. Reflect each in $targetLanguage.',
    ]);
  }
  if (targetLanguage == 'Korean') {
    rules.addAll([
      'Narration outside quotes is written in the plain literary style '
          'ending in -다 (했다, 있었다, 무너져 내렸다), never in -어/-지 '
          'chat style. Dialogue inside quotes keeps natural spoken endings '
          '(해, 할래, 해요, 하거든) - never -다 narration endings.',
      'Use 반말 for casual speech and 존댓말 for polite speech, matching '
          'the original. Translate forms of address naturally: 先輩 → '
          '선배, 〜さん → 〜 씨, 〜くん → 〜 군 or the name alone, 〜ちゃん → '
          '〜쨩, お兄ちゃん → 오빠 or 형 by context.',
      'Write Korean sound words (두근, 쾅, 끼잉) and keep sentence-final '
          'nuance (~거든, ~잖아, ~라고요).',
    ]);
  }
  return rules;
}

/// The instruction sent with every paragraph. The model answers with the
/// translation only. [context] is the text just before this paragraph,
/// given so names, tone and who is speaking stay consistent; it is not
/// translated.
String translationPrompt({
  required String text,
  required String targetLanguage,
  String? sourceLanguage,
  String? context,
  bool lightNovelStyle = true,
}) {
  final japanese = sourceLanguage == 'Japanese' || containsKana(text);
  final from = sourceLanguage == null ? '' : ' $sourceLanguage';
  final buffer = StringBuffer()
    ..writeln('Translate the following$from text into $targetLanguage.')
    ..writeln('Rules:');
  final rules = lightNovelStyle
      ? _styleRules(targetLanguage: targetLanguage, japaneseSource: japanese)
      : _plainRules(targetLanguage);
  for (final rule in rules) {
    buffer.writeln('- $rule');
  }
  buffer
      .writeln('- Output only the $targetLanguage translation, without notes, '
          'quotes around it, or the original.');
  final ctx = context?.trim() ?? '';
  if (ctx.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('Preceding text, for context only (do not translate it):')
      ..writeln(ctx);
  }
  buffer
    ..writeln()
    ..writeln('Text to translate:')
    ..write(text);
  return buffer.toString();
}

/// Style asked of Hy-MT2 when light-novel style is on (its "Style"
/// instruction). Measured: chrF++ 42.9 -> 50.5 on light-novel lines.
String _hyMtStyle(String targetLanguage) => targetLanguage == 'Korean'
    ? 'Japanese light novel / manga style: keep each character\'s speech '
        'level (반말 or 존댓말) and verbal quirks, render honorifics and sound '
        'words naturally in Korean, narration in the -다 literary form'
    : 'Japanese light novel / manga style: keep each character\'s voice, '
        'speech level and verbal quirks, and render honorifics and sound '
        'words naturally';

/// Hy-MT2's own instructions (from its model card); it has no system
/// prompt. Context made it worse in tests, so none is sent.
String hyMtPrompt({
  required String text,
  required String targetLanguage,
  bool lightNovelStyle = true,
}) {
  if (lightNovelStyle) {
    return 'Please translate the following text into $targetLanguage. Note '
        'that the translation style must strictly conform to '
        '[${_hyMtStyle(targetLanguage)}]:\n\n$text';
  }
  return 'Translate the following text into $targetLanguage. Note that you '
      'should only output the translated result without any additional '
      'explanation:\n\n$text';
}

/// The Japanese-to-Korean dialogue fine-tune's training format: up to two
/// lines before and one after as reference, then the line to translate.
String jaKoDialoguePrompt({
  required String text,
  List<String> before = const [],
  List<String> after = const [],
}) {
  final prev = before.where((l) => l.trim().isNotEmpty).toList();
  final next = after.where((l) => l.trim().isNotEmpty).toList();
  final lines = <String>[];
  if (prev.isEmpty && next.isEmpty) {
    lines.add('일본어 만화 대사를 자연스러운 한국어로 번역하세요.');
  } else {
    lines.add('일본어 만화 대사를 자연스러운 한국어로 번역하세요. '
        '앞뒤 대사는 참고용이며, 현재 대사의 번역만 출력하세요.');
    if (prev.isNotEmpty) {
      lines.add('이전 대사:');
      lines.addAll(prev
          .skip(prev.length > 2 ? prev.length - 2 : 0)
          .map((l) => '- ${l.trim()}'));
    }
    if (next.isNotEmpty) {
      lines.add('다음 대사:');
      lines.add('- ${next.first.trim()}');
    }
  }
  lines.add('현재 대사: $text');
  return lines.join('\n');
}

/// Context lines for a dialogue prompt: the last [count] non-empty lines
/// of [text], each cut to [maxChars].
List<String> contextLines(String? text,
    {int count = 2, bool fromEnd = true, int maxChars = 120}) {
  final lines = (text ?? '')
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  final picked = fromEnd
      ? lines.skip(lines.length > count ? lines.length - count : 0)
      : lines.take(count);
  return [
    for (final l in picked)
      l.length > maxChars
          ? (fromEnd
              ? l.substring(l.length - maxChars)
              : l.substring(0, maxChars))
          : l,
  ];
}

/// The request for [format]. [context] is the text just before, [following]
/// the text just after; formats use them only where they helped.
String buildTranslationPrompt({
  required TranslationPromptFormat format,
  required String text,
  required String targetLanguage,
  String? sourceLanguage,
  String? context,
  String? following,
  bool lightNovelStyle = true,
}) {
  switch (format) {
    case TranslationPromptFormat.general:
      return translationPrompt(
          text: text,
          targetLanguage: targetLanguage,
          sourceLanguage: sourceLanguage,
          context: context,
          lightNovelStyle: lightNovelStyle);
    case TranslationPromptFormat.hyMt:
      return hyMtPrompt(
          text: text,
          targetLanguage: targetLanguage,
          lightNovelStyle: lightNovelStyle);
    case TranslationPromptFormat.jaKoDialogue:
      return jaKoDialoguePrompt(
          text: text,
          before: contextLines(context),
          after: contextLines(following, count: 1, fromEnd: false));
  }
}

/// A correction sent when an answer still contained source-language
/// script: the same request, with the problem named.
String retryPrompt(String prompt, String badAnswer, String targetLanguage) =>
    '$prompt\n\nYour previous answer left Japanese text untranslated:\n'
    '$badAnswer\n\nTranslate again. Every word must be $targetLanguage.';

// ---------------------------------------------------------------------------
// Several paragraphs per request
// ---------------------------------------------------------------------------

/// How a published Korean edition of a light novel reads - the target the
/// batch prompt aims the model at (measured against a reference
/// translation of a real light novel; see the commit that added it).
const _koreanLightNovelStyle = """
You translate Japanese light novels into Korean for a published Korean edition.
Write Korean that reads like an officially published light novel: smooth, natural and idiomatic, never word for word.

Style:
- Narration is in the literary -다 form. What happens is told in the past tense, even where the Japanese says it in the present (ノックされる → 노크하는 소리가 들렸다); the narrator's thoughts, judgments and descriptions of how things are stay in the present (〜だろう → 겠지, 〜ない → 않다).
- Keep the narration's person. When the narrator tells the story as 俺, 僕 or 私, the narrator is 나 and あいつら is 그 녀석들; narration that calls the hero by name (周は) stays in the third person, and こちら is the hero (아마네 쪽). 自分 is 자신 or 스스로 (나 only where a first-person narrator means himself).
- Rebuild each sentence in natural Korean word order and drop the subjects and pronouns Korean leaves out (avoid 그녀, 그 when the sentence works without them). Use a comma only where Korean needs a pause, not for every 、.
- Translate idioms by their meaning (おいしい思いをする → 재미를 보다, 腹が立つ → 화가 나다), never literally.
- Words that look alike in Korean often mean something else: 苦手 of a person → 껄끄럽다, 거북하다 (not 서툴다); 正解 → 잘한 일; 微妙 → 애매하다, 좀 그렇다; 一応 → 일단, 그래도; 結構 → 꽤; 気味悪い → 징그럽다; 素直 → 솔직하다, 순순히; 適当 → 대충; 迷惑 → 폐; 失礼 → 실례; 遠慮 → 사양.
- Speech drops the hedges Korean does not say: 〜と思う, 〜気がする and 〜んだけど at the end of a casual line become its ending (「そこまで怒ることないと思うんだけど」 → “그렇게까지 화낼 건 없잖아.”).
- Dialogue keeps each speaker's voice: casual stays casual (반말), polite stays polite (존댓말); a teenage girl sounds like one (~거든, ~잖아, 진짜), a parent warm, a joker playful.
- 「」 become “ ”, 『』 and inner thoughts in （） become ‘ ’, and every line of dialogue ends with punctuation inside the quotes (“이제 됐어.”). Keep ……, ── and !? as they are.
- Japanese names are written by their Japanese reading in Hangul (翔太 → 쇼타, 美咲 → 미사키), the same way every time. Forms of address: 〜君 and 〜くん → 군 (翔太くん → 쇼타 군); 〜ちゃん is dropped (美咲ちゃん → 미사키, called to: 미사키야); 〜さん → 씨 (美咲さん → 미사키 씨), except between classmates: 군 when a girl politely names a boy, nothing when boys talk of a girl; a young girl called 〜さん by someone older → 양; a role with さん or 様 in polite speech → 님 (探偵さん → 탐정님, お客様 → 손님); 先輩 → 선배; お兄ちゃん is 오빠 from a girl and 형 from a boy; 父さん and 母さん are 아빠 and 엄마 for a young speaker.
- Numbers with a unit are written in digits (三十八度三分 → 38.3도, 一年生 → 1학년); 一人 and the like stay words (혼자).
- Sound words and cries become natural Korean ones (ドキッ → 두근, グチャリ → 철퍽, ジンジン → 욱신욱신, いってぇ → 아파).
- Translate every sentence, add nothing, explain nothing.""";

/// Replaces the Korean light-novel instructions (to measure a change
/// against the instructions before it).
@visibleForTesting
String? koreanStyleOverride;

String _genericBatchStyle(String targetLanguage, bool lightNovelStyle) =>
    lightNovelStyle
        ? 'You translate fiction into $targetLanguage for a published edition. '
            'Write natural, fluent $targetLanguage prose, never word for word. '
            "Keep each character's voice and speech level, names exactly and "
            'the same way every time, sound words as natural $targetLanguage '
            'ones, and punctuation such as ……, ── and !?. Translate every '
            'sentence, add nothing, explain nothing.'
        : 'Translate into accurate, natural $targetLanguage. Keep the tone, '
            'names, numbers and amounts exactly. Translate every sentence, add '
            'nothing, explain nothing.';

/// One request for several consecutive paragraphs, answered one numbered
/// line each (see [parseNumberedTranslations]). [before] are the
/// paragraphs just before, with their translations where known, for
/// consistency; they are not translated again.
String batchTranslationPrompt({
  required List<String> texts,
  required String targetLanguage,
  String? sourceLanguage,
  List<String> before = const [],
  List<String?> beforeTranslations = const [],
  List<MapEntry<String, String>> readings = const [],
  List<GlossaryEntry> glossary = const [],
  bool lightNovelStyle = true,
  String? narration,
}) {
  final buffer = StringBuffer(batchStyle(
      texts: texts,
      targetLanguage: targetLanguage,
      sourceLanguage: sourceLanguage,
      lightNovelStyle: lightNovelStyle));
  if (narration != null) {
    buffer
      ..writeln()
      ..write('- $narration');
  }
  if (glossary.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln()
      ..writeln('Names and terms in this book - write them exactly like this '
          '(a gender tells how that person speaks and is spoken of):');
    for (final e in glossary) {
      buffer.writeln(e.promptLine);
    }
  }
  // Readings the glossary does not cover yet: hints only.
  final covered = {for (final e in glossary) e.source};
  readings = [
    for (final r in readings)
      if (!covered.any((c) => c.contains(r.key))) r,
  ];
  if (readings.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln()
      ..writeln('Readings of names and words in this book (write names as '
          'they are read, in $targetLanguage letters; translate ordinary '
          'words by meaning):');
    for (final r in readings) {
      buffer.writeln('${r.key} = ${r.value}');
    }
  }
  if (before.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln()
      ..writeln('The story just before (context only, do not translate it '
          'again):');
    for (var i = 0; i < before.length; i++) {
      buffer.writeln(before[i]);
      final done = i < beforeTranslations.length ? beforeTranslations[i] : null;
      if (done != null && done.isNotEmpty) buffer.writeln('→ $done');
    }
  }
  buffer
    ..writeln()
    ..writeln()
    ..writeln('Translate these paragraphs into $targetLanguage. Answer with '
        'exactly one line per paragraph: its number in brackets, then the '
        'translation.');
  // Said again last: what a small model forgets first over a long request.
  if (targetLanguage == 'Korean' &&
      lightNovelStyle &&
      (sourceLanguage == 'Japanese' || texts.any(containsKana))) {
    buffer.writeln('Remember: narration in the past tense (-었다, -였다), '
        'dialogue in each speaker\'s own 존댓말 or 반말, names as given.');
  }
  buffer.writeln();
  for (var i = 0; i < texts.length; i++) {
    buffer.writeln('[${i + 1}] ${texts[i]}');
  }
  return buffer.toString().trimRight();
}

/// The instructions a batch request opens with (also those a
/// refinement request repeats).
String batchStyle({
  required List<String> texts,
  required String targetLanguage,
  String? sourceLanguage,
  bool lightNovelStyle = true,
}) {
  final japanese =
      sourceLanguage == 'Japanese' || texts.any((t) => containsKana(t));
  return targetLanguage == 'Korean' && japanese && lightNovelStyle
      ? (koreanStyleOverride ?? _koreanLightNovelStyle).trim()
      : _genericBatchStyle(targetLanguage, lightNovelStyle);
}

final _numbered = RegExp(r'^\s*\[(\d+)\]\s*(.*)$');

/// The translations in a numbered answer, by position; null where a number
/// is missing (that paragraph is translated again on its own).
List<String?> parseNumberedTranslations(String answer, int count) {
  final found = <int, String>{};
  for (final line in answer.split('\n')) {
    final m = _numbered.firstMatch(line);
    if (m == null) continue;
    final n = int.parse(m.group(1)!);
    final text = m.group(2)!.trim();
    if (n >= 1 && n <= count && text.isNotEmpty) found.putIfAbsent(n, () => text);
  }
  return [for (var i = 1; i <= count; i++) found[i]];
}
