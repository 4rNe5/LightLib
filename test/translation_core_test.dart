// Translation building blocks: paragraph text, prompts, the reader's
// queue, and the per-book cache. No model or network involved.

// Dart imports:
import 'dart:async';
import 'dart:io';

// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;

// Project imports:
import 'package:openlib/services/translation/paragraph_text.dart';
import 'package:openlib/services/translation/reader_translation_controller.dart';
import 'package:openlib/services/translation/translation_cache.dart';
import 'package:openlib/services/translation/translation_models.dart';
import 'package:openlib/services/translation/translator.dart';

/// Records what it was asked and answers `[KO]` + the text.
class FakeTranslator implements Translator {
  final List<String> asked = [];
  bool failLoad = false;
  int loads = 0;
  Completer<void>? gate;

  @override
  String? get deviceLabel => 'GPU';

  @override
  Future<void> load() async {
    loads++;
    if (failLoad) throw Exception('no GPU memory');
  }

  @override
  Future<String> translate(String text,
      {required String targetLanguage, String? sourceLanguage}) async {
    asked.add(text);
    if (gate != null) await gate!.future;
    return '[KO]$text';
  }

  @override
  Future<void> dispose() async {}
}

Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('paragraphText', () {
    test('drops ruby readings and keeps line breaks', () {
      final el = html_parser
          .parseFragment('<p><ruby>漢字<rt>かんじ</rt></ruby>を読む。<br/>次の行</p>')
          .children
          .first;
      expect(paragraphText(el), '漢字を読む。\n次の行');
    });

    test('collapses whitespace and ignores empty lines', () {
      final el = html_parser
          .parseFragment('<p>  a   b  <br><br> c </p>')
          .children
          .first;
      expect(paragraphText(el), 'a b\nc');
    });

    test('shouldTranslate needs a letter', () {
      expect(shouldTranslate('「ぼくは戻る。」'), isTrue);
      expect(shouldTranslate('＊　＊　＊'), isFalse);
      expect(shouldTranslate('123'), isFalse);
    });

    test('images are left as they are', () {
      final el =
          html_parser.parseFragment('<p><img src="a.png"/></p>').children.first;
      expect(containsImage(el), isTrue);
    });
  });

  group('translatedHtml', () {
    test('keeps headings, escapes text, maps line breaks', () {
      final h = html_parser.parseFragment('<h2>章</h2>').children.first;
      expect(translatedHtml(h, 'A <b> & "c"\nd'),
          '<h2>A &lt;b&gt; &amp; &quot;c&quot;<br>d</h2>');
    });

    test('unknown tags become paragraphs', () {
      final span = html_parser.parseFragment('<span>x</span>').children.first;
      expect(translatedHtml(span, 'y'), '<p>y</p>');
    });
  });

  test('cleanTranslation strips fences and labels', () {
    expect(cleanTranslation('```\n안녕\n```'), '안녕');
    expect(cleanTranslation('Translation: 안녕'), '안녕');
    expect(cleanTranslation('  안녕  '), '안녕');
  });

  group('models and languages', () {
    test('runtime follows the file extension', () {
      expect(runtimeForFile('a.litertlm'), TranslationRuntime.liteRtLm);
      expect(runtimeForFile('B.GGUF'), TranslationRuntime.llamaCpp);
      expect(runtimeForFile('c.bin'), isNull);
    });

    test('book language codes map to prompt names', () {
      expect(sourceLanguageName('ja'), 'Japanese');
      expect(sourceLanguageName('ja-JP'), 'Japanese');
      expect(sourceLanguageName('jpn'), 'Japanese');
      expect(sourceLanguageName('zh-TW'), 'Traditional Chinese');
      expect(sourceLanguageName(''), isNull);
      expect(sourceLanguageName('xx'), isNull);
    });

    test('the prompt names both languages and asks for the text only', () {
      final prompt = translationPrompt(
          text: '本文', targetLanguage: 'Korean', sourceLanguage: 'Japanese');
      expect(prompt, contains('Japanese text into Korean'));
      expect(prompt, contains('Output only the Korean translation'));
      expect(prompt.endsWith('本文'), isTrue);
      expect(translationPrompt(text: 'x', targetLanguage: 'Korean'),
          contains('following text into Korean'));
    });

    test('presets carry size and checksum', () {
      for (final preset in translationModelPresets) {
        expect(preset.sizeBytes, greaterThan(1000000000));
        expect(preset.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
        expect(runtimeForFile(preset.fileName), preset.runtime);
      }
    });
  });

  group('TranslationCache', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('tcache');
    });
    tearDown(() async => dir.delete(recursive: true));

    test('persists across reopen, keyed by book, language and model', () async {
      final a = await TranslationCache.open(
          bookFileName: 'b.epub',
          targetLanguage: 'ko',
          modelId: 'm',
          directory: dir);
      a.store('こんにちは', '안녕하세요');
      await a.flush();

      final again = await TranslationCache.open(
          bookFileName: 'b.epub',
          targetLanguage: 'ko',
          modelId: 'm',
          directory: dir);
      expect(again.lookup('こんにちは'), '안녕하세요');

      final otherLang = await TranslationCache.open(
          bookFileName: 'b.epub',
          targetLanguage: 'en',
          modelId: 'm',
          directory: dir);
      expect(otherLang.lookup('こんにちは'), isNull);
    });
  });

  group('ReaderTranslationController', () {
    late Directory dir;
    late TranslationCache cache;
    late FakeTranslator translator;
    late ReaderTranslationController controller;
    final texts = [for (var i = 0; i < 40; i++) i % 5 == 4 ? null : 'p$i'];

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('tctl');
      cache = await TranslationCache.open(
          bookFileName: 'b',
          targetLanguage: 'ko',
          modelId: 'm',
          directory: dir);
      translator = FakeTranslator();
      controller = ReaderTranslationController(
        translator: translator,
        cache: cache,
        targetLanguage: 'Korean',
        lookahead: 6,
      );
    });
    tearDown(() async {
      await cache.flush();
      controller.dispose();
      await settle();
      await dir.delete(recursive: true);
    });

    void show(int i) => controller.ensureAhead(i,
        textAt: (j) => j < texts.length ? texts[j] : null,
        itemCount: texts.length);

    test('translates the visible paragraph and the lookahead, in order',
        () async {
      show(10);
      await settle();
      // 10..16, skipping the null at 14.
      expect(translator.asked, ['p10', 'p11', 'p12', 'p13', 'p15', 'p16']);
      expect(controller.translationOf('p12'), '[KO]p12');
      expect(controller.status, ReaderTranslationStatus.idle);
      expect(translator.loads, 1);
    });

    test('cached paragraphs are not asked again', () async {
      cache.store('p0', 'cached');
      show(0);
      await settle();
      expect(translator.asked, isNot(contains('p0')));
      expect(controller.translationOf('p0'), 'cached');
    });

    test('a far jump drops the old queue', () async {
      translator.gate = Completer<void>();
      show(0); // p0 in flight, p1..p6 queued
      await settle();
      show(30); // far away: the old ones go
      translator.gate!.complete();
      await settle();
      expect(translator.asked.first, 'p0');
      expect(translator.asked.skip(1).first, 'p30');
      expect(translator.asked, isNot(contains('p3')));
    });

    test('pause holds the queue until resume', () async {
      controller.pause();
      show(0);
      await settle();
      expect(translator.asked, isEmpty);
      expect(controller.status, ReaderTranslationStatus.paused);
      controller.resume();
      await settle();
      expect(translator.asked, isNotEmpty);
    });

    test('a model that will not load stops with an error; retry runs again',
        () async {
      translator.failLoad = true;
      show(0);
      await settle();
      expect(controller.status, ReaderTranslationStatus.error);
      expect(translator.asked, isEmpty);

      translator.failLoad = false;
      controller.retry();
      await settle();
      expect(controller.status, ReaderTranslationStatus.idle);
      expect(translator.asked, contains('p0'));
    });
  });
}
