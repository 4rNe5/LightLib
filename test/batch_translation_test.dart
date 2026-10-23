// Several paragraphs per request: the prompt, reading the numbered answer,
// and the book's ruby readings handed to the model.

// Dart imports:
import 'dart:convert';
import 'dart:typed_data';

// Package imports:
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/services/epub_package.dart';
import 'package:openlib/services/translation/translation_models.dart';

Uint8List _epub(Map<String, String> files) {
  final archive = Archive();
  files.forEach((name, content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  test('the prompt numbers the paragraphs and carries context and readings',
      () {
    final prompt = batchTranslationPrompt(
      texts: ['「おはよう、和希君！」', '父さんだ。'],
      targetLanguage: 'Korean',
      sourceLanguage: 'Japanese',
      before: ['ドアを開けた。'],
      beforeTranslations: ['문을 열었다.'],
      readings: const [MapEntry('和希', 'かずき')],
    );
    expect(prompt, contains('published Korean edition'));
    expect(prompt, contains('和希 = かずき'));
    expect(prompt, contains('ドアを開けた。\n→ 문을 열었다.'));
    expect(prompt, endsWith('[1] 「おはよう、和希君！」\n[2] 父さんだ。'));
    // Not Japanese into Korean: the general instructions.
    final en = batchTranslationPrompt(
        texts: ['Hello.', 'Bye.'], targetLanguage: 'German');
    expect(en, isNot(contains('Korean')));
    expect(en, contains('[2] Bye.'));
  });

  test('numbered answers are read by position, gaps stay empty', () {
    expect(
        parseNumberedTranslations(
            'Sure:\n[1] “좋은 아침, 카즈키!”\n[3]  아빠다.\n[3] again\n[9] x', 3),
        ['“좋은 아침, 카즈키!”', null, '아빠다.']);
    expect(parseNumberedTranslations('', 2), [null, null]);
  });

  test('ruby readings: repeated names and rare words, not one-off kana', () {
    final page = '<html><body>'
        '${'<p><ruby>和<rt>かず</rt>希<rt>き</rt></ruby>は笑った。</p>' * 3}'
        '${'<p><ruby><rb>氷高</rb><rt>ひだか</rt></ruby>さん</p>' * 4}'
        '${'<p><ruby>奴<rt>やつ</rt></ruby>だ</p>' * 5}'
        '<p><ruby>月山<rt>つきやま</rt></ruby>は一度だけ</p>'
        '</body></html>';
    final book = EpubPackage.open(_epub({
      'META-INF/container.xml':
          '<container><rootfiles><rootfile full-path="OPS/p.opf"/></rootfiles></container>',
      'OPS/p.opf': '<package><manifest><item id="a" href="a.xhtml" '
          'media-type="application/xhtml+xml"/></manifest>'
          '<spine><itemref idref="a"/></spine></package>',
      'OPS/a.xhtml': page,
    }))!;
    final readings = epubRubyReadings(book);
    expect(readings, {'和希': 'かずき', '氷高': 'ひだか'});
    expect(readingsIn(readings, ['和希は来た']).map((e) => e.key), ['和希']);
  });
}
