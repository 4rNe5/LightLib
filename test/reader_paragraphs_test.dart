// Paragraphs as the book reader splits them (reader_web/src/paragraphs.js),
// which the background translator must match for the cache to be shared.

// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/services/translation/paragraph_text.dart';

void main() {
  test('a self-closing script in the head does not swallow the book', () {
    // Kobo EPUBs put <script .../> in every head; an HTML parser reads it
    // as an opening tag, the browser (parsing XHTML) does not.
    const xhtml = '<html><head><title>t</title>'
        '<script type="text/javascript" src="../../js/kobo.js"/>'
        '<style id="s"/></head><body>'
        '<p>「周～、どうだった？」</p><p><br/></p>'
        '<p>　期末考査の日程がようやく終了した。</p></body></html>';
    expect(readerParagraphs(xhtml),
        ['「周～、どうだった？」', '期末考査の日程がようやく終了した。']);
    expect(expandSelfClosingTags('<br/><img src="a"/><span/>'),
        '<br/><img src="a"/><span></span>');
  });

  test('a glyph set as a picture in a line is text: the line is a '
      'paragraph, read with the glyph; an illustration is not', () {
    // (The Japanese publishers' EPUBs write what the fonts lack - and
    // some write "!!?" - as <img class="gaiji">: every such line was
    // left untranslated.)
    const xhtml = '<html><head><title>t</title></head><body>'
        '<p>「それでいいのかな<img class="gaiji" src="../image/gaiji-0003.png" alt="!!?"/>」</p>'
        '<p>魔法<img class="gaiji" src="g5.png" alt="杖"/>の職人だ。</p>'
        '<p>「<img class="gaiji-line" src="g1.png" alt="ア濁点"/>ー」と叫ぶ</p>'
        '<p>名は<img class="gaiji" src="g2.png" alt="外字の説明"/>だった</p>'
        '<p>なんだって<img src="mark.png" alt="!?"/></p>'
        // Illustrations, with and without words beside them.
        '<p><img src="../image/i-001.jpg" alt=""/></p>'
        '<div><img src="../image/i-002.jpg" alt="絵"/>挿絵の説明</div>'
        '<p>図<img class="fit" src="../image/i-003.jpg" alt="図版"/></p>'
        '<p>次の<img class="gaiji" src="g5.png" alt="杖"/><svg></svg>は絵</p>'
        '</body></html>';
    expect(readerParagraphs(xhtml), [
      '「それでいいのかな!!?」',
      '魔法杖の職人だ。',
      '「ア\u3099ー」と叫ぶ',
      '名はだった',
      'なんだって!?',
    ]);
  });

  test('leaf blocks with letters, ruby readings dropped, pictures skipped',
      () {
    const xhtml = '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" class="vrtl"><head><title>t</title></head>
<body><div class="main">
<h1 id="toc-001"><span>第一章</span>　<span>「始まり」</span></h1>
<p><br /></p>
<p>　はっきり言って、<ruby><rb>一</rb><rt>ひと</rt></ruby><ruby><rb>目</rb><rt>め</rt></ruby>惚れだった。</p>
<p>――クイクイ。</p>
<div class="align-center"><p><img src="../Images/a.jpg" alt=""/></p></div>
<p>＊　＊　＊</p>
<blockquote><p>引用の中の段落</p></blockquote>
<p>一行目<br/>二行目</p>
</div></body></html>''';
    expect(readerParagraphs(xhtml), [
      '第一章　「始まり」',
      'はっきり言って、一目惚れだった。',
      '――クイクイ。',
      '引用の中の段落',
      '一行目\n二行目',
    ]);
  });
}
