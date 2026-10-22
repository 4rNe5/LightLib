// Reader settings model, the light-novel style switch in the prompt, the
// marquee title and the library's bento/grid tiles.

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/database.dart';
import 'package:openlib/services/library_organization.dart';
import 'package:openlib/services/reader_settings.dart';
import 'package:openlib/services/translation/translation_models.dart';
import 'package:openlib/ui/components/library_tiles.dart';
import 'package:openlib/ui/components/marquee_text.dart';
import 'package:openlib/ui/components/paged_book_view.dart' show ReaderLayout;

LibraryBook _book(String id, String title,
        {ReadingStatus status = ReadingStatus.unread, BookGenre? genre}) =>
    LibraryBook(
      book: MyBook(
        id: id,
        title: title,
        author: 'Author $id',
        thumbnail: null,
        link: 'https://example.com/$id',
        publisher: null,
        info: null,
        format: 'epub',
        description: null,
      ),
      status: status,
      genre: genre,
    );

Widget _app(Widget child, {bool disableAnimations = false}) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
            size: const Size(400, 800), disableAnimations: disableAnimations),
        child: Scaffold(body: child),
      ),
    );

void main() {
  group('ReaderSettingsData', () {
    test('values are clamped to their ranges', () {
      final s = const ReaderSettingsData().copyWith(
        fontSize: 99,
        lineHeight: 0.1,
        letterSpacing: 9,
        margin: -3,
      );
      expect(s.fontSize, ReaderSettingsData.maxFontSize);
      expect(s.lineHeight, ReaderSettingsData.minLineHeight);
      expect(s.letterSpacing, ReaderSettingsData.maxLetterSpacing);
      expect(s.margin, ReaderSettingsData.minMargin);
    });

    test('JSON round trip keeps every field', () {
      const s = ReaderSettingsData(
        fontSize: 21,
        lineHeight: 2.0,
        letterSpacing: 0.4,
        margin: 30,
        justify: true,
        boldText: true,
        theme: ReaderThemeId.calm,
        layout: ReaderLayout.pagesRtl,
      );
      expect(ReaderSettingsData.fromJson(s.toJson()), s);
    });

    test('garbage and missing fields fall back to defaults', () {
      final s = ReaderSettingsData.fromJson(
          {'theme': 'nope', 'layout': 42, 'justify': 'yes', 'fontSize': 18});
      expect(s.theme, ReaderThemeId.original);
      expect(s.layout, ReaderLayout.scroll);
      expect(s.fontSize, 18);
      expect(s.justify, isFalse);
      expect(s.lineHeight, const ReaderSettingsData().lineHeight);
    });

    test('reset keeps the theme and layout, restores typography', () {
      final s = const ReaderSettingsData().copyWith(
        fontSize: 30,
        margin: 40,
        justify: true,
        theme: ReaderThemeId.night,
        layout: ReaderLayout.pagesLtr,
      );
      final r = s.resetTypography();
      expect(r.theme, ReaderThemeId.night);
      expect(r.layout, ReaderLayout.pagesLtr);
      expect(r.fontSize, const ReaderSettingsData().fontSize);
      expect(r.justify, isFalse);
    });

    test('palettes: original follows the app, bold forces weight', () {
      expect(paletteFor(ReaderThemeId.original, appDark: true).dark, isTrue);
      expect(paletteFor(ReaderThemeId.original, appDark: false).dark, isFalse);
      expect(paletteFor(ReaderThemeId.paper, appDark: true).dark, isFalse);
      final bold = paletteFor(ReaderThemeId.bold, appDark: false);
      expect(const ReaderSettingsData().boldFor(bold), isTrue);
      expect(
          const ReaderSettingsData()
              .boldFor(paletteFor(ReaderThemeId.quiet, appDark: false)),
          isFalse);
    });
  });

  group('light-novel style switch', () {
    test('on: light-novel and Korean narration rules are in the prompt', () {
      final p = translationPrompt(
          text: 'せ、先輩っ！', targetLanguage: 'Korean', sourceLanguage: 'Japanese');
      expect(p, contains('Japanese light novel'));
      expect(p, contains('선배'));
      expect(p, contains('-다'));
    });

    test('off: only neutral rules, the text and output rule remain', () {
      final p = translationPrompt(
        text: 'せ、先輩っ！',
        targetLanguage: 'Korean',
        sourceLanguage: 'Japanese',
        lightNovelStyle: false,
      );
      expect(p, isNot(contains('light novel')));
      expect(p, isNot(contains('선배')));
      expect(p, isNot(contains('-다')));
      expect(p, contains('accurate, natural Korean'));
      expect(p, contains('Output only the Korean translation'));
      expect(p.trimRight(), endsWith('せ、先輩っ！'));
    });

    test('each style has its own cache id', () {
      TranslationStyle.lightNovel = true;
      expect(TranslationStyle.cacheModelId('m.litertlm'), 'm.litertlm');
      TranslationStyle.lightNovel = false;
      expect(TranslationStyle.cacheModelId('m.litertlm'), 'm.litertlm+plain');
      TranslationStyle.lightNovel = true;
    });
  });

  group('MarqueeText', () {
    double offsetOf(WidgetTester tester) {
      final transforms = tester.widgetList<Transform>(find.descendant(
          of: find.byType(MarqueeText), matching: find.byType(Transform)));
      if (transforms.isEmpty) return 0;
      return transforms.first.transform.getTranslation().x;
    }

    testWidgets('a title that fits stays still', (tester) async {
      await tester.pumpWidget(_app(const Center(
        child: SizedBox(width: 300, child: MarqueeText('Short')),
      )));
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('Short'), findsOneWidget);
      expect(offsetOf(tester), 0);
    });

    testWidgets('a long title rests, then scrolls', (tester) async {
      const title = 'An extremely long light novel title that never fits';
      await tester.pumpWidget(_app(const Center(
        child: SizedBox(width: 80, child: MarqueeText(title)),
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(offsetOf(tester), 0, reason: 'still in the opening pause');
      await tester.pump(const Duration(seconds: 3));
      expect(offsetOf(tester), lessThan(0));
      // Two copies so the loop is seamless.
      expect(find.text(title), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('reduced motion shows an ellipsis instead', (tester) async {
      const title = 'An extremely long light novel title that never fits';
      await tester.pumpWidget(_app(
        const Center(child: SizedBox(width: 80, child: MarqueeText(title))),
        disableAnimations: true,
      ));
      await tester.pump(const Duration(seconds: 4));
      expect(find.text(title), findsOneWidget);
      expect(tester.widget<Text>(find.text(title)).overflow,
          TextOverflow.ellipsis);
    });
  });

  group('library tiles', () {
    testWidgets('bento hero continues the book being read', (tester) async {
      await tester.pumpWidget(_app(SingleChildScrollView(
        child: LibraryBentoPanel(
          books: [
            _book('new', 'Newest'),
            _book('mid', 'Halfway', status: ReadingStatus.inProgress),
            _book('also', 'Also Reading', status: ReadingStatus.inProgress),
            _book('done', 'Done', status: ReadingStatus.completed),
          ],
          onOpen: (_) {},
        ),
      ), disableAnimations: true));
      await tester.pump();
      expect(find.text('Continue reading'), findsOneWidget);
      final hero = find.byKey(const ValueKey('bentoHero'));
      // Placeholder covers carry the title too, hence several matches.
      expect(find.descendant(of: hero, matching: find.text('Halfway')),
          findsWidgets);
      expect(find.descendant(of: hero, matching: find.text('Newest')),
          findsNothing);
      // Total books and finished count in the stats card.
      expect(find.text('4'), findsOneWidget);
      expect(find.text('1 finished'), findsOneWidget);
      // The second book being read gets the small card.
      expect(find.text('Also Reading'), findsWidgets);
    });

    testWidgets('without a book in progress the newest is featured',
        (tester) async {
      LibraryBook? opened;
      await tester.pumpWidget(_app(SingleChildScrollView(
        child: LibraryBentoPanel(
          books: [_book('new', 'Newest'), _book('old', 'Oldest')],
          onOpen: (b) => opened = b,
        ),
      ), disableAnimations: true));
      await tester.pump();
      expect(find.text('Recently added'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('bentoHero')));
      expect(opened?.id, 'new');
    });

    testWidgets('grid tile shows title, author, genre and progress',
        (tester) async {
      var taps = 0;
      var longPresses = 0;
      await tester.pumpWidget(_app(Center(
        child: SizedBox(
          width: 120,
          height: 120 * 1.5 + LibraryGridTile.captionHeight,
          child: LibraryGridTile(
            book: _book('ln', 'Death Game',
                status: ReadingStatus.completed, genre: BookGenre.lightNovel),
            onTap: () => taps++,
            onLongPress: () => longPresses++,
          ),
        ),
      ), disableAnimations: true));
      await tester.pump();
      // Title shows on the placeholder cover and in the caption.
      expect(find.text('Death Game'), findsNWidgets(2));
      expect(find.text('Author ln'), findsOneWidget);
      expect(find.text('Light novel'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byType(LibraryGridTile));
      await tester.longPress(find.byType(LibraryGridTile));
      expect(taps, 1);
      expect(longPresses, 1);
    });

    testWidgets('every genre has a label in Korean', (tester) async {
      late AppLocalizations l10n;
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (context) {
          l10n = AppLocalizations.of(context);
          return const SizedBox();
        }),
      ));
      final labels = BookGenre.values.map((g) => genreLabel(l10n, g)).toSet();
      expect(labels.length, BookGenre.values.length);
      expect(genreLabel(l10n, BookGenre.lightNovel), '라이트노벨');
      expect(genreLabel(l10n, BookGenre.paper), '논문');
    });
  });
}
