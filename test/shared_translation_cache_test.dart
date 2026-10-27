// One set of translations per book, language and style, whichever engine
// made them; earlier per-model sets are brought in on first open.

// Dart imports:
import 'dart:convert';
import 'dart:io';

// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

// Project imports:
import 'package:openlib/services/translation/translation_cache.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('shared_cache'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> legacy(String model, Map<String, String> byText) async {
    final id = TranslationCache.fileIdFor('book.epub', 'ko', model);
    await File(p.join(dir.path, '$id.json')).writeAsString(jsonEncode({
      for (final e in byText.entries) TranslationCache.keyFor(e.key): e.value
    }));
  }

  test('the first open brings in earlier sets, the first listed wins',
      () async {
    await legacy('gemma-4-E2B-it.litertlm', {'あ': '아(E2B)', 'い': '이'});
    await legacy('gemma-4-E4B-it.litertlm', {'あ': '아(E4B)', 'う': '우'});
    final cache = await TranslationCache.open(
      bookFileName: 'book.epub',
      targetLanguage: 'ko',
      modelId: TranslationCache.sharedModelId(lightNovel: true),
      directory: dir,
      mergeFrom: const ['gemma-4-E2B-it.litertlm', 'gemma-4-E4B-it.litertlm'],
    );
    expect(cache.lookup('あ'), '아(E2B)');
    expect(cache.lookup('い'), '이');
    expect(cache.lookup('う'), '우');
    // Saved as the shared set at once.
    final shared = File(p.join(dir.path,
        '${TranslationCache.fileIdFor('book.epub', 'ko', 'shared')}.json'));
    expect(shared.existsSync(), isTrue);

    // Either engine adds to the same set.
    cache.store('え', '에(Gemini)');
    await cache.flush();
    final again = await TranslationCache.open(
        bookFileName: 'book.epub',
        targetLanguage: 'ko',
        modelId: 'shared',
        directory: dir);
    expect(again.lookup('え'), '에(Gemini)');
    expect(again.lookup('い'), '이');
  });

  test('styles stay apart, and deleting a book removes the shared set',
      () async {
    expect(TranslationCache.sharedModelId(lightNovel: false), 'shared+plain');
    final c = await TranslationCache.open(
        bookFileName: 'gone.epub',
        targetLanguage: 'ko',
        modelId: 'shared',
        directory: dir);
    c.store('x', 'y');
    await c.flush();
    await TranslationCache.deleteForBook('gone.epub', directory: dir);
    expect(dir.listSync(), isEmpty);
  });
}
