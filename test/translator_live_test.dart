// Runs the real on-device translator against a model file. Skipped by
// default (it needs a multi-gigabyte model); run with
//   TRANSLATION_MODEL=/path/gemma-4-E2B-it.litertlm \
//   flutter test --run-skipped test/translator_live_test.dart

// Dart imports:
import 'dart:io';

// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/services/translation/translation_models.dart';
import 'package:openlib/services/translation/translator.dart';

void main() {
  final modelPath = Platform.environment['TRANSLATION_MODEL'] ?? '';

  test('translates Japanese paragraphs into Korean', () async {
    final runtime = runtimeForFile(modelPath)!;
    final translator =
        LocalLlmTranslator(modelPath: modelPath, runtime: runtime);
    const samples = [
      '「じつにぼくは、二千四百円の損害だ」と一人の紳士が言いました。',
      'それはだいぶの山奥でした。',
      '「ぼくはもう戻ろうとおもう。」',
    ];
    final watch = Stopwatch()..start();
    final outputs = <String>[];
    for (final text in samples) {
      outputs.add(await translator.translate(text,
          targetLanguage: 'Korean', sourceLanguage: 'Japanese'));
    }
    watch.stop();
    // ignore: avoid_print
    print('device=${translator.deviceLabel} ms=${watch.elapsedMilliseconds}');
    for (var i = 0; i < samples.length; i++) {
      // ignore: avoid_print
      print('${samples[i]}\n  => ${outputs[i]}');
    }
    await translator.dispose();

    for (final out in outputs) {
      expect(out, isNotEmpty);
      // Hangul in the answer, no leftover prompt text.
      expect(RegExp(r'[가-힣]').hasMatch(out), isTrue);
      expect(out.toLowerCase(), isNot(contains('translate')));
    }
    // Numbers survive.
    expect(outputs.first,
        anyOf(contains('2,400'), contains('2400'), contains('이천사백')));
  },
      timeout: const Timeout(Duration(minutes: 10)),
      skip: 'needs a local model file (TRANSLATION_MODEL)');
}
