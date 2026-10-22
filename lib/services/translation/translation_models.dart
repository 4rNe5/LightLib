// The on-device translation models the app offers, and the languages.

// Flutter imports:
import 'package:flutter/foundation.dart';

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

  const TranslationModelPreset({
    required this.id,
    required this.name,
    required this.fileName,
    required this.url,
    required this.sizeBytes,
    required this.sha256,
    required this.runtime,
    required this.license,
  });
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

const translationModelPresets = [gemma4E2bLiteRt, gemma4E2bGguf];

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
}) {
  final japanese = sourceLanguage == 'Japanese' || containsKana(text);
  final from = sourceLanguage == null ? '' : ' $sourceLanguage';
  final buffer = StringBuffer()
    ..writeln('Translate the following$from text into $targetLanguage.')
    ..writeln('Rules:');
  for (final rule in _styleRules(
      targetLanguage: targetLanguage, japaneseSource: japanese)) {
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

/// A correction sent when an answer still contained source-language
/// script: the same request, with the problem named.
String retryPrompt(String prompt, String badAnswer, String targetLanguage) =>
    '$prompt\n\nYour previous answer left Japanese text untranslated:\n'
    '$badAnswer\n\nTranslate again. Every word must be $targetLanguage.';
