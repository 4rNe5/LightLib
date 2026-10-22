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
