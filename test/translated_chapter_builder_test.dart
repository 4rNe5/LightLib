// The reader's translating paragraph builder: originals are replaced by
// translations as they arrive, images and scene breaks stay untouched.

// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:epub_view/epub_view.dart' hide Image;
// ignore: implementation_imports
import 'package:epub_view/src/data/models/paragraph.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;

// Project imports:
import 'package:openlib/services/translation/reader_translation_controller.dart';
import 'package:openlib/services/translation/translation_cache.dart';
import 'package:openlib/ui/components/translated_chapter_builder.dart';

import 'translation_core_test.dart' show FakeTranslator;

void main() {
  testWidgets('shows translations in place of the originals', (tester) async {
    final dir = Directory.systemTemp.createTempSync('tbuild');
    final cache = await tester.runAsync(() => TranslationCache.open(
        bookFileName: 'b', targetLanguage: 'ko', modelId: 'm', directory: dir));
    final translator = FakeTranslator();
    final controller = ReaderTranslationController(
      translator: translator,
      cache: cache!,
      targetLanguage: 'Korean',
    );
    final paragraphs = [
      Paragraph(html_parser.parseFragment('<h2>第一章</h2>').children.first, 0),
      Paragraph(
          html_parser
              .parseFragment('<p><ruby>山<rt>やま</rt></ruby>に登った。</p>')
              .children
              .first,
          0),
      Paragraph(html_parser.parseFragment('<p>＊＊＊</p>').children.first, 0),
    ];
    final builders = EpubViewBuilders<DefaultBuilderOptions>(
      options: const DefaultBuilderOptions(),
    );
    final build = translatingChapterBuilder(
        controller: controller, memo: ParagraphTextMemo());

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => ListView(
            children: [
              for (var i = 0; i < paragraphs.length; i++)
                build(context, builders, EpubBook(), const [], paragraphs, i,
                    -1, i, (_) {}),
            ],
          ),
        ),
      ),
    ));

    // Before the model answers: originals, dimmed.
    expect(find.textContaining('に登った', findRichText: true), findsOneWidget);
    expect(find.byType(Opacity), findsWidgets);

    for (var i = 0; i < 10; i++) {
      await tester.pump();
    }

    expect(find.textContaining('[KO]第一章', findRichText: true), findsOneWidget);
    // The ruby reading was not part of what was sent.
    expect(translator.asked, contains('山に登った。'));
    expect(
        find.textContaining('[KO]山に登った。', findRichText: true), findsOneWidget);
    // The scene break is not translated.
    expect(find.textContaining('＊＊＊', findRichText: true), findsOneWidget);
    expect(translator.asked.any((t) => t.contains('＊')), isFalse);
    expect(find.byType(Opacity), findsNothing);

    await tester.runAsync(() async {
      await cache.flush();
      controller.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      dir.deleteSync(recursive: true);
    });
  });
}
