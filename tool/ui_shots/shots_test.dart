// Pictures of the app's own screens at a phone's size and an unfolded
// foldable's, drawn by the real widgets over a real (ffi) database -
// what a change to the library, a book's page or the opening picture
// looks like, without a device.
//
//   SHOT_COVERS=<dir with books.json and cover pictures> \
//   SHOT_FONTS=<dir with Nunito-<weight>.ttf> SHOT_OUT=<dir> \
//   flutter test --no-pub tool/ui_shots/shots_test.dart
//
// See README.md here.

// Dart imports:
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Package imports:
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/bookwalker.dart';
import 'package:openlib/services/database.dart';
import 'package:openlib/services/library_organization.dart';
import 'package:openlib/state/state.dart';
import 'package:openlib/ui/book_navigation.dart';
import 'package:openlib/ui/components/app_nav_bar.dart';
import 'package:openlib/ui/components/book_opening.dart';
import 'package:openlib/ui/home_page.dart';
import 'package:openlib/ui/mylibrary_page.dart';
import 'package:openlib/ui/search_page.dart';
import 'package:openlib/ui/settings_page.dart';
import 'package:openlib/ui/themes.dart';

String _env(String name, String otherwise) =>
    Platform.environment[name] ?? otherwise;

final _covers = _env('SHOT_COVERS', '');
final _fonts = _env('SHOT_FONTS', '');
final _out = _env('SHOT_OUT', '/tmp/lightlib_shots/out');

class _Paths extends PathProviderPlatform {
  Future<String> _dir(String name) async {
    final dir = Directory('/tmp/lightlib_shots/app/$name');
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

/// A screen to draw on: its size in dp, and where it folds (if it does).
class _Screen {
  const _Screen(this.name, this.size, {this.fold = false});
  final String name;
  final Size size;
  final bool fold;
}

const _phone = _Screen('phone', Size(411, 914));
const _unfolded = _Screen('fold', Size(750, 832), fold: true);
const _dpr = 2.0;

Future<void> _loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    var any = false;
    for (final f in files) {
      final file = File(f);
      if (!file.existsSync()) continue;
      any = true;
      final bytes = file.readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    if (any) await loader.load();
  }

  await family('Nunito', [
    for (final w in [400, 500, 600, 700, 800, 900]) '$_fonts/Nunito-$w.ttf'
  ]);
  await family('ShotCJK', [
    for (final w in ['Regular', 'Medium', 'Bold', 'Black'])
      '/usr/share/fonts/opentype/noto/NotoSansCJK-$w.ttc',
  ]);
  // Text styled without the theme (a chip's label, a pill over a cover)
  // is drawn in the system's font on a device.
  for (final name in ['Roboto', 'FlutterTest']) {
    await family(name, [
      for (final w in ['Regular', 'Medium', 'Bold', 'Black'])
        '/usr/share/fonts/opentype/noto/NotoSansCJK-$w.ttc',
    ]);
  }
  final flutter = File(Platform.resolvedExecutable).parent.parent.parent;
  await family('MaterialIcons', [
    '${flutter.path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
    '/opt/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ]);
}

ThemeData _theme(ThemeData base) => base.copyWith(
      textTheme: base.textTheme
          .apply(fontFamily: 'Nunito', fontFamilyFallback: const ['ShotCJK']),
      primaryTextTheme: base.primaryTextTheme
          .apply(fontFamily: 'Nunito', fontFamilyFallback: const ['ShotCJK']),
    );

/// The app's frame round [page]: the tabs' bar under it on a phone, the
/// rail beside it on a wide screen (as `MainScreen` lays them out).
class _Shell extends StatelessWidget {
  const _Shell({required this.page, this.tab = 2});

  final Widget page;
  final int tab;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = [
      AppNavItem(
          icon: Icons.explore_outlined,
          selectedIcon: Icons.explore_rounded,
          label: l10n.navHome),
      AppNavItem(
          icon: Icons.search_rounded,
          selectedIcon: Icons.manage_search_rounded,
          label: l10n.navSearch),
      AppNavItem(
          icon: Icons.collections_bookmark_outlined,
          selectedIcon: Icons.collections_bookmark_rounded,
          label: l10n.navMyLibrary),
      AppNavItem(
          icon: Icons.settings_outlined,
          selectedIcon: Icons.settings_rounded,
          label: l10n.navSettings),
    ];
    if (useNavRail(context)) {
      return Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: SafeArea(right: false, child: page)),
            AppNavRail(selectedIndex: tab, onSelected: (_) {}, items: items),
          ],
        ),
      );
    }
    return Scaffold(
      body: SafeArea(bottom: false, child: page),
      bottomNavigationBar: SafeArea(
        child: AppNavBar(selectedIndex: tab, onSelected: (_) {}, items: items),
      ),
    );
  }
}

final _shot = GlobalKey();

