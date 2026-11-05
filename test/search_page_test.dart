// The Search tab: the field and its filter sheet, the filters in force
// under it, suggestions from the store and Google, and the Japanese title
// of a Korean one.

// Dart imports:
import 'dart:convert';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/bookwalker.dart';
import 'package:openlib/services/google_suggest_api.dart';
import 'package:openlib/services/original_title.dart';
import 'package:openlib/services/search_history.dart';
import 'package:openlib/services/translation/book_glossary.dart';
import 'package:openlib/services/translation/translator.dart';
import 'package:openlib/state/state.dart';
import 'package:openlib/ui/search_page.dart';

class _Engine implements Translator {
  _Engine(this.answer);
  final String? answer;
  int asked = 0;
  bool disposed = false;
  @override
  String? get deviceLabel => null;
  @override
  int get batchSize => 1;
  @override
  Future<void> load() async {}
  @override
  Future<String> translate(String text,
          {required String targetLanguage,
          String? sourceLanguage,
          String? context,
          String? following,
          TranslationPriority priority =
              TranslationPriority.background}) async =>
      text;
  @override
  Future<List<String>> translateBatch(List<String> texts,
          {required String targetLanguage,
          String? sourceLanguage,
          List<String> before = const [],
          List<String?> beforeTranslations = const [],
          Map<String, String> readings = const {},
          BookGlossary glossary = BookGlossary.empty,
          TranslationPriority priority = TranslationPriority.background,
          void Function(int index, String translation)? onEach}) async =>
      texts;
  @override
  Future<String?> complete(String prompt,
      {required int maxTokens,
      TranslationPriority priority = TranslationPriority.background,
      String? head}) async {
    asked++;
    return answer;
  }

  @override
  Future<void> dispose() async => disposed = true;
}

class _Originals extends OriginalTitles {
  _Originals(this.result) : super(engine: () async => null);
  final List<String>? result;
  int asked = 0;
  @override
  Future<List<String>?> known(String korean) async => null;
  @override
  Future<List<String>?> lookup(String korean) async {
    asked++;
    return result;
  }
}

void main() {
  test('Japanese titles read from an answer', () {
    expect(
        parseOriginalTitles(
            '```json\n{"titles": ["死亡遊戯で飯を食う。", "Shibou Yuugi", "死亡遊戯で飯を食う。"]}\n```'),
        ['死亡遊戯で飯を食う。']);
    expect(parseOriginalTitles('{"titles": []}'), isEmpty);
    expect(parseOriginalTitles('no idea'), isEmpty);
    expect(hasHangul('사망유희로 밥을 먹는다'), isTrue);
    expect(hasHangul('死亡遊戯'), isFalse);
    expect(originalTitlePrompt('사망유희'), endsWith('Korean title: 사망유희'));
  });

  test('the engine is asked once; it is let go after', () async {
    final engine = _Engine('{"titles": ["死亡遊戯で飯を食う。"]}');
    final o = OriginalTitles(engine: () async => engine);
    // No database in this test: the lookup still answers.
    expect(await o.lookup('사망유희'), ['死亡遊戯で飯を食う。']);
    expect(engine.disposed, isTrue);
    expect(engine.asked, 1);
    expect(await OriginalTitles(engine: () async => null).lookup('사망'), isNull);
  });

  test('Google suggestions in Japanese; a failure is no suggestion',
      () async {
    Uri? asked;
    final api = GoogleSuggestApi(
        client: MockClient((r) async {
      asked = r.url;
      return http.Response.bytes(
          utf8.encode('["死亡",["死亡遊戯で飯を食う","死亡遊戯"]]'), 200);
    }));
    expect(await api.fetchSuggestions('死亡'), ['死亡遊戯で飯を食う', '死亡遊戯']);
    expect(asked!.queryParameters['hl'], 'ja');
    final down = GoogleSuggestApi(
        client: MockClient((_) async => http.Response('', 503)));
    expect(await down.fetchSuggestions('x'), isEmpty);
    final broken =
        GoogleSuggestApi(client: MockClient((_) async => throw Exception('x')));
    expect(await broken.fetchSuggestions('x'), isEmpty);
  });

  Future<void> pump(WidgetTester tester, {OriginalTitles? originals}) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        searchHistoryProvider.overrideWith((ref) async => const <String>[]),
        selectedLanguageState.overrideWith((ref) => 'Japanese'),
        selectedFileTypeState.overrideWith((ref) => 'Epub'),
      ],
      child: MaterialApp(
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SearchPage(
            suggestApi: GoogleSuggestApi(
                client: MockClient((_) async =>
                    http.Response.bytes(
                    utf8.encode('["q",["死亡遊戯 10巻"]]'), 200))),
            store: (_) async => const [
              BookWalkerBook(
                  title: '死亡遊戯で飯を食う。10【電子特典付き】',
                  cover: 'https://example.com/c.jpg',
                  author: '鵜飼有志'),
            ],
            originalTitles: originals ?? _Originals(null),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('filters in force show under the field; the sheet changes them',
      (tester) async {
    await pump(tester);
    expect(find.text('작품명·작가 (한국어도 OK)'), findsOneWidget);
    expect(find.byKey(const ValueKey('filterSummary')), findsOneWidget);
    expect(find.text('일본어'), findsOneWidget);
    expect(find.text('EPUB'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('searchFilters')));
    await tester.pumpAndSettle();
    expect(find.text('필터'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('lang-All')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('format-All')));
    await tester.pump();
    Navigator.of(tester.element(find.byKey(const ValueKey('lang-All'))))
        .pop();
    await tester.pumpAndSettle();
    // Nothing set: no summary.
    expect(find.byKey(const ValueKey('filterSummary')), findsNothing);
  });

  testWidgets('typing: the store\'s titles and Google\'s, as suggestions',
      (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const ValueKey('searchField')), '死亡');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    // The store's title shows as the series name the libraries list.
    expect(find.text('死亡遊戯で飯を食う'), findsOneWidget);
    expect(find.text('BOOK☆WALKER 작품'), findsOneWidget);
    expect(find.text('死亡遊戯 10巻'), findsOneWidget);
    expect(find.byKey(const ValueKey('originalTitle')), findsNothing);
  });

  testWidgets('a Korean title: the Japanese one, on a tap', (tester) async {
    final originals = _Originals(['死亡遊戯で飯を食う。']);
    await pump(tester, originals: originals);
    await tester.enterText(
        find.byKey(const ValueKey('searchField')), '사망유희로 밥을 먹는다');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(originals.asked, 0);
    await tester.tap(find.byKey(const ValueKey('findOriginalTitle')));
    await tester.pump();
    await tester.pump();
    expect(originals.asked, 1);
    expect(find.byKey(const ValueKey('original-死亡遊戯で飯を食う。')),
        findsOneWidget);
  });

  testWidgets('a Korean title without translation set up says so',
      (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const ValueKey('searchField')), '사망유희');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('findOriginalTitle')));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('원제를 찾으려면 번역'), findsOneWidget);
  });
}
