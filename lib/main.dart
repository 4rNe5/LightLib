import 'dart:async';
// Dart imports:
import 'dart:io' show Platform;

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:openlib/ui/components/app_nav_bar.dart';
import 'package:openlib/ui/home_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:desktop_webview_window/desktop_webview_window.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/database.dart' show MyLibraryDb;
import 'package:openlib/services/translation/book_translation_service.dart';
import 'package:openlib/services/reader_fonts.dart';
import 'package:openlib/services/process_exits.dart';
import 'package:openlib/services/platform_utils.dart';
import 'package:openlib/services/challenge_html_cache.dart';
import 'package:openlib/services/webview_challenge_solver.dart';
import 'package:openlib/services/update_checker.dart';
import 'package:openlib/services/upgrade_detector.dart';
import 'package:openlib/ui/mylibrary_page.dart';
import 'package:openlib/ui/search_page.dart';
import 'package:openlib/ui/settings_page.dart';
import 'package:openlib/ui/themes.dart';
import 'package:openlib/ui/onboarding/onboarding_page.dart';
import 'package:openlib/ui/challenge_solver_page.dart';
import 'package:openlib/ui/whats_new_page.dart';
import 'package:openlib/ui/mybook_page.dart' show BookPage;
import 'package:openlib/services/home_widgets.dart';
import 'package:openlib/services/reading_recap.dart';

import 'package:openlib/services/files.dart'
    show moveFilesToAndroidInternalStorage;
import 'package:openlib/services/download_manager.dart';
import 'package:openlib/services/download_notification.dart';
import 'package:openlib/services/instance_manager.dart';
import 'package:openlib/state/state.dart'
    show
        ThemeModeNotifier,
        libraryBooksProvider,
        selectedIndexProvider,
        themeModeProvider,
        fontSizeScaleProvider,
        localeOverrideProvider,
        openPdfWithExternalAppProvider,
        openEpubWithExternalAppProvider,
        showManualDownloadButtonProvider,
        backgroundVerificationProvider,
        userAgentProvider,
        cookieProvider,
        donationKeyProvider,
        selectedTypeState,
        selectedSortState,
        selectedFileTypeState,
        selectedLanguageState,
        selectedYearState;

