// Paragraphs marked to be made again (a name was set right in the
// glossary), translated by the library's translator at once and to the
// end, without the book being opened - those paragraphs only.

// Dart imports:
import 'dart:convert';
import 'dart:io';

// Package imports:
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/translation/background_translation_notice.dart';
import 'package:openlib/services/translation/book_glossary.dart';
import 'package:openlib/services/translation/book_translation_service.dart';
import 'package:openlib/services/translation/claude/claude_settings.dart';
import 'package:openlib/services/translation/gemini/gemini_settings.dart';
import 'package:openlib/services/translation/glossary_service.dart';
import 'package:openlib/services/translation/translation_cache.dart';
import 'package:openlib/services/translation/translation_engine.dart';
import 'package:openlib/services/translation/translation_repair.dart';
import 'package:openlib/services/translation/translator.dart';

class _FakePathProvider extends PathProviderPlatform {
  Future<String> _dir(String name) async {
    final dir = Directory('/tmp/openlib_redo_test/$name');
    await dir.create(recursive: true);
    return dir.path;
  }

  @override
  Future<String?> getApplicationSupportPath() => _dir('support');
  @override
  Future<String?> getApplicationDocumentsPath() => _dir('documents');
  @override
  Future<String?> getTemporaryPath() => _dir('temp');
  @override
  Future<String?> getLibraryPath() => _dir('library');
}

/// Translates by saying what it was given, and keeps a list of it.
class _Fake implements Translator {
  final asked = <String>[];

  @override
  String? get deviceLabel => 'CPU';
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
          String? head}) async =>
      null;

  @override
  Future<String> translate(String text,
      {required String targetLanguage,
      String? sourceLanguage,
      String? context,
      String? following,
      TranslationPriority priority = TranslationPriority.background}) async {
    asked.add(text);
    return '다시: $text';
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
    final out = <String>[];
    for (var i = 0; i < texts.length; i++) {
      asked.add(texts[i]);
      out.add('다시: ${texts[i]}');
      onEach?.call(i, out.last);
    }
    return out;
  }
}

List<int> _epub(List<String> paragraphs) {
  final a = Archive()
    ..add(ArchiveFile.bytes('mimetype', ascii.encode('application/epub+zip')))
    ..add(ArchiveFile.string('META-INF/container.xml',
        '<?xml version="1.0"?><container><rootfiles><rootfile full-path="OEBPS/book.opf"/></rootfiles></container>'))
    ..add(ArchiveFile.string(
        'OEBPS/book.opf',
        '<?xml version="1.0"?><package><metadata><dc:title>t</dc:title>'
            '<dc:language>ja</dc:language></metadata>'
            '<manifest><item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/></manifest>'
            '<spine><itemref idref="c1"/></spine></package>'))
    ..add(ArchiveFile.string(
        'OEBPS/c1.xhtml',
        '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>t</title></head><body>'
            '${[for (final p in paragraphs) '<p>$p</p>'].join()}</body></html>'));
  return ZipEncoder().encodeBytes(a);
}

