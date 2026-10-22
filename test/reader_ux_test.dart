// Reader UX tests that mount the viewer with a real epub file: the font
// size controls in the app bar and the SelectionArea around the book text.
// These live apart from epub_viewer_test.dart because mounting the viewer
// against a real document starts sqlite work whose sqflite busy-watchers
// only drain in this file's own test run.

// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Package imports:
import 'package:archive/archive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

// Project imports:
import 'package:openlib/services/reader_settings.dart';
import 'package:openlib/ui/components/paged_book_view.dart';
import 'package:openlib/ui/epub_viewer.dart';
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/state/state.dart' show filePathProvider;

class _FakePathProvider extends PathProviderPlatform {
  Future<String> _dir(String name) async {
    final dir = Directory('/tmp/openlib_reader_test/$name');
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      PathProviderPlatform.instance = _FakePathProvider();
    }
  });

  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('openlib_reader_test');
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  testWidgets('text size lives in the Themes & Settings sheet',
      (tester) async {
    final file = File('${tmpDir.path}/sample.epub');
    _writeMinimalEpub(file);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        filePathProvider.overrideWith((ref, fileName) => file.path),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const EpubViewerWidget(fileName: 'sample.epub'),
      ),
    ));

    await tester.pump();
    await tester.pump();

    // The app bar no longer carries size buttons; the "Aa" button opens
    // the sheet that does.
    expect(find.byTooltip('Increase font size'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('readerSettingsButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Themes & Settings'), findsOneWidget);
    expect(find.byKey(const ValueKey('theme-paper')), findsOneWidget);
    expect(find.byKey(const ValueKey('readerLayoutSegments')), findsOneWidget);

    String size() => (tester
            .widget<Text>(find.byKey(const ValueKey('readerFontSizeValue')))
            .data)!;
    final before = int.parse(size());
    await tester.tap(find.byTooltip('Increase font size'));
    await tester.pump();
    expect(int.parse(size()), before + 1);
    expect(ReaderSettings.instance.value.fontSize, before + 1);
    await tester.tap(find.byTooltip('Decrease font size'));
    await tester.pump();
    expect(int.parse(size()), before);

    // A theme applies to the page behind the sheet.
    await tester.tap(find.byKey(const ValueKey('theme-paper')));
    await tester.pump();
    expect(ReaderSettings.instance.value.theme, ReaderThemeId.paper);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.backgroundColor, const Color(0xFFF8F1E3));
    await tester.tap(find.byKey(const ValueKey('theme-original')));
    await tester.pump();
    await _drain(tester);
  });

  testWidgets('choosing Pages in the sheet turns the reader into pages',
      (tester) async {
    final file = File('${tmpDir.path}/sample.epub');
    _writeMinimalEpub(file);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        filePathProvider.overrideWith((ref, fileName) => file.path),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const EpubViewerWidget(fileName: 'sample.epub'),
      ),
    ));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('readerSettingsButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.ensureVisible(find.text('Pages'));
    await tester.pump();
    await tester.tap(find.text('Pages'));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(ReaderSettings.instance.value.layout, ReaderLayout.pagesLtr);
    expect(find.byType(PagedBookView), findsOneWidget);
    expect(find.byKey(const ValueKey('pageNumber')), findsWidgets);

    // Back to scrolling for the other tests.
    await tester.ensureVisible(find.text('Scroll'));
    await tester.pump();
    await tester.tap(find.text('Scroll'));
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.byType(PagedBookView), findsNothing);
    await _drain(tester);
  });

  testWidgets('book text is wrapped in a SelectionArea', (tester) async {
    final file = File('${tmpDir.path}/sample.epub');
    _writeMinimalEpub(file);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        filePathProvider.overrideWith((ref, fileName) => file.path),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const EpubViewerWidget(fileName: 'sample.epub'),
      ),
    ));

    await tester.pump();
    await tester.pump();
    expect(find.byType(SelectionArea), findsOneWidget);
    await _drain(tester);
  });
}

/// Lets the viewer's real sqlite and file work finish, then unmounts it,
/// so no timers outlive the test.
Future<void> _drain(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)));
  await tester.pump(const Duration(seconds: 11));
}

/// Writes a structurally valid minimal EPUB 3 book.
void _writeMinimalEpub(File file) {
  final archive = Archive();
  archive.addFile(ArchiveFile('mimetype', 20, 'application/epub+zip'.codeUnits)
    ..compression = CompressionType.none);
  archive.addFile(ArchiveFile.string('META-INF/container.xml', '''
<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>'''));
  archive.addFile(ArchiveFile.string('OEBPS/content.opf', '''
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="bookid">urn:uuid:0d3f1a5a-9d0a-4d0e-a4e9-6b6e6f6f6e6e</dc:identifier>
    <dc:title>Sample Book</dc:title>
    <dc:language>en</dc:language>
  </metadata>
  <manifest>
    <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="ch1"/>
  </spine>
</package>'''));
  archive.addFile(ArchiveFile.string('OEBPS/chapter1.xhtml', '''
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
  <head><title>Chapter 1</title></head>
  <body><h1>Sample Chapter</h1><p>Hello reader.</p></body>
</html>'''));

  archive.addFile(ArchiveFile.string('OEBPS/nav.xhtml', '''
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
  <head><title>Contents</title></head>
  <body><nav epub:type="toc"><ol><li><a href="chapter1.xhtml">Chapter 1</a></li></ol></nav></body>
</html>'''));

  archive.addFile(ArchiveFile.string('OEBPS/toc.ncx', '''
<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head><meta name="dtb:uid" content="urn:uuid:0d3f1a5a-9d0a-4d0e-a4e9-6b6e6f6f6e6e"/></head>
  <docTitle><text>Sample Book</text></docTitle>
  <navMap>
    <navPoint id="p1" playOrder="1">
      <navLabel><text>Chapter 1</text></navLabel>
      <content src="chapter1.xhtml"/>
    </navPoint>
  </navMap>
</ncx>'''));

  final data = ZipEncoder().encode(archive);
  file.writeAsBytesSync(data);
}