void main(List<String> args) async {
  // Required for desktop_webview_window on Linux - must be called before ensureInitialized
  if (Platform.isLinux || Platform.isWindows) {
    if (runWebViewTitleBarWidget(args)) {
      return;
    }
  }
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  MyLibraryDb dataBase = MyLibraryDb.instance;

  await DownloadManager().initialize();

  ThemeMode startThemeMode = await ThemeModeNotifier.getInitialTheme();

  double fontSizeScale = 1.0;
  try {
    var pref =
        await dataBase.getPreference('fontSizeScale').catchError((e) => 1.0);
    if (pref is num) {
      fontSizeScale = pref.toDouble();
    } else if (pref is String) {
      fontSizeScale = double.tryParse(pref) ?? 1.0;
    }
  } catch (e) {
    fontSizeScale = 1.0;
  }

  bool openPdfwithExternalapp = await dataBase
              .getPreference('openPdfwithExternalApp')
              .catchError((e) => null) ==
          0
      ? false
      : true;

  bool openEpubwithExternalapp = await dataBase
              .getPreference('openEpubwithExternalApp')
              .catchError((e) => null) ==
          0
      ? false
      : true;

  bool showManualDownloadButton = await dataBase
              .getPreference('showManualDownloadButton')
              .catchError((e) => null) ==
          0
      ? false
      : true;

  // Stored as 0 = off; anything else (or missing) = headless on.
  bool backgroundVerification = await dataBase
              .getPreference('backgroundVerification')
              .catchError((e) => null) ==
          0
      ? false
      : true;
  WebviewChallengeSolver.headlessEnabled = backgroundVerification;

  String browserUserAgent = await dataBase.getBrowserOptions('userAgent');
  String browserCookie = await dataBase.getBrowserOptions('cookie');

  // Load search filter preferences
  String savedType = await dataBase
          .getPreference('filterType')
          .catchError((e) => 'All') as String? ??
      'All';
  String savedSort = await dataBase
          .getPreference('filterSort')
          .catchError((e) => 'Most Relevant') as String? ??
      'Most Relevant';
  String savedFileType = await dataBase
          .getPreference('filterFileType')
          .catchError((e) => 'All') as String? ??
      'All';
  String savedLanguage = await dataBase
          .getPreference('filterLanguage')
          .catchError((e) => 'All') as String? ??
      'All';
  String savedYear = await dataBase
          .getPreference('filterYear')
          .catchError((e) => 'All') as String? ??
      'All';

  String savedDonationKey = await dataBase
          .getPreference('donationKey')
          .catchError((e) => '') as String? ??
      '';

  // Load saved language override; empty or unknown values follow the
  // system locale.
  final savedLocaleCode =
      await dataBase.getPreference('locale').catchError((e) => '') as String? ??
          '';
  Locale? startLocale;
  final supported = AppLocalizations.supportedLocales;
  for (final locale in supported) {
    if (locale.languageCode == savedLocaleCode) startLocale = locale;
  }

  // Check onboarding status
  bool onboardingCompleted = await dataBase
          .getPreference('onboardingCompleted')
          .catchError((e) => 0) ==
      1;

  // Upgrade check: shows the what's-new screen once after a real
  // version bump (never on first install - onboarding covers that).
  // A failed check must not block startup.
  UpgradeCheck? upgrade;
  try {
    upgrade = await UpgradeDetector().checkAndRecord();
  } catch (_) {
    upgrade = null;
  }

  if (Platform.isAndroid) {
    // Android-specific setup for system UI overlay colors
    ThemeModeNotifier.updateSystemUi(startThemeMode);
    await moveFilesToAndroidInternalStorage();
  }

  // When the invisible (headless) DDoS solve fails on mobile, show the
  // solver as a visible page instead - the user watches the check clear
  // and the app closes the page as soon as the HTML is captured.
  WebviewChallengeSolver.visibleSolverFallback = (url) async {
    final context = _navigatorKey.currentContext;
    if (context == null) return null;
    final solved = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChallengeSolverPage(url: url)),
    );
    return solved == true ? ChallengeHtmlCache.get(url) : null;
  };

  // Fonts chosen per script (and imported font files) before first frame.
  await ReaderFonts.instance.load().catchError((_) {});

  // Library books are translated in the background, a little at a time,
  // when a model is installed and the option is on.
  unawaited(ProcessExits.logNew());
  unawaited(BookTranslationService.instance.start());

  runApp(
    ProviderScope(
      overrides: [
        themeModeProvider
            .overrideWith((ref) => ThemeModeNotifier(startThemeMode)),
        fontSizeScaleProvider.overrideWith((ref) => fontSizeScale),
        localeOverrideProvider.overrideWith((ref) => startLocale),
        openPdfWithExternalAppProvider
            .overrideWith((ref) => openPdfwithExternalapp),
        openEpubWithExternalAppProvider
            .overrideWith((ref) => openEpubwithExternalapp),
        showManualDownloadButtonProvider
            .overrideWith((ref) => showManualDownloadButton),
        backgroundVerificationProvider
            .overrideWith((ref) => backgroundVerification),
        donationKeyProvider.overrideWith((ref) => savedDonationKey),
        userAgentProvider.overrideWith((ref) => browserUserAgent),
        cookieProvider.overrideWith((ref) => browserCookie),
        selectedTypeState.overrideWith((ref) => savedType),
        selectedSortState.overrideWith((ref) => savedSort),
        selectedFileTypeState.overrideWith((ref) => savedFileType),
        selectedLanguageState.overrideWith((ref) => savedLanguage),
        selectedYearState.overrideWith((ref) => savedYear),
      ],
      child: MyApp(
        onboardingCompleted: onboardingCompleted,
        upgrade: upgrade,
      ),
    ),
  );
}

/// Scrolling tuned for the snappy complaint on newer Androids: touch
/// input gets momentum-based physics with a clamped stop at the edges
/// (no iOS-style bounce-back), so lists decelerate naturally instead of
/// halting on a dime when the finger lifts.
class _SmoothScrollBehavior extends MaterialScrollBehavior {
  const _SmoothScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics(
      decelerationRate: ScrollDecelerationRate.fast,
      parent: AlwaysScrollableScrollPhysics(),
    );
  }
}

/// Global navigator so the challenge-solver fallback (a service, not a
/// widget) can push the visible solver page from anywhere.
final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

class MyApp extends ConsumerWidget {
  final bool onboardingCompleted;

