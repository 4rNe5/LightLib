// The web build's entry point (flutter build web -t lib/main_web.dart):
// the library in this browser, the reader, Gemini translation and sync.
// The phone app's other parts (search and downloads, the model on the
// device, widgets, updates) are not part of it.

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/database.dart';
import 'package:openlib/services/sync/sync_service.dart';
import 'package:openlib/services/translation/translation_models.dart';
import 'package:openlib/ui/themes.dart';
import 'package:openlib/web/web_library_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The settings and library database: sqlite (WebAssembly) in IndexedDB.
  databaseFactory = databaseFactoryFfiWeb;
  final db = MyLibraryDb.instance;
  await db.database;
  TranslationStyle.lightNovel = await db
          .getPreference(translationLightNovelStylePref)
          .catchError((_) => null) !=
      0;
  // Also finishes a Google sign-in this page was sent back from.
  await SyncService.instance.init();
  runApp(const ProviderScope(child: LightLibWebApp()));
}

class LightLibWebApp extends StatelessWidget {
  const LightLibWebApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'LightLib',
        debugShowCheckedModeBanner: false,
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: ThemeMode.system,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const WebLibraryPage(),
      );
}
