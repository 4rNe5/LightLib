// Turning EPUB paragraphs into translatable text and back into HTML.

// Dart imports:
import 'dart:typed_data';

// Flutter imports:
import 'package:flutter/foundation.dart' show visibleForTesting;

// Package imports:
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

// Project imports:
import 'package:openlib/services/epub_package.dart';

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
    text = _restoreWrapping(text, source.trim(), targetLanguage);
    if (targetLanguage == 'Korean' && closeKoreanDialogue) {
      text = _closeKoreanDialogue(text);
    }
  }
  return text;
}

final _openDialogue = RegExp(r'“([^“”]*?)”');

/// Whether Korean dialogue gets its closing period (off only to measure
/// what it adds).
@visibleForTesting
bool closeKoreanDialogue = true;

/// Korean editions end every line of dialogue with punctuation inside the
/// quotes (“이제 됐어.”), where Japanese leaves 「いいぞ」 bare: a period
/// goes in where the line has none.
String _closeKoreanDialogue(String text) {
  return text.replaceAllMapped(_openDialogue, (m) {
      final inner = m.group(1)!;
      if (inner.trim().isEmpty ||
          RegExp(r'[.?!…~―─\-)\]’。、,]$').hasMatch(inner.trimRight())) {
        return m.group(0)!;
      }
      return '“${inner.trimRight()}.”';
    });
}

/// A whole line of dialogue (「…」) or inner voice (（…）) that came back
/// bare - dialogue-trained models drop the brackets, as manga balloons
/// have none - gets them back, so speech still reads as speech.
String _restoreWrapping(String text, String source, String targetLanguage) {
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
    _ when targetLanguage == 'Korean' => ('‘', '’'),
    _ => ('(', ')'),
  };
  // Korean editions set inner thoughts in single quotes, closed like
  // dialogue: ‘뭐, 그렇겠지.’
  String thought(String inner) {
    inner = inner.trim();
    return RegExp(r'[.?!…~―─\-]$').hasMatch(inner) ? '‘$inner’' : '‘$inner.’';
  }

  final isThought = wrapped.$1 == '‘' && open == '（';
  if (isThought &&
      text.length > 2 &&
      text.startsWith('(') &&
      text.endsWith(')') &&
      !text.substring(1, text.length - 1).contains(RegExp(r'[()]'))) {
    return thought(text.substring(1, text.length - 1));
  }
  final starts = RegExp(r'^["“‘(（「『]').hasMatch(text);
  final ends = RegExp(r'["”’)）」』]$').hasMatch(text);
  if (starts || ends) return text;
  if (isThought) return thought(text);
  return '${wrapped.$1}$text${wrapped.$2}';
}

/// Block elements the book reader treats as paragraphs (its
/// reader_web/src/paragraphs.js): the innermost ones with text.
const readerParagraphBlocks =
    'p,h1,h2,h3,h4,h5,h6,li,blockquote,dt,dd,figcaption,td,th,div,caption';

const _voidTags = {
  'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link',
  'meta', 'param', 'source', 'track', 'wbr',
};
final _selfClosing = RegExp(r'<([A-Za-z][\w:-]*)(\s[^<>]*?)?/>');

/// [xhtml] with `<tag/>` written `<tag></tag>` for elements HTML does not
/// know as empty. An HTML parser takes `<script .../>` (a Kobo EPUB
/// puts one in every head) as an opening tag, and the whole book after
/// it as the script; the reader, parsing XHTML, does not.
String expandSelfClosingTags(String xhtml) =>
    xhtml.replaceAllMapped(_selfClosing, (m) {
      final tag = m.group(1)!;
      if (_voidTags.contains(tag.toLowerCase())) return m.group(0)!;
      return '<$tag${m.group(2) ?? ''}></$tag>';
    });

/// The paragraphs of one XHTML document as the book reader splits them:
/// leaf blocks with letters, pictures skipped, text as [paragraphText].
List<String> readerParagraphs(String xhtml) {
  final doc = html_parser.parse(expandSelfClosingTags(xhtml));
  final body = doc.body;
  if (body == null) return const [];
  final out = <String>[];
  for (final el in body.querySelectorAll(readerParagraphBlocks)) {
    if (el.querySelector(readerParagraphBlocks) != null) continue;
    if (el.querySelector('img, svg, image, video') != null) continue;
    final text = paragraphText(el);
    if (text.isEmpty || !shouldTranslate(text)) continue;
    out.add(text);
  }
  return out;
}

/// Every paragraph of the EPUB in [bytes], in reading order, split like
/// the book reader splits them (so both share one translation cache).
/// Null when the file is not an EPUB this can read.
List<String>? epubReaderParagraphs(Uint8List bytes) {
  final book = EpubPackage.open(bytes);
  if (book == null) return null;
  return [
    for (final path in book.spine) ...readerParagraphs(book.text(path) ?? ''),
  ];
}
