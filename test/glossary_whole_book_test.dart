// A book's glossary made with Gemini: the book is read whole first, and
// the candidates' way is asked only about what that left unnamed.

// Dart imports:
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// Package imports:
import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/services/translation/book_glossary.dart';
import 'package:openlib/services/translation/gemini/cloud_translator.dart';
import 'package:openlib/services/translation/gemini/gemini_api.dart';
import 'package:openlib/services/translation/gemini/gemini_client.dart';
import 'package:openlib/services/translation/gemini/gemini_settings.dart';
import 'package:openlib/services/translation/glossary_service.dart';

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

/// Gemini, as a stand-in: [whole] answers a request to read the book
/// (one with the names' schema), [lines] one about candidates.
class _Gemini implements HttpClientAdapter {
  _Gemini({required this.whole, required this.lines});
  final (int, String) Function(String part) whole;
  final String Function(String prompt) lines;
  final List<String> parts = [];
  final List<String> prompts = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    final body = options.data as Map;
    final user = ((body['contents'] as List).first['parts'] as List)
        .first['text'] as String;
    final reads = jsonEncode(body).contains('"entries"');
    var status = 200;
    final String text;
    if (reads) {
      parts.add(user);
      (status, text) = whole(user);
    } else {
      prompts.add(user);
      text = lines(user);
    }
    final data = status != 200
        ? {
            'error': {'code': status, 'status': 'UNAVAILABLE', 'message': 'x'}
          }
        : {
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': text}
                  ]
                },
                'finishReason': 'STOP'
              }
            ],
            'usageMetadata': {
              'promptTokenCount': 100,
              'candidatesTokenCount': 20
            },
          };
    return ResponseBody.fromString(jsonEncode(data), status, headers: {
      'content-type': ['application/json']
    });
  }

  @override
  void close({bool force = false}) {}
}

