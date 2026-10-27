// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'LightLib';

  @override
  String get navHome => 'Home';

  @override
  String get navSearch => 'Search';

  @override
  String get navMyLibrary => 'My Library';

  @override
  String get navSettings => 'Settings';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get add => 'Add';

  @override
  String get delete => 'Delete';

  @override
  String get retry => 'Retry';

  @override
  String get advancedSearch => 'Advanced Search';

  @override
  String get author => 'Author';

  @override
  String get publisher => 'Publisher';

  @override
  String get searchLibraryHint =>
      'Search library (title, author, publisher, year)';

  @override
  String get newCollection => 'New collection';

  @override
  String get noResultsFound => 'No results found';

  @override
  String resultsFor(String query) {
    return 'Results for \'$query\'';
  }

  @override
  String get followSystem => 'Follow the System';

  @override
  String get lightTheme => 'Light theme';

  @override
  String get darkTheme => 'Dark theme';

  @override
  String get languageSetting => 'Language';

  @override
  String get systemLanguage => 'System default';

  @override
  String get enableNotifications => 'Enable Notifications';

  @override
  String get notificationsExplanation =>
      'LightLib needs notification permission to show download progress in the background. This helps you track your book downloads even when the app is minimized.';

  @override
  String get maybeLater => 'Maybe Later';

  @override
  String get enable => 'Enable';

  @override
  String get statusUnread => 'Unread';

  @override
  String get statusInProgress => 'In Progress';

  @override
  String get statusCompleted => 'Completed';

  @override
  String get collectionNameHint => 'e.g. Favorites, Sci-Fi';

  @override
  String get manageCollectionsHint =>
      'Long-press any book to manage its collections';

  @override
  String get results => 'Results';

  @override
  String get loading => 'Loading...';

  @override
  String get unknown => 'Unknown';

  @override
  String get about => 'About';

  @override
  String get aboutDescription =>
      'An Open source app to download and read books from shadow library (Anna\'s Archive).';

  @override
  String get aboutForkNote =>
      'This is a forked version maintained by warreth for personal use and community updates.';

  @override
  String get aboutOriginalNote =>
      'Original app by dstark5 (https://github.com/dstark5/Openlib).';

  @override
  String get version => 'Version';

  @override
  String get github => 'Github';

  @override
  String get thisForkByWarreth => 'This Fork (by warreth)';

  @override
  String get reportAnIssue => 'Report An Issue';

  @override
  String get originalProject => 'Original Project (by dstark5)';

  @override
  String get licence => 'Licence';

  @override
  String get gplLicense => 'GPL v3.0 license';

  @override
  String couldNotLaunch(String url) {
    return 'Could not launch $url';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get searchProvidersSection => 'Search Providers';

  @override
  String get libraryInstancesSection => 'Library & Instances';

  @override
  String get appearanceSection => 'Appearance';

  @override
  String get generalSection => 'General';

  @override
  String get readerSection => 'Reader';

  @override
  String get advancedSection => 'Advanced';

  @override
  String get backupSection => 'Backup';

  @override
  String get updatesSection => 'Updates';

  @override
  String get aboutSection => 'About';

  @override
  String get archiveInstance => 'Archive Instance';

  @override
  String get mirrorsAndProviders => 'Mirrors & Providers';

  @override
  String get fontSizeTitle => 'Font Size';

  @override
  String scaleValue(String value) {
    return 'Scale: ${value}x';
  }

  @override
  String get preview => 'Preview';

  @override
  String get storageLocation => 'Storage Location';

  @override
  String get openPdfExternally => 'Open PDF externally';

  @override
  String get useDefaultPdfViewer => 'Use your default PDF viewer';

  @override
  String get openEpubExternally => 'Open EPUB externally';

  @override
  String get useDefaultEpubReader => 'Use your default EPUB reader';

  @override
  String get manualDownloadButton => 'Manual Download Button';

  @override
  String get backgroundVerification => 'Verify challenges in background';

  @override
  String get backgroundVerificationHint =>
      'Solve DDoS checks invisibly. Some devices fail this - turn it off to verify in a visible window instead';

  @override
  String get backgroundVerificationFix =>
      'If verification keeps failing, try turning off \"Verify challenges in background\" in Settings - some devices cannot solve checks invisibly.';

  @override
  String get showManualDownloadHint =>
      'Show button to manually trigger downloads';

  @override
  String get donationKeyTitle => 'Anna\'s Archive Donation Key';

  @override
  String get enterKeyForFasterDownloads => 'Enter key for faster downloads';

  @override
  String get aboutOpenlib => 'About LightLib';

  @override
  String get redoOnboarding => 'Redo Onboarding';

  @override
  String get resetAppSetup => 'Reset app setup and start over';

  @override
  String get exportLogs => 'Export Logs';

  @override
  String get shareDiagnosticLogs => 'Share diagnostic logs (last 5 min)';

  @override
  String failedExportLogs(String error) {
    return 'Failed to export logs: $error';
  }

  @override
  String get donationKeyDialog => 'Donation Key';

  @override
  String get enterYourKey => 'Enter your key';

  @override
  String get instanceChanged => 'Instance changed successfully';

  @override
  String rankingFailed(String error) {
    return 'Ranking failed: $error';
  }

  @override
  String get autoRankInstances => 'Auto-Rank Instances';

  @override
  String get sortBySpeedOnStartup => 'Automatically sort by speed on startup';

  @override
  String get rankInstancesNow => 'Rank Instances Now';

  @override
  String onLatestVersion(String version) {
    return 'You\'re on the latest version ($version)';
  }

  @override
  String failedCheckUpdates(String error) {
    return 'Failed to check for updates: $error';
  }

  @override
  String get includeBetaUpdates => 'Include Beta Updates';

  @override
  String get getPreReleaseVersions => 'Get pre-release versions';

  @override
  String get checkForUpdates => 'Check for Updates';

  @override
  String get backupSaved => 'Backup saved';

  @override
  String failedExportBackup(String error) {
    return 'Failed to export backup: $error';
  }

  @override
  String get backupRestored => 'Backup restored';

  @override
  String failedImportBackup(String error) {
    return 'Failed to import backup: $error';
  }

  @override
  String get atLeastOneSource => 'At least one search source is needed';

  @override
  String rankedFastest(String name, String time) {
    return 'Ranked! Fastest: $name (${time}ms)';
  }

  @override
  String get rankingComplete => 'Ranking complete';

  @override
  String get providerSourceOriginal =>
      'Searched last - protected by DDoS-Guard';

  @override
  String get providerLibgenCatalog => 'Fast, direct downloads - searched first';

  @override
  String get providerZlibMirrors => 'Mirrors rotate; may need a login';

  @override
  String get themeTitle => 'Theme';

  @override
  String get saveBackupTitle => 'Save Backup';

  @override
  String get pickBackupFile => 'Pick a backup file';

  @override
  String get notABackup => 'That file is not an LightLib backup';

  @override
  String get donationKeyHelper =>
      'Used for faster downloads on Anna\'s Archive';

  @override
  String get mirrorsTestedRanked => 'Mirrors tested and ranked by speed';

  @override
  String testingFailed(String error) {
    return 'Testing failed: $error';
  }

  @override
  String get addCustomMirror => 'Add Custom Mirror';

  @override
  String get nameLabel => 'Name';

  @override
  String get nameHint => 'e.g., My LibGen mirror';

  @override
  String get serviceLabel => 'Service';

  @override
  String get urlLabel => 'URL';

  @override
  String get urlHint => 'https://example.com';

  @override
  String get pleaseFillAllFields => 'Please fill all fields';

  @override
  String get enterValidUrl =>
      'Please enter a valid URL with http:// or https://';

  @override
  String get mirrorAdded => 'Mirror added successfully';

  @override
  String get deleteMirror => 'Delete Mirror';

  @override
  String deleteMirrorConfirm(String name) {
    return 'Are you sure you want to delete \"$name\"?';
  }

  @override
  String get mirrorDeleted => 'Mirror deleted';

  @override
  String get cannotDeleteDefaultMirrors => 'Cannot delete default mirrors';

  @override
  String get manageMirrors => 'Manage Mirrors';

  @override
  String get noMirrorsAvailable => 'No mirrors available';

  @override
  String errorLabel(String error) {
    return 'Error: $error';
  }

  @override
  String get addMirror => 'Add mirror';

  @override
  String get testRankMirrors => 'Test & rank mirrors by speed';

  @override
  String get unreachable => 'unreachable';

  @override
  String get open => 'Open';

  @override
  String get unableToOpenFile => 'Unable to open file!';

  @override
  String get openInSite => 'Open in site';

  @override
  String get bookDeleted => 'Book has been Deleted!';

  @override
  String get deleteBook => 'Delete Book';

  @override
  String get deletePermanentWarning => 'This is permanent and cannot be undone';

  @override
  String get tryAgain => 'Try Again';

  @override
  String get showBlockedContent => 'Show blocked page content';

  @override
  String get verifyInBrowser => 'Verify in Browser';

  @override
  String get manualVerificationRequired => 'Manual Verification Required';

  @override
  String get systemBrowser => 'System Browser';

  @override
  String get embeddedBrowser => 'Embedded Browser';

  @override
  String get unableToOpenVerification =>
      'Unable to open verification page - no URL available';

  @override
  String get blockedPageContent => 'Blocked Page Content';

  @override
  String get copiedToClipboard => 'Copied to clipboard';

  @override
  String get gotIt => 'Got it!';

  @override
  String get copy => 'Copy';

  @override
  String get tryUsingVpn => 'Try using a VPN';

  @override
  String get trending => 'Trending';

  @override
  String get genres => 'Genres';

  @override
  String get copiedBookPath => 'Copied the book path to your clipboard';

  @override
  String get pauseDownload => 'Pause download';

  @override
  String get resumeDownload => 'Resume download';

  @override
  String get cancelDownload => 'Cancel download';

  @override
  String get copiedBookLink => 'Copied the book link to your clipboard';

  @override
  String get noMirrors => 'No mirrors available!';

  @override
  String get addToMyLibrary => 'Add To My Library';

  @override
  String get downloadStartedBackground => 'Download started in background';

  @override
  String get bookDownloaded => 'Book has been downloaded!';

  @override
  String get selectStorageToContinue =>
      'Please select a storage folder to continue';

  @override
  String get getStarted => 'Get Started';

  @override
  String get next => 'Next';

  @override
  String get welcomeTitle => 'Welcome to LightLib';

  @override
  String get welcomeSubtitle =>
      'Your personal gateway to a world of knowledge. Let\'s get you set up.';

  @override
  String get whereToStoreBooks => 'Where should we store your books?';

  @override
  String get noPathSelected => 'No path selected';

  @override
  String get selectFolder => 'Select Folder';

  @override
  String get storageScanNote =>
      'We\'ll only look for PDF/EPUB files in this folder. No recursive scanning of subfolders.';

  @override
  String get automaticUpdates => 'Automatic Updates';

  @override
  String get enableAutoUpdates => 'Enable Auto-Updates';

  @override
  String get autoUpdatesFdroidNote =>
      'Not recommended if you installed via F-Droid (F-Droid handles updates).';

  @override
  String get enableBetaUpdatesOnboarding => 'Enable Beta Updates';

  @override
  String get betaUpdatesNote =>
      'Get pre-release versions (beta updates) when available.';

  @override
  String get supportAnnasArchive => 'Support Anna\'s Archive';

  @override
  String get donationPitch =>
      'Donating to Anna\'s Archive provides faster downloads and helps them keep the service running for everyone. You can enter your secret key below.';

  @override
  String get annasSecretKey => 'Anna\'s Archive Secret Key';

  @override
  String get supportThisApp => 'Support This App';

  @override
  String get sponsorPitch =>
      'If you enjoy this app, consider supporting its development. It helps me dedicate more time to making it better!';

  @override
  String get sponsorOnGithub => 'Sponsor on GitHub';

  @override
  String get stayUpdated => 'Stay Updated';

  @override
  String get notifyOnComplete => 'Get notified when downloads complete.';

  @override
  String get chooseTheme => 'Choose a Theme';

  @override
  String get lightThemeShort => 'Light';

  @override
  String get darkThemeShort => 'Dark';

  @override
  String get verifyingAccess => 'Verifying Access';

  @override
  String get done => 'Done';

  @override
  String get nothingToRead => 'Nothing to read on this page';

  @override
  String get noVoiceAvailable => 'No voice available for reading aloud';

  @override
  String get pauseReadingAloud => 'Pause reading aloud';

  @override
  String get resumeReadingAloud => 'Read aloud';

  @override
  String get stopReadingAloud => 'Stop reading aloud';

  @override
  String get speechSpeed => 'Speech speed';

  @override
  String get decreaseFontSize => 'Decrease font size';

  @override
  String get increaseFontSize => 'Increase font size';

  @override
  String get close => 'Close';

  @override
  String get sortLibrary => 'Sort library';

  @override
  String get reloadHealthData => 'Reload health data';

  @override
  String addServiceMirror(String title) {
    return 'Add a $title mirror';
  }

  @override
  String get deleteMirrorTooltip => 'Delete mirror';

  @override
  String get ttsEngineMissing =>
      'No speech engine found. Install one (e.g. Speech Services) in system settings.';

  @override
  String get previousPage => 'Previous page';

  @override
  String get nextPage => 'Next page';

  @override
  String searchingOn(String source) {
    return 'Results from $source';
  }

  @override
  String get sourceLibgen => 'LibGen';

  @override
  String get sourceZlib => 'Z-Library';

  @override
  String get sourceAnnas => 'Anna\'s Archive';

  @override
  String downloadFrom(String source) {
    return 'Downloading from $source';
  }

  @override
  String get tryingNextSource => 'No results here, trying next source…';

  @override
  String get slowMirrorsSkipped => 'Using faster mirrors';

  @override
  String whatsNewTitle(String version) {
    return 'What\'s new in $version';
  }

  @override
  String get whatsNewIntro => 'LightLib was updated. Here is what changed.';

  @override
  String get whatsNewTabFeatures => 'New features';

  @override
  String get whatsNewTabSources => 'Sources & mirrors';

  @override
  String get whatsNewProvidersHint =>
      'This release adds new search providers and mirrors. Update your list to drop dead mirrors and add the new ones; all three search providers get enabled.';

  @override
  String get whatsNewUpdateInstances => 'Update mirror list';

  @override
  String get whatsNewInstancesUpdated => 'Mirror list updated';

  @override
  String get whatsNewContinue => 'Continue';

  @override
  String get whatsNewFeatureSpeed =>
      'Downloads start faster: no mirror probing, fast hosts first, slow IPFS gateways last.';

  @override
  String get whatsNewFeatureSourceLabels =>
      'Every search result and download now shows which catalog it came from.';

  @override
  String get whatsNewFeatureCovers =>
      'Missing LibGen covers are fetched from the book\'s detail page.';

  @override
  String get zlibRecommendationsTitle => 'You may be interested in';

  @override
  String get zlibRecommendationsLoadMore => 'Load more';

  @override
  String get zlibRecommendationsLoadFailed => 'Could not load more books';

  @override
  String get searchingSources => 'Searching…';

  @override
  String searchingSource(String source) {
    return 'Searching $source…';
  }

  @override
  String tryingNextSourceNamed(String previous, String source) {
    return 'Nothing on $previous, trying $source…';
  }

  @override
  String get translationTranslate => 'Translate';

  @override
  String get translationShowOriginal => 'Show original';

  @override
  String get translationNoModel => 'No translation model installed yet.';

  @override
  String get translationOpenSettings => 'Set up';

  @override
  String get translationLoadingModel =>
      'Preparing the translation model… (the first time can take a few minutes)';

  @override
  String translationTranslating(int count, String device) {
    return 'Translating · $count left · $device';
  }

  @override
  String translationReady(String device) {
    return 'Translated on this device · $device';
  }

  @override
  String get translationPaused => 'Translation paused';

  @override
  String get translationFailed => 'The translation model could not run.';

  @override
  String get translationSettingsTitle => 'On-device translation';

  @override
  String get translationSettingsSubtitle =>
      'Translate books in the reader with a local AI model';

  @override
  String get translationTargetLanguage => 'Translate into';

  @override
  String get translationModels => 'Models';

  @override
  String get translationModelsHint =>
      'LiteRT runs on the GPU and falls back to the CPU. The GGUF file is for phones where LiteRT does not work.';

  @override
  String get translationRecommended => 'recommended';

  @override
  String get translationDownload => 'Download';

  @override
  String translationDownloadConfirm(String size) {
    return 'This downloads $size. Use Wi-Fi if you can. The file stays on this device.';
  }

  @override
  String get translationVerifying => 'Verifying the file…';

  @override
  String translationDownloadFailed(String error) {
    return 'Download failed: $error';
  }

  @override
  String get translationInUse => 'In use';

  @override
  String get translationUse => 'Use';

  @override
  String get translationDeleteConfirm =>
      'Delete this model file from the device?';

  @override
  String get translationImportModel =>
      'Import a model file (.litertlm / .gguf)';

  @override
  String get translationNotAModel => 'Pick a .litertlm or .gguf file.';

  @override
  String get translationImported => 'Model imported and selected.';

  @override
  String get translationImportFailed => 'Could not import the model file.';

  @override
  String get translationBatteryNote =>
      'Only the paragraphs on screen and a few ahead are translated, and results are saved, so re-reading costs nothing. Translation pauses when the app is in the background.';

  @override
  String get translationClearCache => 'Delete saved translations';

  @override
  String get translationCacheCleared => 'Saved translations deleted.';

  @override
  String get importBooks => 'Import EPUB / PDF';

  @override
  String get importBooksFailed => 'Could not open the file picker.';

  @override
  String importBooksResult(int imported, int existing, int failed) {
    return 'Added $imported · already in library $existing · failed $failed';
  }

  @override
  String get translationAutoLibrary =>
      'Translate library books in the background';

  @override
  String get translationAutoLibraryHint =>
      'Off unless turned on. Slow and gentle: rests after every paragraph, waits while you read or when the phone is warm or low on battery, and keeps going with a notification after you leave the app. Translations are saved next to each book.';

  @override
  String get translationBookDone => 'Done';

  @override
  String get readerViewOptions => 'View';

  @override
  String get readerLayoutScroll => 'Scroll';

  @override
  String get readerLayoutPagesLtr => 'Pages (left to right)';

  @override
  String get readerLayoutPagesRtl => 'Pages (right to left, manga style)';

  @override
  String get readerFonts => 'Fonts';

  @override
  String get fontsSettingsSubtitle =>
      'Fonts for Korean, Japanese and Latin text';

  @override
  String get fontsHint =>
      'Each script uses its own font. Google Fonts download once on first use and then work offline. You can also import a .ttf or .otf file.';

  @override
  String get fontKorean => 'Korean text';

  @override
  String get fontJapanese => 'Japanese text';

  @override
  String get fontLatin => 'Latin text';

  @override
  String get fontSystem => 'System default';

  @override
  String get fontFile => 'file';

  @override
  String get fontImport => 'Import a font file (.ttf / .otf)';

  @override
  String fontImported(String family) {
    return 'Font imported: $family';
  }

  @override
  String get fontImportFailed => 'Could not import the font.';

  @override
  String get readerThemesSettings => 'Themes & Settings';

  @override
  String get readerThemeOriginal => 'Original';

  @override
  String get readerThemePaper => 'Paper';

  @override
  String get readerThemeCalm => 'Calm';

  @override
  String get readerThemeQuiet => 'Quiet';

  @override
  String get readerThemeBold => 'Bold';

  @override
  String get readerThemeNight => 'Night';

  @override
  String get readerLayout => 'Layout';

  @override
  String get readerLayoutPagesShort => 'Pages';

  @override
  String get readerLayoutMangaShort => 'Manga';

  @override
  String get readerFont => 'Font';

  @override
  String get readerAllFonts => 'Fonts for each language';

  @override
  String get readerCustomize => 'Customize';

  @override
  String get readerFontSize => 'Text size';

  @override
  String get readerLineSpacing => 'Line spacing';

  @override
  String get readerLetterSpacing => 'Character spacing';

  @override
  String get readerMargins => 'Margins';

  @override
  String get readerJustify => 'Justify text';

  @override
  String get readerBoldText => 'Bold text';

  @override
  String get readerReset => 'Reset';

  @override
  String get readerContents => 'Contents';

  @override
  String get libraryContinueReading => 'Continue reading';

  @override
  String get libraryAllBooks => 'All books';

  @override
  String libraryBookCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count books',
      one: '1 book',
    );
    return '$_temp0';
  }

  @override
  String get libraryNoMatches => 'No books match the current filters';

  @override
  String get libraryEmpty => 'Your library is empty';

  @override
  String get libraryEmptyHint =>
      'Import EPUB or PDF files you have to start reading.';

  @override
  String get bookGenre => 'Genre';

  @override
  String get bookCollections => 'Collections';

  @override
  String get genreAll => 'All';

  @override
  String get genreNone => 'No genre';

  @override
  String get genreLightNovel => 'Light novel';

  @override
  String get genreComic => 'Comics';

  @override
  String get genreNovel => 'Novel';

  @override
  String get genreEnglishNovel => 'English fiction';

  @override
  String get genreEssay => 'Essay';

  @override
  String get genreScience => 'Science';

  @override
  String get genreHumanities => 'Humanities';

  @override
  String get genreBusiness => 'Business';

  @override
  String get genrePaper => 'Papers';

  @override
  String get genreTextbook => 'Study';

  @override
  String get genreOther => 'Other';

  @override
  String get translationLightNovelStyle => 'Light novel style';

  @override
  String get translationLightNovelStyleHint =>
      'Keeps casual and polite speech, character quirks, honorifics and sound words. Turn off for non-fiction. Each style keeps its own translations.';

  @override
  String get libraryBookOptions => 'Book options';

  @override
  String get libraryRecentlyAdded => 'Recently added';

  @override
  String get libraryReadingNow => 'Reading now';

  @override
  String libraryFinishedCount(int count) {
    return '$count finished';
  }

  @override
  String get recentSearches => 'Recent searches';

  @override
  String get clearAll => 'Clear all';

  @override
  String get removeFromHistory => 'Remove from history';

  @override
  String get searchHistoryFill => 'Edit this search';

  @override
  String get showMore => 'Show more';

  @override
  String get showLess => 'Show less';

  @override
  String get searchHistorySection => 'Search History';

  @override
  String get saveSearchHistory => 'Save search history';

  @override
  String get saveSearchHistoryHint => 'Show recent searches on the Search tab';

  @override
  String get clearSearchHistory => 'Clear search history';

  @override
  String savedSearchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count saved searches',
      one: '1 saved search',
      zero: 'No saved searches',
    );
    return '$_temp0';
  }

  @override
  String get searchHistoryCleared => 'Search history cleared';

  @override
  String get themeSystemShort => 'System';

  @override
  String get themeLightShort => 'Light';

  @override
  String get themeDarkShort => 'Dark';

  @override
  String get recapTitle => 'Reading record';

  @override
  String get recapCheckpoints => 'Checkpoints';

  @override
  String get recapBooksUnit => '';

  @override
  String get recapDaysUnit => '';

  @override
  String get recapAllCheckpoints => 'Every checkpoint reached!';

  @override
  String recapToNextCheckpoint(int remaining, int next) {
    return '$remaining more to reach $next';
  }

  @override
  String get recapStreak => 'day streak';

  @override
  String get recapStreakStart => 'Read today to start';

  @override
  String recapLongestStreak(int days) {
    return 'Best: $days d';
  }

  @override
  String get recapLastFourWeeks => 'Last 4 weeks';

  @override
  String recapReadingDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days reading days',
      one: '1 reading day',
    );
    return '$_temp0';
  }

  @override
  String recapMonthTitle(String monthName) {
    return '$monthName recap';
  }

  @override
  String get recapFinishedThisMonth => 'finished this month';

  @override
  String get recapGenreMix => 'Genre mix';

  @override
  String get translationPromptFormat => 'Prompt format';

  @override
  String get translationPromptFormatHint =>
      'How requests are worded for this model. Dedicated translation models work best with the format they were trained on; Auto picks it from the model.';

  @override
  String promptFormatAuto(String format) {
    return 'Auto ($format)';
  }

  @override
  String get promptFormatGeneral => 'General (Gemma and others)';

  @override
  String get promptFormatHyMt => 'Hy-MT translation model';

  @override
  String get promptFormatJaKo => 'Japanese→Korean dialogue model';

  @override
  String get promptFormatKoreanOnly =>
      'This format translates into Korean only. For other languages the general format is used.';

  @override
  String translationSomeFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count paragraphs could not be translated',
      one: '1 paragraph could not be translated',
    );
    return '$_temp0';
  }

  @override
  String get translationReadyPlain => 'Translated on this device';

  @override
  String translationNeedsRam(int gb) {
    return 'RAM $gb GB or more';
  }

  @override
  String get translationFaster => 'faster';

  @override
  String get translationChargingOnly => 'Only while charging';

  @override
  String get translationChargingOnlyHint =>
      'Waits for a charger, so the battery is never spent on it.';

  @override
  String get translationDevice => 'Processor';

  @override
  String get translationDeviceAuto => 'GPU first (faster)';

  @override
  String get translationDeviceCpu => 'CPU (GPU left for the screen)';

  @override
  String get translationDeviceHint =>
      'If scrolling stutters while translating, try the CPU: slower, but the screen keeps the GPU.';

  @override
  String get translationNoticeChannel => 'Background translation';

  @override
  String get translationNoticeTitle => 'Translating library books';

  @override
  String translationNoticeProgress(String title, int percent) {
    return '$title · $percent%';
  }

  @override
  String translationNoticeCount(int done, int total, int book, int books) {
    return '$done/$total paragraphs · book $book of $books';
  }

  @override
  String get translationNoticeStop => 'Stop';

  @override
  String get translationNoticeDone => 'Library translation finished';

  @override
  String translationNoticeDoneCount(int count) {
    return 'Books translated: $count';
  }

  @override
  String get translationWaitReading => 'Waiting while you read';

  @override
  String get translationWaitAppClosed => 'Continues when the app is open';

  @override
  String get translationWaitWarm => 'Phone is warm, resting';

  @override
  String get translationWaitBattery => 'Battery low, paused until charging';

  @override
  String get translationWaitPowerSave => 'Battery saver is on, paused';

  @override
  String get translationWaitCharger => 'Waiting for a charger';

  @override
  String get readerWriting => 'Text direction';

  @override
  String get readerWritingAuto => 'Book';

  @override
  String get readerWritingHorizontal => 'Across';

  @override
  String get readerWritingVertical => 'Vertical';

  @override
  String get readerLoadFailed => 'This book could not be shown.';

  @override
  String get readerOpenSimple => 'Open in the simple reader';

  @override
  String get ok => 'OK';

  @override
  String get downloadPreparing => 'Preparing…';

  @override
  String get downloadStartedTitle => 'Download started';

  @override
  String get downloadStartedBody =>
      'It joins your library when it finishes. The notification shows the progress.';

  @override
  String get downloadFastBadge => 'Fast download';

  @override
  String get downloadNotStartedTitle => 'Couldn\'t start the download';

  @override
  String get updateAvailableTitle => 'A new version is out';

  @override
  String get updateReadyTitle => 'Update ready to install';

  @override
  String get updateChangesTitle => 'What\'s changed';

  @override
  String get updateNoNotes => 'No change notes for this build.';

  @override
  String get updateDownloading => 'Downloading…';

  @override
  String get updateDownloadFailed => 'The update could not be downloaded.';

  @override
  String get updateDownloadInstall => 'Download and install';

  @override
  String updateDownloadInstallSize(String size) {
    return 'Download and install · $size';
  }

  @override
  String get updateInstallNow => 'Install now';

  @override
  String get updateLater => 'Later';

  @override
  String get updateViewOnGithub => 'GitHub';

  @override
  String get updateAction => 'Update';

  @override
  String get autoDownloadUpdates => 'Download updates automatically';

  @override
  String get autoDownloadUpdatesHint =>
      'New builds are fetched over Wi-Fi, ready to install';

  @override
  String get releaseHistoryTitle => 'Update history';

  @override
  String get releaseHistoryHint => 'Every build released on GitHub';

  @override
  String get releaseHistoryFailed => 'The update history could not be loaded.';

  @override
  String get releaseLatest => 'Latest';

  @override
  String get releaseInstalled => 'Installed';

  @override
  String get widgetEmptyLibrary => 'Books you add to your library show up here';

  @override
  String get widgetNextUp => 'Next';

  @override
  String get glossaryTitle => 'Glossary';

  @override
  String get glossaryHint =>
      'Every translation writes these names and terms this way. Tap one to change it.';

  @override
  String get glossaryMaking => 'Reading the book to make its glossary…';

  @override
  String get glossaryEmpty =>
      'No glossary yet. It is made when you translate this book.';

  @override
  String get glossaryRemake => 'Make again';

  @override
  String get glossaryKindPerson => 'Person';

  @override
  String get glossaryKindPlace => 'Place';

  @override
  String get glossaryKindTerm => 'Term';

  @override
  String get glossaryGenderMale => 'Male';

  @override
  String get glossaryGenderFemale => 'Female';

  @override
  String get glossaryGenderUnknown => 'Unknown';

  @override
  String get glossaryKorean => 'Written as';

  @override
  String get homeRegionJapan => 'Japan';

  @override
  String get homeRegionWestern => 'English';

  @override
  String get japanLightNovels => 'Light novels';

  @override
  String get japanNewLiterature => 'Web novels in print';

  @override
  String get japanManga => 'Manga';

  @override
  String get storageNotWritable =>
      'Books can\'t be saved in that folder. Choose the app\'s folder, or one inside Download or Documents.';

  @override
  String get priorityTranslate => 'Translate this whole book';

  @override
  String get priorityTranslateHint =>
      'Before any other book and without resting until it\'s done, also with the screen off. It pauses only if the phone gets very hot.';

  @override
  String get priorityTranslating => 'Translating this book first';

  @override
  String get priorityTranslateDone => 'Translated';

  @override
  String get priorityTranslatePreparing => 'Getting ready…';

  @override
  String get priorityTranslateNoModel =>
      'Install a translation model first (Settings > On-device translation)';

  @override
  String priorityTranslateProgress(int done, int total, int percent) {
    return '$done/$total paragraphs · $percent%';
  }

  @override
  String translationNoticeBookDone(String title) {
    return '“$title” is translated';
  }

  @override
  String get coverHide => 'Hide cover';

  @override
  String get coverShow => 'Show cover';

  @override
  String get coverHideHint =>
      'The library, the book page and the home-screen widgets show the title instead';

  @override
  String get translationEngine => 'Translation engine';

  @override
  String get translationEngineDevice => 'On the device';

  @override
  String get translationEngineGemini => 'Gemini';

  @override
  String get translationEngineGeminiHint =>
      'Google Gemini translates over the internet: a book in minutes, better than the model on the phone.';

  @override
  String get geminiKey => 'API key';

  @override
  String get geminiKeyHint =>
      'Free from Google AI Studio (aistudio.google.com/apikey). Kept on this device only, never in backups.';

  @override
  String geminiKeySaved(String hint) {
    return 'Saved key $hint';
  }

  @override
  String get geminiGetKey => 'Get a key';

  @override
  String get geminiTest => 'Save and test';

  @override
  String get geminiTestOk => 'Connected';

  @override
  String get geminiTestBadKey => 'The key doesn\'t work';

  @override
  String geminiTestFailed(String error) {
    return 'Could not connect: $error';
  }

  @override
  String get geminiModel => 'Model';

  @override
  String geminiModelInfo(int rpd, String input, String output) {
    return 'Free: about $rpd requests a day · paid \$$input / \$$output per 1M tokens';
  }

  @override
  String get geminiUsageTitle => 'Today\'s use';

  @override
  String geminiUsageResets(String time) {
    return 'Resets at $time (midnight US Pacific)';
  }

  @override
  String geminiUsageRequests(int count, int limit) {
    return 'Requests $count / $limit';
  }

  @override
  String geminiUsageRequestsEstimate(int count, int limit) {
    return 'Requests $count (free limit about $limit)';
  }

  @override
  String geminiUsageTokens(String input, String output) {
    return 'Tokens in $input · out $output';
  }

  @override
  String geminiUsageParagraphs(int count) {
    return 'Paragraphs translated $count';
  }

  @override
  String geminiUsageBlocked(int safety, int prohibited) {
    return 'Blocked by filters $safety · refused by policy $prohibited';
  }

  @override
  String geminiUsageOnDevice(int count) {
    return 'Translated on the device instead $count';
  }

  @override
  String get geminiTierFree => 'Free tier';

  @override
  String get geminiTierPaid => 'Paid tier';

  @override
  String get geminiTierUnknown =>
      'Tier not known yet (shown once a limit is reached)';

  @override
  String geminiCost(String cost) {
    return 'At paid prices: $cost';
  }

  @override
  String get geminiExhausted =>
      'Today\'s quota is used up: the device translates until it resets.';

  @override
  String get geminiSafety => 'Safety filters';

  @override
  String get geminiSafetyHint =>
      'For books rated 15+ or adult, leave these off. What Google always blocks (such as anything endangering children) stays blocked whatever is set; such paragraphs stay in the original.';

  @override
  String get geminiHarmHarassment => 'Harassment';

  @override
  String get geminiHarmHate => 'Hate speech';

  @override
  String get geminiHarmSexual => 'Sexual content';

  @override
  String get geminiHarmDangerous => 'Dangerous content';

  @override
  String get geminiBlockOff => 'Off';

  @override
  String get geminiBlockOnlyHigh => 'High only';

  @override
  String get geminiBlockMedium => 'Medium and above';

  @override
  String get geminiBlockLow => 'Low and above';

  @override
  String get geminiDeviceFallback =>
      'Continue on the device when Gemini can\'t';

  @override
  String get geminiDeviceFallbackHint =>
      'Quota used up, a filter, no connection: those paragraphs only, with the model on the phone.';

  @override
  String get geminiConcurrency => 'Requests at once';

  @override
  String get geminiPrivacyNote =>
      'The book\'s text is sent to Google. On the free tier Google may use it to improve its products; on the paid tier it does not.';

  @override
  String get geminiThinking => 'Thinking';

  @override
  String get geminiThinkingSpeed => 'Speed first';

  @override
  String get geminiThinkingBalanced => 'Balanced';

  @override
  String get geminiThinkingQuality => 'Quality first';

  @override
  String get geminiThinkingHint =>
      'The more the model thinks before answering, the better it handles nuance, and the longer and costlier each request (thinking is billed as output).';

  @override
  String get translationClearBook => 'Delete this book\'s translations';

  @override
  String get translationClearBookConfirm =>
      'Every saved translation of this book is deleted. Reading it or “Translate this whole book” translates it again.';

  @override
  String get translationClearBookDone => 'Translations deleted';

  @override
  String get translationExport => 'Export translated EPUB';

  @override
  String get translationExportNone => 'Nothing of this book is translated yet';

  @override
  String translationExportDone(int translated, int total) {
    return 'EPUB made with $translated of $total paragraphs translated';
  }

  @override
  String get translationExportFailed => 'This book could not be exported';
}
