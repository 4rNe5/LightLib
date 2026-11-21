// Builds the real SettingsPage with a real (ffi-backed) database and provider
// scope. Regression coverage on the page structure: every section header and
// tile renders, and the theme dropdown commits through to the provider.
// The DB persistence of setTheme itself is covered by a plain (real-zone)
// test below, because real sqlite I/O freezes inside the widget-test fake
// async zone.

// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/reader_settings.dart';
import 'package:openlib/state/state.dart';
import 'package:openlib/ui/settings_page.dart';
import 'package:openlib/l10n/app_localizations.dart';

class _FakePathProvider extends PathProviderPlatform {
  static const base = '/tmp/openlib_settings_test';

  @override
  Future<String?> getApplicationSupportPath() async => base;

  @override
  Future<String?> getApplicationDocumentsPath() async => base;

  @override
  Future<String?> getTemporaryPath() async => base;

  @override
  Future<String?> getLibraryPath() async => base;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    PathProviderPlatform.instance = _FakePathProvider();
    Directory(_FakePathProvider.base).createSync(recursive: true);
  });

  // A phone, unless [wide]: the test window is 800 x 600, where the page
  // shows its categories beside the chosen one's settings.
  Future<void> pumpPage(WidgetTester tester, {bool wide = false}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = wide ? const Size(750, 832) : const Size(411, 914);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          home: const Scaffold(body: SettingsPage()),
        ),
      ),
    );
    // Bounded pumping: the page starts async work (instance providers,
    // PackageInfo) that can keep animations running, so pumpAndSettle is
    // not reliable here.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('renders all sections and tiles', (tester) async {
    await pumpPage(tester);

    for (final label in [
      'Search Providers',
      'Library & Instances',
      'Appearance',
      'General',
      'Reader',
      'Advanced',
      'Updates',
      'About',
    ]) {
      expect(find.text(label), findsOneWidget,
          reason: 'section header "$label" must render');
    }

    for (final label in [
      'Mirrors & Providers',
      'Theme',
      'Font Size',
      'Storage Location',
      'Open PDF externally',
      'Open EPUB externally',
      'Manual Download Button',
      "Anna's Archive Donation Key",
      'Include Beta Updates',
      'Check for Updates',
      'About LightLib',
      'Redo Onboarding',
      'Export Logs',
    ]) {
      expect(find.text(label), findsOneWidget,
          reason: 'tile "$label" must render');
    }
  });

  testWidgets('theme segments update the provider state', (tester) async {
    await pumpPage(tester);

    // The search-provider section pushes the theme row below the default
    // test viewport - drag it into view first.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('themeSegments')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Dark'));
    await tester.pump(const Duration(milliseconds: 600));

    // The state change inside setTheme is synchronous; only the disk write
    // would freeze in the fake async zone.
    final element = tester.element(find.byType(SettingsPage));
    final container = ProviderScope.containerOf(element);
    expect(container.read(themeModeProvider), ThemeMode.dark,
        reason: 'selecting Dark theme must update the provider state');
  });

  testWidgets('wide: the categories on one side, the chosen one beside',
      (tester) async {
    await pumpPage(tester, wide: true);

    // The first category's settings are there without a tap; the others'
    // are not built.
    expect(find.byKey(const ValueKey('settingsPane-0')), findsOneWidget);
    expect(find.text('Mirrors & Providers'), findsOneWidget);
    expect(find.byKey(const ValueKey('themeSegments')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('settingsCategory-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const ValueKey('settingsPane-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('themeSegments')), findsOneWidget);
    expect(find.text('Mirrors & Providers'), findsNothing);

    // Every category can be reached, and none overflows its pane.
    for (var i = 2; i < 5; i++) {
      await tester.tap(find.byKey(ValueKey('settingsCategory-$i')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(ValueKey('settingsPane-$i')), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    expect(find.text('Check for Updates'), findsOneWidget);
  });

  // How every book opens is set from Settings too: the reader's own
  // settings (its "Aa" sheet), the same store.
  testWidgets("the reader's defaults: in the list on a phone", (tester) async {
    addTearDown(ReaderSettings.instance.resetForTest);
    await pumpPage(tester);
    final defaults = find.byKey(const ValueKey('settingsReaderDefaults'));
    await tester.scrollUntilVisible(defaults, 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.descendant(of: defaults, matching: find.text('Reader defaults')),
        findsOneWidget);
    // No heading with a close button, no font rows: this is a page.
    expect(find.byKey(const ValueKey('readerFontRow')), findsNothing);
    expect(find.byTooltip('Close'), findsNothing);

    final twoPages = find.byKey(const ValueKey('twoPages'));
    await tester.scrollUntilVisible(twoPages, 200,
        scrollable: find.byType(Scrollable).first);
    expect(ReaderSettings.instance.value.twoPages, isTrue);
    await tester.tap(twoPages);
    await tester.pump();
    expect(ReaderSettings.instance.value.twoPages, isFalse);
    expect(tester.widget<SwitchListTile>(twoPages).value, isFalse);

    // Text size: the same control as in the reader.
    final size = ReaderSettings.instance.value.fontSize;
    final larger = find.byTooltip('Increase font size');
    await tester.scrollUntilVisible(larger, -200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(larger);
    await tester.pump();
    expect(ReaderSettings.instance.value.fontSize, greaterThan(size));
    expect(tester.takeException(), isNull);
  });

  testWidgets("the reader's defaults: under reading, in a narrow pane",
      (tester) async {
    addTearDown(ReaderSettings.instance.resetForTest);
    await pumpPage(tester, wide: true);
    expect(find.byKey(const ValueKey('settingsReaderDefaults')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('settingsCategory-2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(
        find.byKey(const ValueKey('settingsReaderDefaults')), findsOneWidget);
    // (The fonts and translation are under it, as before.)
    expect(find.text('Fonts'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test('setTheme persists the selected mode', () async {
    final notifier = ThemeModeNotifier(ThemeMode.light);
    await notifier.setTheme(ThemeMode.dark);

    final saved = await MyLibraryDb.instance.getPreference('themeMode');
    expect(saved, 'dark',
        reason: 'setTheme must persist the mode to the preferences table');
  });
}