  /// Non-null with [UpgradeCheck.isUpgrade] when this launch follows a
  /// version bump; drives the what's-new screen.
  final UpgradeCheck? upgrade;
  const MyApp({super.key, this.onboardingCompleted = false, this.upgrade});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      scrollBehavior: const _SmoothScrollBehavior(),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: ref.watch(localeOverrideProvider),
      builder: (context, child) {
        final scale = ref.watch(fontSizeScaleProvider);
        // The fonts chosen in the reader settings are for books only; the
        // app's own screens keep the theme font.
        return MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        );
      },
      debugShowCheckedModeBanner: false,
      title: 'OpenlibExtended',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ref.watch(themeModeProvider),
      home: !onboardingCompleted
          ? const OnboardingPage()
          : (upgrade?.isUpgrade ?? false)
              ? WhatsNewPage(
                  fromVersion: upgrade!.fromVersion,
                  toVersion: upgrade!.toVersion,
                )
              : const MainScreen(),
    );
  }
}

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen>
    with WidgetsBindingObserver {
  static const List<Widget> _widgetOptions = <Widget>[
    HomePage(),
    SearchPage(),
    MyLibraryPage(),
    SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A tap on a home-screen widget opens its book or the library.
    HomeWidgets.instance.pending.addListener(_onWidgetAction);
    unawaited(HomeWidgets.instance.init());
    WidgetsBinding.instance.addPostFrameCallback((_) => _onWidgetAction());
    // Request notification permission after first frame (only on mobile)
    if (PlatformUtils.isMobile) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkAndRequestNotificationPermission();
      });
    }
    // Check for updates after the app has loaded
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdatesOnStartup();
    });
    // Pull the mirror list from open-slum.org so the first search does
    // not wait on it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshMirrorsOnStartup();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android suspends the process soon after the user leaves the app,
    // which cuts sockets mid-download ("Connection closed while
    // receiving data"). Coming back to the foreground, every paused or
    // failed download continues from its partial file instead of dying.
    if (state == AppLifecycleState.resumed) {
      DownloadManager().resumeInterruptedDownloads();
    }
  }

  @override
  void dispose() {
    HomeWidgets.instance.pending.removeListener(_onWidgetAction);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onWidgetAction() {
    final action = HomeWidgets.instance.pending.value;
    if (action == null || !mounted) return;
    HomeWidgets.instance.pending.value = null;
    // The library tab under the book, so "back" lands there.
    ref.read(selectedIndexProvider.notifier).state = 2;
    final id = action.bookId;
    if (id != null) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => BookPage(id: id)))
          .then((_) {
        if (mounted) ref.invalidate(libraryBooksProvider);
      });
    }
  }

  /// The home-screen widgets show the library as it is now.
  void _updateHomeWidgets() {
    final books = ref.read(libraryBooksProvider).valueOrNull;
    if (books == null) return;
    final recap = ref.read(readingRecapProvider).valueOrNull;
    HomeWidgets.instance.update(
      books: books,
      recap: recap == null || recap.total == 0 ? null : recap,
      l10n: AppLocalizations.of(context),
      localeTag: Localizations.localeOf(context).toLanguageTag(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The language may have changed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateHomeWidgets();
    });
  }

  Future<void> _refreshMirrorsOnStartup() async {
    // Small delay to let the UI settle first.
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    await InstanceManager().refreshOnStartup();
  }

  Future<void> _checkForUpdatesOnStartup() async {
    // Small delay to let the UI settle
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    try {
      await UpdateCheckerService().checkAndShowUpdateDialog(context);
    } catch (e) {
      // Silently fail on startup - user can manually check in settings
      debugPrint("Update check failed: $e");
    }
  }

  Future<void> _checkAndRequestNotificationPermission() async {
    // Skip on desktop platforms
    if (PlatformUtils.isDesktop) return;

    // Check if we should show the permission dialog
    final prefs = MyLibraryDb.instance;
    final hasAskedBefore = await prefs
        .getPreference('hasAskedNotificationPermission')
        .catchError((_) => 0);

    if (hasAskedBefore == 0) {
      // Check current permission status
      final notificationService = DownloadNotificationService();
      final currentStatus =
          await notificationService.checkNotificationPermission();

      if (!currentStatus && mounted) {
        // Show the contextual dialog first
        _showNotificationPermissionDialog();
      } else {
        // Already granted, just mark as asked
        await prefs.savePreference('hasAskedNotificationPermission', 1);
      }
    }
  }

  void _showNotificationPermissionDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            AppLocalizations.of(context).enableNotifications,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.secondary,
            ),
          ),
          content: Text(
            AppLocalizations.of(context).notificationsExplanation,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context)
                  .colorScheme
                  .tertiary
                  .withValues(alpha: 0.78),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Don't mark as asked so we can ask again later
              },
              child: Text(
                AppLocalizations.of(context).maybeLater,
                style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .tertiary
                      .withValues(alpha: 0.67),
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                // Request permission when user clicks Enable
                await DownloadNotificationService()
                    .requestNotificationPermission();
                // Mark that we've asked
                await MyLibraryDb.instance
                    .savePreference('hasAskedNotificationPermission', 1);
              },
              child: Text(
                AppLocalizations.of(context).enable,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = ref.watch(selectedIndexProvider);
    final l10n = AppLocalizations.of(context);
    if (HomeWidgets.instance.supported) {
      ref.listen(libraryBooksProvider, (_, __) => _updateHomeWidgets());
      ref.listen(readingRecapProvider, (_, __) => _updateHomeWidgets());
    }

    // No shared app bar: each tab draws its own large title (Home,
    // Search, My Library, Settings) and pushed pages carry the title of
    // what they show.
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: AppTabSwitcher(
          index: selectedIndex,
          child: _widgetOptions.elementAt(selectedIndex),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: AppNavBar(
          selectedIndex: selectedIndex,
          onSelected: (index) =>
              ref.read(selectedIndexProvider.notifier).state = index,
          items: [
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
          ],
        ),
      ),
    );
  }
}
