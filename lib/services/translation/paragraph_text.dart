// Turning EPUB paragraphs into translatable text and back into HTML.

// Package imports:
import 'package:html/dom.dart' as dom;

/// Tags whose content is never part of the readable text: ruby
/// annotations (furigana would otherwise be translated twice, as
/// 漢字かんじ), and non-content elements.
const _droppedTags = {'rt', 'rp', 'script', 'style'};

/// Block tags a translated paragraph is rendered back into. Anything else
/// becomes a `<p>`.
const _keptBlockTags = {
  'p',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'li',
  'blockquote',
  'div',
  'td',
  'th',
  'dt',
  'dd',
  'figcaption',
};

/// The readable text of [element]: ruby readings dropped, `<br>` kept as
/// line breaks, runs of spaces collapsed. Empty when the element holds no
/// text (an illustration, a spacer).
String paragraphText(dom.Element element) {
  final buffer = StringBuffer();
  void walk(dom.Node node) {
    if (node is dom.Element) {
      final tag = node.localName?.toLowerCase();
      if (tag == null || _droppedTags.contains(tag)) return;
      if (tag == 'br') {
        buffer.write('\n');
        return;
      }
    } else if (node is dom.Text) {
      buffer.write(node.text);
      return;
    }
    for (final child in node.nodes) {
      walk(child);
    }
  }

  walk(element);
  return buffer
      .toString()
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r'[ \t\r\f ]+'), ' ').trim())
      .where((line) => line.isNotEmpty)
      .join('\n');
}

/// Whether [text] is worth sending to the model: it must contain at least
/// one letter. Page numbers, `＊＊＊` scene breaks and lone punctuation
/// are left as they are.
bool shouldTranslate(String text) =>
    RegExp(r'\p{L}', unicode: true).hasMatch(text);

/// Whether [element] carries an image. Such paragraphs are shown as the
/// original HTML so the illustration stays.
bool containsImage(dom.Element element) =>
    element.localName == 'img' ||
    element.localName == 'image' ||
    element.querySelector('img, image, svg') != null;

/// HTML for a translated paragraph: the original block tag (so headings
/// stay headings) holding the escaped translation, line breaks as `<br>`.
String translatedHtml(dom.Element original, String translation) {
  final tag = original.localName?.toLowerCase() ?? 'p';
  final outTag = _keptBlockTags.contains(tag) ? tag : 'p';
  final body = translation
      .split('\n')
      .map((line) => _escape(line.trim()))
      .where((line) => line.isNotEmpty)
      .join('<br>');
  return '<$outTag>$body</$outTag>';
}

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// Cleans a model's answer: trims it and removes a wrapper the model
/// sometimes adds around the whole translation (a code fence, or a label
/// such as "Translation:").
String cleanTranslation(String raw) {
  var text = raw.trim();
  final fence = RegExp(r'^```[a-zA-Z]*\n([\s\S]*?)\n?```$').firstMatch(text);
  if (fence != null) text = fence.group(1)!.trim();
  text = text.replaceFirst(
      RegExp(r'^(translation|번역|翻訳|traduction|übersetzung)\s*[:：]\s*',
          caseSensitive: false),
      '');
  return text.trim();
}

/// Characters of Japanese (kana) or of Chinese characters left in an
/// answer that should contain none: kana for any target but Japanese,
/// and Chinese characters too for targets that do not write them.
String leftoverSourceScript(String answer, String targetLanguage) {
  final writesHan =
      targetLanguage == 'Japanese' || targetLanguage.contains('Chinese');
  if (targetLanguage == 'Japanese') return '';
  final pattern = writesHan ? RegExp(r'[぀-ゟ゠-ヿ]') : RegExp(r'[぀-ゟ゠-ヿ㐀-䶿一-鿿]');
  return pattern.allMatches(answer).map((m) => m.group(0)).join();
}

/// Final touches on a translation: Japanese corner brackets become the
/// quotes the target language uses, a quote pair the model wrapped around
/// the whole answer (when the source had none) is removed, and invisible
/// characters and doubled spaces are cleaned up.
String polishTranslation(
    String translation, String source, String targetLanguage) {
  var text = translation
      .replaceAll(RegExp(r'[​-‍﻿]'), '')
      .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
      .trim();

  final sourceQuoted = RegExp(r'^[「『"“]').hasMatch(source.trim());
  if (!sourceQuoted &&
      text.length > 2 &&
      RegExp(r'^["“「]').hasMatch(text) &&
      RegExp(r'["”」]$').hasMatch(text) &&
      !text.substring(1, text.length - 1).contains(RegExp(r'["“”「」]'))) {
    text = text.substring(1, text.length - 1).trim();
  }

  if (targetLanguage != 'Japanese' && !targetLanguage.contains('Chinese')) {
    // Hanja the model added in brackets after a word (만사(萬死)).
    text = text.replaceAll(RegExp(r'\s?\([\u3400-\u4DBF\u4E00-\u9FFF]+\)'), '');
    // Kana the model copied as-is even after the retry (先輩っ！ → 선배っ!,
    // だって left untranslated): kana is never right in this target, so it
    // goes rather than showing up as stray Japanese in the middle of a line.
    text = text.replaceAll(RegExp(r'[\u3040-\u30FF]+\s?'), '');
    text = text
        .replaceAll('！', '!')
        .replaceAll('？', '?')
        .replaceAll('～', '~')
        .replaceAll('（', '(')
        .replaceAll('）', ')')
        .replaceAll('\u3000', ' ')
        .replaceAll(RegExp(r' {2,}'), ' ');
    text = text
        .replaceAll('「', '“')
        .replaceAll('」', '”')
        .replaceAll('『', '‘')
        .replaceAll('』', '’');
    // A dialogue line the model quoted with straight quotes: curly ones,
    // in pairs, as in printed fiction.
    if (RegExp(r'[「『]').hasMatch(source) && text.contains('"')) {
      var open = true;
      text = text.replaceAllMapped(RegExp('"'), (_) {
        final q = open ? '“' : '”';
        open = !open;
        return q;
      });
    }
    text = _restoreWrapping(text, source.trim());
  }
  return text;
}

/// A whole line of dialogue (「…」) or inner voice (（…）) that came back
/// bare - dialogue-trained models drop the brackets, as manga balloons
/// have none - gets them back, so speech still reads as speech.
String _restoreWrapping(String text, String source) {
  if (text.isEmpty) return text;
  const pairs = {'「': '」', '『': '』', '（': '）', '(': ')'};
  final open = source.isEmpty ? null : source[0];
  final close = open == null ? null : pairs[open];
  if (close == null || !source.endsWith(close)) return text;
  // Only when the brackets wrap the whole line, once.
  final inner = source.substring(1, source.length - 1);
  if (inner.contains(open!) || inner.contains(close)) return text;
  final wrapped = switch (open) {
    '「' => ('“', '”'),
    '『' => ('‘', '’'),
    _ => ('(', ')'),
  };
  final starts = RegExp(r'^["“‘(（「『]').hasMatch(text);
  final ends = RegExp(r'["”’)）」』]$').hasMatch(text);
  if (starts || ends) return text;
  return '${wrapped.$1}$text${wrapped.$2}';
}