/// Answers a request about candidates: [known] (source → the answer's
/// text) on the line of each candidate the request numbers.
String _answer(String prompt, Map<String, String> known) => [
      for (final m
          in RegExp(r'^\[(\d+)\] (\S+)', multiLine: true).allMatches(prompt))
        if (known[m.group(2)!.split('(').first] != null)
          '[${m.group(1)}] ${known[m.group(2)!.split('(').first]}',
    ].join('\n');

void main() {
  final settings = GeminiSettings.instance;
  late Directory dir;
  late File book;
  final service = GlossaryService.instance;

  CloudTranslator gemini(_Gemini server) => CloudTranslator(
        client: GeminiClient(
            dio: Dio()..httpClientAdapter = server,
            settings: settings,
            sleep: (_) async {}),
        settings: settings,
        device: () async => null,
      );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('glossary_whole');
    service.directory = () async => dir;
    settings.debugSet(
        useGemini: true,
        key: 'test-key',
        deviceFallback: false,
        usage: GeminiUsage(day: quotaDay(DateTime.now())));
    const yuna = '<ruby>結奈<rt>ゆな</rt></ruby>';
    book = File('${dir.path}/book.epub')
      ..writeAsBytesSync(_epub([
        for (var i = 0; i < 4; i++) ...[
          // No furigana, no honorific: 風宮 is no candidate.
          '風宮は聖剣を抜いた。',
          '「$yunaさん、下がって」と風宮が言うと、$yunaは頷いた。',
          '「わかりました」と$yunaは答えた。',
          '上野の街は静かだった。上野駅まで歩く。',
          '「しずくちゃん」と呼ぶと、しずくは振り向いた。しずくの髪が揺れた。',
        ],
      ]));
  });
  tearDown(() {
    GlossaryService.seriesOf = null;
    dir.deleteSync(recursive: true);
  });

  String answer(List<Map<String, String>> entries) =>
      jsonEncode({'entries': entries});

  test('the book read whole: names nothing points to, the book\'s own '
      'spelling, and no second question about them', () async {
    final server = _Gemini(
      whole: (_) => (
        200,
        answer([
          {'src': '風宮', 'reading': 'かざみや', 'kind': 'person', 'ko': '카자미야', 'gender': 'male', 'speech': 'casual'},
          {'src': '結奈', 'reading': 'ゆうな', 'kind': 'person', 'ko': '유우나', 'gender': 'female', 'speech': 'polite'},
          {'src': '聖剣', 'reading': 'せいけん', 'kind': 'item', 'ko': '성검'},
          {'src': '魔王', 'reading': 'まおう', 'kind': 'person', 'ko': '마왕'},
          // "A drop" to the engine.
          {'src': 'しずく', 'reading': 'しずく', 'kind': 'term', 'ko': '물방울'},
        ])
      ),
      lines: (_) => fail('everything was named already'),
    );
    final glossary = await service.make(
        bookFile: 'whole.epub', bookPath: book.path, translator: gemini(server));
    expect(server.parts.length, 1);
    expect(server.parts.single, contains('風宮は聖剣を抜いた。'));
    expect(server.prompts, isEmpty);
    final by = {for (final e in glossary.entries) e.source: e};
    expect(by['風宮']!.target, '카자미야');
    expect(by['風宮']!.gender, GlossaryGender.male);
    // The book reads it ゆな.
    expect(by['結奈']!.target, '유나');
    expect(by['聖剣']!.target, '성검');
    // Not in the book.
    expect(by.containsKey('魔王'), isFalse);
    // Called しずくちゃん in the book: someone, by the name as written.
    expect(by['しずく']!.target, '시즈쿠');
    expect(by['しずく']!.kind, GlossaryKind.person);
    // A place the book names without a reading.
    expect(by['上野']!.target, '우에노');
    expect(glossary.complete, isTrue);
    expect(glossary.version, BookGlossary.currentVersion);
  });

  test('what the reading left unnamed is asked the candidates\' way',
      () async {
    final server = _Gemini(
      whole: (_) => (
        200,
        answer([
          {'src': '風宮', 'reading': 'かざみや', 'kind': 'person', 'ko': '카자미야'},
        ])
      ),
      lines: (prompt) {
        expect(prompt, contains('結奈'));
        expect(prompt, isNot(contains('] 風宮')));
        return _answer(prompt, const {'結奈': '유나 | person | female | polite'});
      },
    );
    final glossary = await service.make(
        bookFile: 'part.epub', bookPath: book.path, translator: gemini(server));
    expect(server.prompts.length, 1);
    final by = {for (final e in glossary.entries) e.source: e};
    expect(by['風宮']!.target, '카자미야');
    expect(by['結奈']!.target, '유나');
    expect(by['結奈']!.gender, GlossaryGender.female);
  });

  test('Gemini does not read the book: the candidates\' way alone',
      () async {
    final server = _Gemini(
      whole: (_) => (503, ''),
      lines: (prompt) =>
          _answer(prompt, const {'結奈': '유나 | person | female | polite'}),
    );
    final glossary = await service.make(
        bookFile: 'down.epub', bookPath: book.path, translator: gemini(server));
    final by = {for (final e in glossary.entries) e.source: e};
    expect(by['結奈']!.target, '유나');
    expect(by.containsKey('風宮'), isFalse);
    // No answer about her at all: the book's own word for her name.
    expect(by['しずく']!.target, '시즈쿠');
    expect(by['しずく']!.isName, isTrue);
    expect(glossary.complete, isTrue);
  });

  test('another volume of the series gives the reading this one lacks',
      () async {
    GlossaryService.seriesOf = (file) async => [
          const BookGlossary(complete: true, entries: [
            GlossaryEntry(
                source: '風宮',
                target: '카자미야',
                reading: 'かざみや',
                kind: GlossaryKind.person,
                gender: GlossaryGender.male),
          ]),
        ];
    final server = _Gemini(
      whole: (_) => (503, ''),
      lines: (prompt) =>
          _answer(prompt, const {'結奈': '유나 | person | female | polite'}),
    );
    final glossary = await service.make(
        bookFile: 'series.epub',
        bookPath: book.path,
        translator: gemini(server));
    final by = {for (final e in glossary.entries) e.source: e};
    expect(by['風宮']!.target, '카자미야');
    expect(by['結奈']!.target, '유나');
  });

  test('the reading stops part of the way and nobody answers about the '
      'rest: used as far as it goes, made again next time', () async {
    // A book of several parts.
    const yuna = '<ruby>結奈<rt>ゆな</rt></ruby>';
    final long = File('${dir.path}/long.epub')
      ..writeAsBytesSync(_epub([
        for (var i = 0; i < 900; i++) ...[
          '風宮は聖剣を抜いた。風宮の剣は青く光り、あたりは昼のように明るくなった。',
          '「$yunaさん、下がって」と風宮が言うと、$yunaは頷いた。',
        ],
      ]));
    var parts = 0;
    _Gemini server({required bool lines}) => _Gemini(
          whole: (_) => ++parts == 1
              ? (
                  200,
                  answer([
                    {'src': '風宮', 'reading': 'かざみや', 'kind': 'person', 'ko': '카자미야'},
                  ])
                )
              : (503, ''),
          lines: (prompt) => lines
              ? _answer(
                  prompt, const {'結奈': '유나 | person | female | polite'})
              : '',
        );
    final cut = await service.make(
        bookFile: 'cut.epub',
        bookPath: long.path,
        translator: gemini(server(lines: false)));
    expect(parts, greaterThan(1));
    expect(cut.entries.firstWhere((e) => e.source == '風宮').target, '카자미야');
    expect(cut.complete, isFalse);

    // The rest answered about the candidates' way: that will do.
    parts = 0;
    final done = await service.make(
        bookFile: 'cut2.epub',
        bookPath: long.path,
        translator: gemini(server(lines: true)));
    expect(done.entries.firstWhere((e) => e.source == '結奈').target, '유나');
    expect(done.complete, isTrue);
  });
}