/// The app's theme in the pictures: dark (the owner's), or light with
/// `SHOT_THEME=light` (the pictures are then named `light_…`).
final _light = _env('SHOT_THEME', 'dark') == 'light';

Widget _app(Widget home,
        {Brightness? brightness,
        Key? key,
        List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: RepaintBoundary(
        key: _shot,
        child: MaterialApp(
          // (Under the picture's own key: a new key here is a new app.)
          key: key,
          debugShowCheckedModeBanner: false,
          locale: const Locale('ko'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: _theme(lightTheme),
          darkTheme: _theme(darkTheme),
          themeMode: (brightness ??
                      (_light ? Brightness.light : Brightness.dark)) ==
                  Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light,
          home: home,
        ),
      ),
    );

void _use(WidgetTester tester, _Screen screen) {
  tester.view.devicePixelRatio = _dpr;
  tester.view.physicalSize = screen.size * _dpr;
  // The status bar and the gesture bar's room.
  tester.view.padding =
      const FakeViewPadding(top: 30 * _dpr, bottom: 16 * _dpr);
  tester.view.viewPadding =
      const FakeViewPadding(top: 30 * _dpr, bottom: 16 * _dpr);
  tester.view.displayFeatures = [
    if (screen.fold)
      ui.DisplayFeature(
        // (Logical pixels, as the engine gives them.)
        bounds: Rect.fromLTWH(screen.size.width / 2, 0, 0, screen.size.height),
        type: ui.DisplayFeatureType.fold,
        state: ui.DisplayFeatureState.postureFlat,
      ),
  ];
}

/// Lets pictures load (real file reads) and the frame after them come.
Future<void> _settle(WidgetTester tester, {int frames = 14}) async {
  // (The database answers in real time, a step at a time: each step
  // needs a pump to be heard.)
  for (var i = 0; i < 24; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump(const Duration(milliseconds: 16));
  }
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<void> _save(WidgetTester tester, String name) async {
  final boundary =
      _shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _dpr);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$_out/${_light ? 'light_' : ''}$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
  });
}

