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

/// The instruction sent with every paragraph. The model answers with the
/// translation only.
String translationPrompt({
  required String text,
  required String targetLanguage,
  String? sourceLanguage,
}) {
  final from = sourceLanguage == null ? '' : ' $sourceLanguage';
  return 'Translate the following$from text into $targetLanguage. '
      'Keep the meaning, tone, names and numbers exactly. '
      'Output only the $targetLanguage translation, without notes.\n\n'
      '$text';
}