MyBook _book(String file, String title) => MyBook(
      id: file,
      title: title,
      author: null,
      thumbnail: null,
      link: 'https://example.com/$file',
      publisher: null,
      info: null,
      format: 'epub',
      description: null,
      fileName: file,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final db = MyLibraryDb.instance;
  final service = BookTranslationService.instance;
  late Directory dir;
  late _Fake fake;

  const flower = '花の魔女は笑った。';
  const blue = '青の魔女が来た。';
  const weather = '今日はいい天気だった。';
  const meeting = '魔女集会はまだ先だ。';
  const road = '道は遠い。';

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    PathProviderPlatform.instance = _FakePathProvider();
    BackgroundTranslationNotice.supportedOverride = false;
    // An engine off the phone is chosen (nothing of the phone's is asked).
    GeminiSettings.instance.debugSet(useGemini: true, key: 'k');
    ClaudeSettings.instance.debugSet(useClaude: false, key: '');
  });

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('redo_run');
    final database = await db.database;
    for (final t in ['mybooks', 'bookseries', 'syncstate']) {
      await database.delete(t);
    }
    await db.savePreference('bookStorageDirectory', dir.path);
    await db.savePreference(redoTranslationBooksPref, '');
    GlossaryService.instance.directory = () async => dir;
    fake = _Fake();
    service.translatorOverride = () async => fake;
  });

  tearDown(() async {
    await service.cancelRedo();
    service.translatorOverride = null;
    for (final language in const [true, false]) {
      (await TranslationCache.open(
              bookFileName: 'witch2.epub',
              targetLanguage: 'ko',
              modelId: TranslationCache.sharedModelId(lightNovel: language)))
          .forget();
    }
    dir.deleteSync(recursive: true);
  });

  /// A book whose first four paragraphs are translated, the last not.
  Future<TranslationCache> book(String file) async {
    File('${dir.path}/$file')
        .writeAsBytesSync(_epub([flower, blue, weather, meeting, road]));
    await db.insert(_book(file, file));
    await GlossaryService.instance.save(
        file,
        const BookGlossary(complete: true, entries: [
          GlossaryEntry(
              source: '魔女', target: '마녀', kind: GlossaryKind.person),
        ]));
    final cache = await TranslationEngines.openCache(
        bookFileName: file, targetLanguage: 'ko');
    cache
      ..store(flower, '꽃의 푸른마녀는 웃었다.')
      ..store(blue, '푸른마녀가 왔다.')
      ..store(weather, '오늘은 날씨가 좋았다.')
      ..store(meeting, '푸른마녀 집회는 아직 멀었다.');
    await cache.flush();
    return cache;
  }

  Future<void> finished() async {
    for (var i = 0; i < 200; i++) {
      if (service.redoFiles.isEmpty && !service.running) return;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    fail('the paragraphs were not made again in time');
  }

  test('every paragraph of a book with the word: marked, and translated '
      'at once - those only, a book that is not here passed over',
      () async {
    final cache = await book('witch2.epub');
    await service.start();
    final waiting = await service.redoWord(
        files: ['witch2.epub', 'not_here.epub'], source: '魔女');
    expect(waiting, 3);
    expect(service.redoFiles, ['witch2.epub']);
    await finished();

    // The three with the word, and nothing else: not the one without
    // it, not the one that was never translated.
    expect(fake.asked.toSet(), {flower, blue, meeting});
    expect(fake.asked, hasLength(3));
    expect(cache.lookup(flower), '다시: $flower');
    expect(cache.lookup(meeting), '다시: $meeting');
    expect(cache.lookup(weather), '오늘은 날씨가 좋았다.');
    expect(cache.lookup(road), isNull);
    expect(cache.toRedo, 0);
    expect(await translationsToRedo('witch2.epub'), 0);
    final progress = service.redoProgress['witch2.epub']!;
    expect((progress.done, progress.total), (3, 3));
    // It is not kept asked for.
    expect(await db.getPreference(redoTranslationBooksPref), '[]');
  });

  test('nothing translated has the word: nothing asked for, nothing sent',
      () async {
    await book('witch2.epub');
    await service.start();
    expect(await service.redoWord(files: ['witch2.epub'], source: '勇者'), 0);
    expect(service.redoFiles, isEmpty);
    expect(fake.asked, isEmpty);
  });

  test('marked before (the reader did not open the book since): asked '
      'again, they are made now', () async {
    final cache = await book('witch2.epub');
    await redoTranslationsWith(
        bookFile: 'witch2.epub',
        bookPath: '${dir.path}/witch2.epub',
        source: '青の魔女');
    expect(cache.toRedo, 1);
    await service.start();
    await service.redo(['witch2.epub']);
    await finished();
    expect(fake.asked, [blue]);
    expect(cache.toRedo, 0);
  });
}
