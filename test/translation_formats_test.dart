// Prompt formats per model family: detection, the exact wording each
// model was trained on, context lines, the per-model override and the
// cache id, and the bracket restoration for dialogue-trained output.

// Flutter imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/services/translation/paragraph_text.dart';
import 'package:openlib/services/translation/translation_models.dart';

void main() {
  tearDown(() {
    TranslationPromptFormats.overrides = {};
    TranslationStyle.lightNovel = true;
  });

  group('detectPromptFormat', () {
    test('presets carry their format', () {
      expect(detectPromptFormat(gemma4E2bLiteRt.fileName),
          TranslationPromptFormat.general);
      expect(
          detectPromptFormat(hyMt2Q4km.fileName), TranslationPromptFormat.hyMt);
      expect(
          detectPromptFormat(hyMt2Q8.fileName), TranslationPromptFormat.hyMt);
    });

    test('imported files are recognised by name', () {
      expect(detectPromptFormat('manga-v5-Q4_K_M.gguf'),
          TranslationPromptFormat.general);
      expect(detectPromptFormat('Hy_MT2-1.8B-JP-Manga.gguf'),
          TranslationPromptFormat.hyMt);
      expect(detectPromptFormat('HY-MT1.5-1.8B-Q8_0.gguf'),
          TranslationPromptFormat.hyMt);
      expect(detectPromptFormat('ja-ko-qwen35-2b-ctxB-dpo195-Q4_K_M.gguf'),
          TranslationPromptFormat.jaKoDialogue);
      expect(detectPromptFormat('gemma-4-E4B-it.litertlm'),
          TranslationPromptFormat.general);
    });

    test('the dialogue format is Korean-only', () {
      expect(TranslationPromptFormat.jaKoDialogue.supportsTarget('Korean'),
          isTrue);
      expect(TranslationPromptFormat.jaKoDialogue.supportsTarget('English'),
          isFalse);
      expect(TranslationPromptFormat.hyMt.supportsTarget('English'), isTrue);
    });
  });

  group('prompts', () {
    test('Hy-MT2: its published instructions, style when asked', () {
      final style = hyMtPrompt(text: '本文', targetLanguage: 'Korean');
      expect(
          style,
          startsWith('Please translate the following text into Korean. Note '
              'that the translation style must strictly conform to ['));
      expect(style, contains('반말 or 존댓말'));
      expect(style, endsWith(']:\n\n本文'));

      final plain = hyMtPrompt(
          text: '本文', targetLanguage: 'English', lightNovelStyle: false);
      expect(
          plain,
          'Translate the following text into English. Note that you should '
          'only output the translated result without any additional '
          'explanation:\n\n本文');
    });

    test('JA-KO dialogue: the trained wording, single line', () {
      expect(jaKoDialoguePrompt(text: '「は？」'),
          '일본어 만화 대사를 자연스러운 한국어로 번역하세요.\n현재 대사: 「は？」');
    });

    test('JA-KO dialogue: two lines before, one after, as a list', () {
      final p = jaKoDialoguePrompt(
        text: 'あの料理なら人気は間違いなしですね',
        before: ['一つ目', '二つ目', '三つ目'],
        after: ['次の台詞', 'その次'],
      );
      expect(
          p,
          '일본어 만화 대사를 자연스러운 한국어로 번역하세요. 앞뒤 대사는 참고용이며, '
          '현재 대사의 번역만 출력하세요.\n'
          '이전 대사:\n- 二つ目\n- 三つ目\n'
          '다음 대사:\n- 次の台詞\n'
          '현재 대사: あの料理なら人気は間違いなしですね');
    });

    test('JA-KO dialogue: only the side that exists', () {
      final p = jaKoDialoguePrompt(text: 'x', after: ['y']);
      expect(p, isNot(contains('이전 대사')));
      expect(p, contains('다음 대사:\n- y\n현재 대사: x'));
    });

    test('contextLines: last lines before, first line after, trimmed', () {
      expect(contextLines('a\n\n b \nc\nd'), ['c', 'd']);
      expect(contextLines('a\nb', count: 1, fromEnd: false), ['a']);
      expect(contextLines(null), isEmpty);
      final long = 'あ' * 200;
      expect(contextLines(long).single.length, 120);
      expect(contextLines('x$long', fromEnd: false, count: 1).single,
          startsWith('x'));
    });

    test('buildTranslationPrompt dispatches by format', () {
      final general = buildTranslationPrompt(
          format: TranslationPromptFormat.general,
          text: '本文',
          targetLanguage: 'Korean',
          sourceLanguage: 'Japanese');
      expect(general, contains('Rules:'));

      final hy = buildTranslationPrompt(
          format: TranslationPromptFormat.hyMt,
          text: '本文',
          targetLanguage: 'Korean',
          context: '前の段落');
      expect(hy, isNot(contains('前の段落')),
          reason: 'context made Hy-MT2 worse; it is not sent');

      final jako = buildTranslationPrompt(
          format: TranslationPromptFormat.jaKoDialogue,
          text: '本文',
          targetLanguage: 'Korean',
          context: '一\n二\n三',
          following: '次\nその次');
      expect(jako, contains('이전 대사:\n- 二\n- 三'));
      expect(jako, contains('다음 대사:\n- 次'));
      expect(jako, endsWith('현재 대사: 本文'));
    });
  });

  group('overrides and cache ids', () {
    test('an override wins over detection', () {
      expect(TranslationPromptFormats.formatFor('m.gguf'),
          TranslationPromptFormat.general);
      TranslationPromptFormats.overrides = {
        'm.gguf': TranslationPromptFormat.jaKoDialogue
      };
      expect(TranslationPromptFormats.formatFor('m.gguf'),
          TranslationPromptFormat.jaKoDialogue);
    });

    test('encode/decode round trip; junk is dropped', () {
      final map = {
        'a.gguf': TranslationPromptFormat.hyMt,
        'b.litertlm': TranslationPromptFormat.general,
      };
      expect(
          TranslationPromptFormats.decode(TranslationPromptFormats.encode(map)),
          map);
      expect(TranslationPromptFormats.decode('{"x":"nope","y":"hyMt"}'),
          {'y': TranslationPromptFormat.hyMt});
      expect(TranslationPromptFormats.decode('not json'), isEmpty);
      expect(TranslationPromptFormats.decode(null), isEmpty);
    });

    test('cache ids: general unchanged, other formats kept apart', () {
      expect(TranslationStyle.cacheModelId('gemma.litertlm'), 'gemma.litertlm');
      expect(TranslationStyle.cacheModelId(hyMt2Q4km.fileName),
          '${hyMt2Q4km.fileName}+hyMt');
      TranslationStyle.lightNovel = false;
      expect(TranslationStyle.cacheModelId(hyMt2Q4km.fileName),
          '${hyMt2Q4km.fileName}+plain+hyMt');
      TranslationPromptFormats.overrides = {
        'gemma.litertlm': TranslationPromptFormat.jaKoDialogue
      };
      expect(TranslationStyle.cacheModelId('gemma.litertlm'),
          'gemma.litertlm+plain+jaKoDialogue');
    });
  });

  group('bracket restoration', () {
    test('dialogue that came back bare is quoted again', () {
      expect(polishTranslation('선배, 아직 안 자요?', '「先輩、まだ起きてるんすか？」', 'Korean'),
          '“선배, 아직 안 자요?”');
      expect(polishTranslation('왜 이 녀석은……!', '（なんでこいつ……！）', 'Korean'),
          '‘왜 이 녀석은……!’');
      expect(polishTranslation('그 책', '『その本』', 'Korean'), '‘그 책’');
      // Full-width brackets the model mixed in: a thought all the same.
      expect(polishTranslation('(어째 이 녀석은……!）', '（なんでこいつ……！）', 'Korean'),
          '‘어째 이 녀석은……!’');
      expect(polishTranslation('(어째 이 녀석은……!）', '（なんでこいつ……！）', 'English'),
          '(어째 이 녀석은……!)');
    });

    test('already quoted, partial or narration lines are left alone', () {
      expect(polishTranslation('“하?”', '「は？」', 'Korean'), '“하?”');
      // Brackets that do not wrap the whole line.
      expect(polishTranslation('그는 하? 라고 말했다', '彼は「は？」と言った', 'Korean'),
          '그는 하? 라고 말했다');
      // Two quoted parts in one source line.
      expect(polishTranslation('응. 그래.', '「うん」「そう」', 'Korean'), '응. 그래.');
      expect(polishTranslation('비가 왔다.', '雨が降った。', 'Korean'), '비가 왔다.');
    });
  });

  test('Hy-MT2 presets: official files, sizes and checksums', () {
    for (final preset in [hyMt2Q4km, hyMt2Q8]) {
      expect(preset.url,
          startsWith('https://huggingface.co/tencent/Hy-MT2-1.8B-GGUF/'));
      expect(preset.url, endsWith('/${preset.fileName}'));
      expect(preset.license, 'Apache-2.0');
      expect(preset.runtime, TranslationRuntime.llamaCpp);
    }
    expect(translationModelPresets, containsAll([hyMt2Q4km, hyMt2Q8]));
  });
}
