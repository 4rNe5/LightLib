// The translation settings page: the recommended preset, the per-model
// prompt format picker with its auto-detected default, the override that
// it saves, and the warning for a Korean-only format.

// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Package imports:
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/database.dart';
import 'package:openlib/services/translation/translation_model_store.dart';
import 'package:openlib/services/translation/translation_models.dart';
import 'package:openlib/ui/translation_settings_page.dart';

class _FakePathProvider extends PathProviderPlatform {
  Future<String> _dir(String name) async {
    final dir = Directory('/tmp/openlib_translation_settings_test/$name');
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
  late Directory models;
  const dialogueModel = 'ja-ko-qwen35-2b-ctxB-dpo195-Q4_K_M.gguf';

  setUpAll(() {
    final stale = Directory('/tmp/openlib_translation_settings_test');
    if (stale.existsSync()) stale.deleteSync(recursive: true);
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    PathProviderPlatform.instance = _FakePathProvider();
  });

  setUp(() async {
    models = Directory.systemTemp.createTempSync('tmodels');
    File('${models.path}/$dialogueModel').writeAsBytesSync([0, 1, 2]);
    TranslationModelStore.instance.directoryProvider = () async => models;
    TranslationPromptFormats.overrides = {};
  });

  tearDown(() {
    models.deleteSync(recursive: true);
    TranslationPromptFormats.overrides = {};
  });

  Future<void> settle(WidgetTester tester, [bool Function()? done]) async {
    // Until [done] holds (slow CI runners need more frames), at least 8.
    for (var i = 0; i < 80; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump();
      if (i >= 7 && (done == null || done())) break;
    }
  }

  testWidgets('presets, auto-detected format, override and Korean-only note',
      (tester) async {
    final db = MyLibraryDb.instance;
    await tester.runAsync(() async {
      await db.savePreference(selectedTranslationModelPref, dialogueModel);
      await db.savePreference(translationTargetLanguagePref, 'ko');
      await db.savePreference(TranslationPromptFormats.pref, '{}');
    });
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: TranslationSettingsPage(database: db),
    ));
    // The page lists files and reads preferences when the store changes;
    // run that on the real event loop so the file and database calls end.
    await tester.runAsync(() async {
      await TranslationModelStore.instance.select(dialogueModel, database: db);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await settle(tester,
        () => find.byKey(const ValueKey('promptFormat')).evaluate().isNotEmpty);

    // E4B is listed first and recommended; every preset is offered.
    for (final preset in translationModelPresets) {
      expect(find.byKey(ValueKey('preset-${preset.id}')), findsOneWidget);
    }
    expect(
        find.descendant(
            of: find.byKey(ValueKey('preset-${gemma4E4bLiteRt.id}')),
            matching: find.textContaining('recommended · RAM 8 GB or more')),
        findsOneWidget);

    expect(
        find.byKey(const ValueKey('imported-$dialogueModel')), findsOneWidget);
    // The imported dialogue model is active; its format is detected.
    expect(find.byKey(const ValueKey('promptFormat')), findsOneWidget);
    expect(find.text('Auto (Japanese→Korean dialogue model)'), findsOneWidget);
    expect(find.byKey(const ValueKey('promptFormatKoreanOnly')), findsNothing);

    // Override to Hy-MT: kept in memory and in the preference.
    await tester.tap(find.byKey(const ValueKey('promptFormat')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Hy-MT translation model').last);
    await settle(tester);
    expect(TranslationPromptFormats.overrides[dialogueModel],
        TranslationPromptFormat.hyMt);
    final saved = await tester
        .runAsync(() => db.getPreference(TranslationPromptFormats.pref));
    expect(TranslationPromptFormats.decode(saved as String),
        {dialogueModel: TranslationPromptFormat.hyMt});

    // Back to the dialogue format, then a target it cannot translate into.
    await tester.tap(find.byKey(const ValueKey('promptFormat')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Japanese→Korean dialogue model').last);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('translationTarget')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('English').last);
    await settle(
        tester,
        () => find
            .byKey(const ValueKey('promptFormatKoreanOnly'))
            .evaluate()
            .isNotEmpty);
    expect(
        find.byKey(const ValueKey('promptFormatKoreanOnly')), findsOneWidget);
  });
}
