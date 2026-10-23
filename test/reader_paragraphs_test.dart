// Paragraphs as the book reader splits them (reader_web/src/paragraphs.js),
// which the background translator must match for the cache to be shared.

// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/services/translation/paragraph_text.dart';

void main() {
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
