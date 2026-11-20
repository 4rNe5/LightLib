// A glossary an earlier version made, and the translations made with it,
// set right from the book alone: the owner's 준 타로 (the glossary cut
// 純太郎 after 純, his short name) and しずく, which it never had.

// Dart imports:
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// Package imports:
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/services/translation/book_glossary.dart';
import 'package:openlib/services/translation/glossary_service.dart';
import 'package:openlib/services/translation/paragraph_text.dart';
import 'package:openlib/services/translation/translation_cache.dart';
import 'package:openlib/services/translation/translation_repair.dart';
import 'package:openlib/services/translation/translator.dart';

Uint8List _epub(List<String> paragraphs) {
  final a = Archive()
    ..add(ArchiveFile.bytes('mimetype', ascii.encode('application/epub+zip')))
    ..add(ArchiveFile.string('META-INF/container.xml',
        '<?xml version="1.0"?><container><rootfiles><rootfile full-path="OEBPS/book.opf"/></rootfiles></container>'))
    ..add(ArchiveFile.string(
        'OEBPS/book.opf',
        '<?xml version="1.0"?><package><metadata><dc:title>テスト</dc:title>'
            '<dc:language>ja</dc:language></metadata>'
            '<manifest><item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/></manifest>'
            '<spine><itemref idref="c1"/></spine></package>'))
    ..add(ArchiveFile.string(
        'OEBPS/c1.xhtml',
        '<?xml version="1.0" encoding="UTF-8"?><html xmlns="http://www.w3.org/1999/xhtml">'
            '<head><title>t</title></head><body>'
            '${paragraphs.map((p) => '<p>$p</p>').join()}'
            '</body></html>'));
  return ZipEncoder().encodeBytes(a);
}

/// A model that must not be asked.
class _NoModel implements Translator {
  int asked = 0;
  @override
  String? get deviceLabel => null;
  @override
  int get batchSize => 12;
  @override
  Future<void> load() async {}
  @override
  Future<void> dispose() async {}
  @override
  Future<String?> complete(String prompt,
      {required int maxTokens,
      TranslationPriority priority = TranslationPriority.background,
      String? head}) async {
    asked++;
    return null;
  }

  @override
  Future<String> translate(String text,
      {required String targetLanguage,
      String? sourceLanguage,
      String? context,
      String? following,
      TranslationPriority priority = TranslationPriority.background}) async {
    asked++;
    return '';
  }

  @override
  Future<List<String>> translateBatch(List<String> texts,
      {required String targetLanguage,
      String? sourceLanguage,
      List<String> before = const [],
      List<String?> beforeTranslations = const [],
      Map<String, String> readings = const {},
      BookGlossary glossary = BookGlossary.empty,
      TranslationPriority priority = TranslationPriority.background,
      void Function(int index, String translation)? onEach}) async {
    asked++;
    return [for (final _ in texts) ''];
  }
}

void main() {
  test('opened again: the glossary and the translations are set right, '
      'no model asked', () async {
    final dir = Directory.systemTemp.createTempSync('glossary_upgrade');
    addTearDown(() => dir.deleteSync(recursive: true));
    final service = GlossaryService.instance..directory = () async => dir;
    const jun = '<ruby>純太郎<rt>じゅんたろう</rt></ruby>';
    final book = File('${dir.path}/book.epub')
      ..writeAsBytesSync(_epub([
        for (var i = 0; i < 4; i++) ...[
          '「純くん、おはよう」と言われて$junは笑った。',
          '「しずくちゃん」と呼ぶと、しずくは振り向いた。しずくの髪が揺れた。',
          '$junは店を出た。',
        ],
        '空は青かった。',
      ]));
    final paragraphs = epubReaderParagraphs(book.readAsBytesSync())!;
    expect(paragraphs, contains('純太郎は店を出た。'));

    // As the version before left it.
    File('${dir.path}/upgrade.epub.json').writeAsStringSync(jsonEncode({
      'version': 1,
      'complete': true,
      'narration': 'thirdPerson',
      'entries': [
        {'source': '純', 'target': '준', 'kind': 'person', 'gender': 'male'},
        {
          'source': '純太郎',
          'target': '준 타로',
          'reading': 'じゅんたろう',
          'kind': 'person',
          'gender': 'male',
        },
      ],
    }));
    final cache = await TranslationCache.open(
        bookFileName: 'upgrade.epub',
        targetLanguage: 'Korean',
        modelId: TranslationCache.sharedModelId(lightNovel: true),
        directory: dir);
    cache
      ..store('純太郎は店を出た。', '준 타로는 가게를 나왔다.')
      ..store('「しずくちゃん」と呼ぶと、しずくは振り向いた。しずくの髪が揺れた。',
          '“시즈크.” 하고 부르자 시즈크는 돌아보았다. 시즈쿠의 머리카락이 흔들렸다.')
      ..store('空は青かった。', '하늘은 파랬다.');
    await cache.flush();

    final repaired = <int>[];
    GlossaryService.onUpgraded = (bookFile, bookPath, glossary) async {
      repaired.add(await repairTranslatedNames(
          bookFile: bookFile,
          bookPath: bookPath,
          glossary: glossary,
          directory: dir));
    };
    addTearDown(() => GlossaryService.onUpgraded = null);

    final model = _NoModel();
    final glossary = await service.ensure(
        bookFile: 'upgrade.epub', bookPath: book.path, translator: model);
    // The upgrade's listener works on after the glossary is handed back.
    for (var i = 0; i < 50 && repaired.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    expect(model.asked, 0);
    expect(glossary.version, BookGlossary.currentVersion);
    final target = {for (final e in glossary.entries) e.source: e.target};
    expect(target['純太郎'], '준타로');
    expect(target['純'], '준');
    expect(target['しずく'], '시즈쿠');
    expect(glossary.entries.firstWhere((e) => e.source == 'しずく').gender,
        GlossaryGender.female);
    // Kept as it was otherwise, and saved in the new form.
    expect(glossary.narration, Narration.thirdPerson);
    expect(
        BookGlossary.decode(
                File('${dir.path}/upgrade.epub.json').readAsStringSync())
            .version,
        BookGlossary.currentVersion);

    expect(repaired, [2]);
    expect(cache.lookup('純太郎は店を出た。'), '준타로는 가게를 나왔다.');
    expect(
        cache.lookup('「しずくちゃん」と呼ぶと、しずくは振り向いた。しずくの髪が揺れた。'),
        '“시즈쿠.” 하고 부르자 시즈쿠는 돌아보았다. 시즈쿠의 머리카락이 흔들렸다.');
    expect(cache.lookup('空は青かった。'), '하늘은 파랬다.');

    // Opened once more: nothing left to do.
    repaired.clear();
    await service.ensure(
        bookFile: 'upgrade.epub', bookPath: book.path, translator: model);
    expect(model.asked, 0);
    expect(repaired, isEmpty);
  });
}
