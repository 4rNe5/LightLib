// The web build's entry point (flutter build web -t lib/main_web.dart):
// the library (this browser's books and the account's), the reader,
// Gemini translation and sync. The phone app's other parts (search and
// downloads, the model on the device, widgets, updates) are not part of
// it.
//
// The first frame does not wait for anything: the library's frame shows
// while the database opens and the account answers (web/index.html shows
// the app's name until that frame).

// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // The settings and library database: sqlite (WebAssembly) in IndexedDB.
  databaseFactory = databaseFactoryFfiWeb;
  // Right-click belongs to the library's own menus.
  unawaited(BrowserContextMenu.disableContextMenu());
  runApp(const ProviderScope(child: LightLibWebApp()));
  unawaited(_afterFirstFrame());
}

Future<void> _afterFirstFrame() async {
  // Also finishes a Google sign-in this page was sent back from.
  unawaited(SyncService.instance.init());
  TranslationStyle.lightNovel = await MyLibraryDb.instance
          .getPreference(translationLightNovelStylePref)
          .catchError((_) => null) !=
      0;
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