/// The books of the pictures: `books.json` of [_covers] (title, author,
/// cover file, what it is about), or a few without covers.
List<Map<String, dynamic>> _manifest() {
  final file = File('$_covers/books.json');
  if (_covers.isEmpty || !file.existsSync()) {
    return [
      for (var i = 1; i <= 9; i++)
        {'title': 'A book, volume $i', 'author': 'Its writer'},
    ];
  }
  return (jsonDecode(file.readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
}

/// The library the pictures are of: books in reading order, some read
/// part of the way, one finished, two series.
Future<List<MyBook>> _seed() async {
  final db = MyLibraryDb.instance;
  final database = await db.database;
  for (final t in [
    'mybooks',
    'bookposition',
    'booktags',
    'bookgenre',
    'bookseries',
    'syncstate',
    'readingdays',
    'completions',
  ]) {
    await database.delete(t);
  }
  final books = <MyBook>[];
  final manifest = _manifest();
  for (var i = 0; i < manifest.length; i++) {
    final m = manifest[i];
    final cover = m['cover'] as String?;
    final book = MyBook(
      id: 'shot$i',
      title: '${m['title']}',
      author: '${m['author'] ?? ''}',
      thumbnail: cover == null ? null : '$_covers/$cover',
      link: 'https://example.com/shot$i',
      publisher: null,
      info: null,
      format: 'epub',
      // (What a book is about comes with the books too: nothing of a
      // real book is written in this file.)
      description: m['description'] as String?,
    );
    books.add(book);
    await db.insert(book);
  }
  final now = DateTime.now();
  Future<void> read(int i, double fraction, Duration ago,
      {bool done = false}) async {
    if (i >= books.length) return;
    final file = books[i].getFileName();
    await db.saveBookState(file, 'reader:epubcfi(/6/8!/4/2)');
    await db.setSyncState('frac:$file', fraction.toStringAsFixed(4));
    await db.setSyncState(
        'pos:$file', '${now.subtract(ago).millisecondsSinceEpoch}');
    if (done) {
      await db.setCompleted(file, true, now.subtract(ago));
      await db.setSyncState(
          'pos:$file', '${now.subtract(ago).millisecondsSinceEpoch}');
    }
  }

  await read(books.length - 1, 0.62, const Duration(hours: 3));
  await read(1, 0.18, const Duration(days: 2));
  await read(5, 0.41, const Duration(days: 6));
  await read(3, 1, const Duration(days: 9), done: true);
  if (books.length > 7) {
    await db.setSeries([books[6].id, books[7].id],
        suggestedSeriesName([books[6].title, books[7].title]));
  }
  await db.setGenre(books.last.id, BookGenre.lightNovel.key);
  for (final back in [0, 1, 2, 3, 5, 6, 7, 9, 10, 13, 14, 15, 20, 21, 24]) {
    await db.recordReadingDay(now.subtract(Duration(days: back)));
  }
  return books;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    PathProviderPlatform.instance = _Paths();
    // ignore: invalid_use_of_visible_for_testing_member
    PackageInfo.setMockInitialValues(
        appName: 'LightLib',
        packageName: 'dev.arne5.lightlib',
        version: '2.0.0',
        buildNumber: '2072',
        buildSignature: '');
    await _loadFonts();
  });

  for (final screen in [_phone, _unfolded]) {
    testWidgets('library, a book, the opening picture: ${screen.name}',
        (tester) async {
      _use(tester, screen);
      addTearDown(tester.view.reset);
      late List<MyBook> books;
      await tester.runAsync(() async => books = await _seed());

      await tester.pumpWidget(_app(const _Shell(page: MyLibraryPage())));
      await _settle(tester);
      await _save(tester, '${screen.name}_1_library');

      // Further down: the series and the shelf.
      final scroll = find.byType(CustomScrollView).first;
      await tester.drag(scroll, const Offset(0, -560));
      await _settle(tester, frames: 6);
      await _save(tester, '${screen.name}_2_library_shelf');
      await tester.drag(scroll, const Offset(0, 900));
      await _settle(tester, frames: 6);

      // The book being read: its page (a phone) or the pane beside the
      // shelf (unfolded).
      await tester.tap(find.byKey(const ValueKey('bentoHero')));
      await _settle(tester);
      await _save(tester, '${screen.name}_3_book');

      // A finished book.
      final container = ProviderScope.containerOf(
          tester.element(find.byType(MyLibraryPage, skipOffstage: false)));
      if (screen.fold) {
        container.read(libraryDetailProvider.notifier).state = books[3].id;
        await _settle(tester);
        await _save(tester, '${screen.name}_4_book_finished');
      }

      // The opening picture.
      final library = await tester
          .runAsync(() => container.read(libraryBooksProvider.future));
      final reading = continueReading(library!).first;
      await tester.pumpWidget(_app(
          key: UniqueKey(),
          Builder(
            builder: (context) => BookOpeningView(
              book: reading,
              progress: reading.progress,
              label:
                  AppLocalizations.of(context).bookOpeningAt(reading.percent!),
              onClose: () {},
            ),
          )));
      await _settle(tester);
      await _save(tester, '${screen.name}_5_opening');
    });
  }

  for (final screen in [_phone, _unfolded]) {
    testWidgets('settings, search: ${screen.name}', (tester) async {
      _use(tester, screen);
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        final db = MyLibraryDb.instance;
        await (await db.database).delete('searchhistory');
        // (What was searched before: the first books' own titles.)
        for (final m in _manifest().take(3)) {
          await db.addSearchHistory('${m['title']}');
        }
      });
      await tester.pumpWidget(
          _app(key: UniqueKey(), const _Shell(tab: 3, page: SettingsPage())));
      await _settle(tester);
      await _save(tester, '${screen.name}_6_settings');
      if (screen.fold) {
        await tester.tap(find.byKey(const ValueKey('settingsCategory-1')));
        await _settle(tester, frames: 8);
        await _save(tester, '${screen.name}_7_settings_display');
        await tester.tap(find.byKey(const ValueKey('settingsCategory-2')));
        await _settle(tester, frames: 8);
      } else {
        await tester.scrollUntilVisible(
            find.byKey(const ValueKey('settingsReaderDefaults')), 300,
            scrollable: find.byType(Scrollable).first);
        await tester.drag(
            find.byType(Scrollable).first, const Offset(0, -260));
        await _settle(tester, frames: 8);
      }
      // How every book opens, set from the settings.
      await _save(tester, '${screen.name}_7b_settings_reader');
      await tester.pumpWidget(
          _app(key: UniqueKey(), const _Shell(tab: 1, page: SearchPage())));
      await _settle(tester);
      await _save(tester, '${screen.name}_8_search');
    });
  }

  for (final screen in [_phone, _unfolded]) {
    testWidgets('home: ${screen.name}', (tester) async {
      _use(tester, screen);
      addTearDown(tester.view.reset);
      // What sells now, as the store would list it: the pictures' own
      // books, twice over.
      final manifest = _manifest();
      final selling = [
        for (var round = 0; round < 2; round++)
          for (final m in manifest.reversed)
            BookWalkerBook(
              title: '${m['title']}',
              cover: m['cover'] == null ? '' : '$_covers/${m['cover']}',
            ),
      ];
      await tester.pumpWidget(_app(
        key: UniqueKey(),
        const _Shell(tab: 0, page: HomePage()),
        overrides: [
          japanPopularProvider.overrideWith((ref, category) async => selling),
        ],
      ));
      await _settle(tester);
      await _save(tester, '${screen.name}_9_home');
    });
  }
}
