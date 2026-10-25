import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('ja'),
    Locale('ko')
  ];

  /// Application name shown in the app bar and about page
  ///
  /// In en, this message translates to:
  /// **'LightLib'**
  String get appTitle;

  /// Bottom navigation label
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// Bottom navigation label
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get navSearch;

  /// Bottom navigation label
  ///
  /// In en, this message translates to:
  /// **'My Library'**
  String get navMyLibrary;

  /// Bottom navigation label
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// Common dismiss button
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Common confirm button
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// Confirm a creation dialog
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// Remove item action
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// Retry a failed action
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// Expandable metadata filter toggle on the search page
  ///
  /// In en, this message translates to:
  /// **'Advanced Search'**
  String get advancedSearch;

  /// Text field label for the author metadata filter
  ///
  /// In en, this message translates to:
  /// **'Author'**
  String get author;

  /// Text field label for the publisher metadata filter
  ///
  /// In en, this message translates to:
  /// **'Publisher'**
  String get publisher;

  /// Hint text of the library metadata search box
  ///
  /// In en, this message translates to:
  /// **'Search library (title, author, publisher, year)'**
  String get searchLibraryHint;

  /// Button that opens the tag creation dialog
  ///
  /// In en, this message translates to:
  /// **'New collection'**
  String get newCollection;

  /// Shown when a search or filter returns nothing
  ///
  /// In en, this message translates to:
  /// **'No results found'**
  String get noResultsFound;

  /// Title of the results page
  ///
  /// In en, this message translates to:
  /// **'Results for \'{query}\''**
  String resultsFor(String query);

  /// Theme mode choice that follows the OS
  ///
  /// In en, this message translates to:
  /// **'Follow the System'**
  String get followSystem;

  /// Theme mode choice
  ///
  /// In en, this message translates to:
  /// **'Light theme'**
  String get lightTheme;

  /// Theme mode choice
  ///
  /// In en, this message translates to:
  /// **'Dark theme'**
  String get darkTheme;

  /// Settings row label for the app language
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageSetting;

  /// Language picker entry that follows the system locale
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get systemLanguage;

  /// Onboarding notifications switch title
  ///
  /// In en, this message translates to:
  /// **'Enable Notifications'**
  String get enableNotifications;

  /// Dialog body explaining why notifications are needed
  ///
  /// In en, this message translates to:
  /// **'LightLib needs notification permission to show download progress in the background. This helps you track your book downloads even when the app is minimized.'**
  String get notificationsExplanation;

  /// Deferred consent button in the notification dialog
  ///
  /// In en, this message translates to:
  /// **'Maybe Later'**
  String get maybeLater;

  /// Confirm button granting a permission
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get enable;

  /// Reading status filter chip
  ///
  /// In en, this message translates to:
  /// **'Unread'**
  String get statusUnread;

  /// Reading status filter chip
  ///
  /// In en, this message translates to:
  /// **'In Progress'**
  String get statusInProgress;

  /// Reading status filter chip
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get statusCompleted;

  /// Hint for the new-collection name field
  ///
  /// In en, this message translates to:
  /// **'e.g. Favorites, Sci-Fi'**
  String get collectionNameHint;

  /// Helper text in the collection editor sheet
  ///
  /// In en, this message translates to:
  /// **'Long-press any book to manage its collections'**
  String get manageCollectionsHint;

  /// Page header above search results
  ///
  /// In en, this message translates to:
  /// **'Results'**
  String get results;

  /// Placeholder while content loads
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// Fallback when a value cannot be read
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknown;

  /// About page title
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// Short app description on the About page
  ///
  /// In en, this message translates to:
  /// **'An Open source app to download and read books from shadow library (Anna\'s Archive).'**
  String get aboutDescription;

  /// Fork attribution line
  ///
  /// In en, this message translates to:
  /// **'This is a forked version maintained by warreth for personal use and community updates.'**
  String get aboutForkNote;

  /// Upstream attribution line
  ///
  /// In en, this message translates to:
  /// **'Original app by dstark5 (https://github.com/dstark5/Openlib).'**
  String get aboutOriginalNote;

  /// Version section header
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// Github section header
  ///
  /// In en, this message translates to:
  /// **'Github'**
  String get github;

  /// Link label to this fork
  ///
  /// In en, this message translates to:
  /// **'This Fork (by warreth)'**
  String get thisForkByWarreth;

  /// Link label to the issue tracker
  ///
  /// In en, this message translates to:
  /// **'Report An Issue'**
  String get reportAnIssue;

  /// Link label to the upstream project
  ///
  /// In en, this message translates to:
  /// **'Original Project (by dstark5)'**
  String get originalProject;

  /// Licence section header
  ///
  /// In en, this message translates to:
  /// **'Licence'**
  String get licence;

  /// Link label to the licence text
  ///
  /// In en, this message translates to:
  /// **'GPL v3.0 license'**
  String get gplLicense;

  /// Snackbar when opening an external link fails
  ///
  /// In en, this message translates to:
  /// **'Could not launch {url}'**
  String couldNotLaunch(String url);

  /// Settings page header
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Settings section header
  ///
  /// In en, this message translates to:
  /// **'Search Providers'**
  String get searchProvidersSection;

  /// Settings section header
  ///
  /// In en, this message translates to:
  /// **'Library & Instances'**
  String get libraryInstancesSection;

  /// Settings section header
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearanceSection;

  /// Settings section header
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get generalSection;

  /// Settings section header
  ///
  /// In en, this message translates to:
  /// **'Reader'**
  String get readerSection;

  /// Settings section header
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get advancedSection;

  /// Settings section header
  ///
  /// In en, this message translates to:
  /// **'Backup'**
  String get backupSection;

  /// Settings section header
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get updatesSection;

  /// Settings section header
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutSection;

  /// Settings card title
  ///
  /// In en, this message translates to:
  /// **'Archive Instance'**
  String get archiveInstance;

  /// Settings tile title
  ///
  /// In en, this message translates to:
  /// **'Mirrors & Providers'**
  String get mirrorsAndProviders;

  /// Settings card title
  ///
  /// In en, this message translates to:
  /// **'Font Size'**
  String get fontSizeTitle;

  /// Font scale slider readout
  ///
  /// In en, this message translates to:
  /// **'Scale: {value}x'**
  String scaleValue(String value);

  /// Font scale preview label
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get preview;

  /// Settings tile title
  ///
  /// In en, this message translates to:
  /// **'Storage Location'**
  String get storageLocation;

  /// Settings switch tile title
  ///
  /// In en, this message translates to:
  /// **'Open PDF externally'**
  String get openPdfExternally;

  /// Settings switch tile subtitle
  ///
  /// In en, this message translates to:
  /// **'Use your default PDF viewer'**
  String get useDefaultPdfViewer;

  /// Settings switch tile title
  ///
  /// In en, this message translates to:
  /// **'Open EPUB externally'**
  String get openEpubExternally;

  /// Settings switch tile subtitle
  ///
  /// In en, this message translates to:
  /// **'Use your default EPUB reader'**
  String get useDefaultEpubReader;

  /// Settings switch tile title
  ///
  /// In en, this message translates to:
  /// **'Manual Download Button'**
  String get manualDownloadButton;

  /// Background challenge verification toggle
  ///
  /// In en, this message translates to:
  /// **'Verify challenges in background'**
  String get backgroundVerification;

  /// Background challenge verification toggle
  ///
  /// In en, this message translates to:
  /// **'Solve DDoS checks invisibly. Some devices fail this - turn it off to verify in a visible window instead'**
  String get backgroundVerificationHint;

  /// Background challenge verification toggle
  ///
  /// In en, this message translates to:
  /// **'If verification keeps failing, try turning off \"Verify challenges in background\" in Settings - some devices cannot solve checks invisibly.'**
  String get backgroundVerificationFix;

  /// Settings switch tile subtitle
  ///
  /// In en, this message translates to:
  /// **'Show button to manually trigger downloads'**
  String get showManualDownloadHint;

  /// Settings tile title
  ///
  /// In en, this message translates to:
  /// **'Anna\'s Archive Donation Key'**
  String get donationKeyTitle;

  /// Settings tile subtitle
  ///
  /// In en, this message translates to:
  /// **'Enter key for faster downloads'**
  String get enterKeyForFasterDownloads;

  /// Settings tile title
  ///
  /// In en, this message translates to:
  /// **'About LightLib'**
  String get aboutOpenlib;

  /// Settings tile title
  ///
  /// In en, this message translates to:
  /// **'Redo Onboarding'**
  String get redoOnboarding;

  /// Settings tile subtitle
  ///
  /// In en, this message translates to:
  /// **'Reset app setup and start over'**
  String get resetAppSetup;

  /// Settings tile title
  ///
  /// In en, this message translates to:
  /// **'Export Logs'**
  String get exportLogs;

  /// Settings tile subtitle
  ///
  /// In en, this message translates to:
  /// **'Share diagnostic logs (last 5 min)'**
  String get shareDiagnosticLogs;

  /// Snackbar when log export fails
  ///
  /// In en, this message translates to:
  /// **'Failed to export logs: {error}'**
  String failedExportLogs(String error);

  /// Dialog title for the donation key
  ///
  /// In en, this message translates to:
  /// **'Donation Key'**
  String get donationKeyDialog;

  /// Donation key field hint
  ///
  /// In en, this message translates to:
  /// **'Enter your key'**
  String get enterYourKey;

  /// Snackbar after switching instance
  ///
  /// In en, this message translates to:
  /// **'Instance changed successfully'**
  String get instanceChanged;

  /// Snackbar when instance ranking fails
  ///
  /// In en, this message translates to:
  /// **'Ranking failed: {error}'**
  String rankingFailed(String error);

  /// Settings switch tile title
  ///
  /// In en, this message translates to:
  /// **'Auto-Rank Instances'**
  String get autoRankInstances;

  /// Settings switch tile subtitle
  ///
  /// In en, this message translates to:
  /// **'Automatically sort by speed on startup'**
  String get sortBySpeedOnStartup;

  /// Settings tile title
  ///
  /// In en, this message translates to:
  /// **'Rank Instances Now'**
  String get rankInstancesNow;

  /// Snackbar when no update is available
  ///
  /// In en, this message translates to:
  /// **'You\'re on the latest version ({version})'**
  String onLatestVersion(String version);

  /// Snackbar when the update check fails
  ///
  /// In en, this message translates to:
  /// **'Failed to check for updates: {error}'**
  String failedCheckUpdates(String error);

  /// Settings switch tile title
  ///
  /// In en, this message translates to:
  /// **'Include Beta Updates'**
  String get includeBetaUpdates;

  /// Settings switch tile subtitle
  ///
  /// In en, this message translates to:
  /// **'Get pre-release versions'**
  String get getPreReleaseVersions;

  /// Settings tile title
  ///
  /// In en, this message translates to:
  /// **'Check for Updates'**
  String get checkForUpdates;

  /// Snackbar after successful backup export
  ///
  /// In en, this message translates to:
  /// **'Backup saved'**
  String get backupSaved;

  /// Snackbar when backup export fails
  ///
  /// In en, this message translates to:
  /// **'Failed to export backup: {error}'**
  String failedExportBackup(String error);

  /// Snackbar after successful backup import
  ///
  /// In en, this message translates to:
  /// **'Backup restored'**
  String get backupRestored;

  /// Snackbar when backup import fails
  ///
  /// In en, this message translates to:
  /// **'Failed to import backup: {error}'**
  String failedImportBackup(String error);

  /// Snackbar refusing to disable the last provider
  ///
  /// In en, this message translates to:
  /// **'At least one search source is needed'**
  String get atLeastOneSource;

  /// Snackbar summarizing instance ranking
  ///
  /// In en, this message translates to:
  /// **'Ranked! Fastest: {name} ({time}ms)'**
  String rankedFastest(String name, String time);

  /// Snackbar when ranking finds no reachable instance
  ///
  /// In en, this message translates to:
  /// **'Ranking complete'**
  String get rankingComplete;

  /// Anna's Archive provider subtitle
  ///
  /// In en, this message translates to:
  /// **'Searched last - protected by DDoS-Guard'**
  String get providerSourceOriginal;

  /// Libgen provider subtitle
  ///
  /// In en, this message translates to:
  /// **'Fast, direct downloads - searched first'**
  String get providerLibgenCatalog;

  /// Z-Library provider subtitle
  ///
  /// In en, this message translates to:
  /// **'Mirrors rotate; may need a login'**
  String get providerZlibMirrors;

  /// Settings card title
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get themeTitle;

  /// Native save dialog title for backups
  ///
  /// In en, this message translates to:
  /// **'Save Backup'**
  String get saveBackupTitle;

  /// Native file picker dialog title
  ///
  /// In en, this message translates to:
  /// **'Pick a backup file'**
  String get pickBackupFile;

  /// Snackbar when an imported file is invalid
  ///
  /// In en, this message translates to:
  /// **'That file is not an LightLib backup'**
  String get notABackup;

  /// Helper text under the donation key field
  ///
  /// In en, this message translates to:
  /// **'Used for faster downloads on Anna\'s Archive'**
  String get donationKeyHelper;

  /// Snackbar after ranking mirrors
  ///
  /// In en, this message translates to:
  /// **'Mirrors tested and ranked by speed'**
  String get mirrorsTestedRanked;

  /// Snackbar when mirror testing fails
  ///
  /// In en, this message translates to:
  /// **'Testing failed: {error}'**
  String testingFailed(String error);

  /// Dialog title for adding a mirror
  ///
  /// In en, this message translates to:
  /// **'Add Custom Mirror'**
  String get addCustomMirror;

  /// Mirror form field label
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get nameLabel;

  /// Mirror name field hint
  ///
  /// In en, this message translates to:
  /// **'e.g., My LibGen mirror'**
  String get nameHint;

  /// Mirror service dropdown label
  ///
  /// In en, this message translates to:
  /// **'Service'**
  String get serviceLabel;

  /// Mirror URL field label
  ///
  /// In en, this message translates to:
  /// **'URL'**
  String get urlLabel;

  /// Mirror URL field hint
  ///
  /// In en, this message translates to:
  /// **'https://example.com'**
  String get urlHint;

  /// Validation snackbar for the mirror form
  ///
  /// In en, this message translates to:
  /// **'Please fill all fields'**
  String get pleaseFillAllFields;

  /// URL validation snackbar
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid URL with http:// or https://'**
  String get enterValidUrl;

  /// Snackbar after adding a mirror
  ///
  /// In en, this message translates to:
  /// **'Mirror added successfully'**
  String get mirrorAdded;

  /// Dialog title for deleting a mirror
  ///
  /// In en, this message translates to:
  /// **'Delete Mirror'**
  String get deleteMirror;

  /// Mirror deletion confirmation
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{name}\"?'**
  String deleteMirrorConfirm(String name);

  /// Snackbar after deleting a mirror
  ///
  /// In en, this message translates to:
  /// **'Mirror deleted'**
  String get mirrorDeleted;

  /// Snackbar refusing to delete a default mirror
  ///
  /// In en, this message translates to:
  /// **'Cannot delete default mirrors'**
  String get cannotDeleteDefaultMirrors;

  /// Screen title for mirror management
  ///
  /// In en, this message translates to:
  /// **'Manage Mirrors'**
  String get manageMirrors;

  /// Empty state when no mirrors exist
  ///
  /// In en, this message translates to:
  /// **'No mirrors available'**
  String get noMirrorsAvailable;

  /// Generic error display
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String errorLabel(String error);

  /// Floating action button label
  ///
  /// In en, this message translates to:
  /// **'Add mirror'**
  String get addMirror;

  /// Tooltip for the rank button
  ///
  /// In en, this message translates to:
  /// **'Test & rank mirrors by speed'**
  String get testRankMirrors;

  /// Mirror status when ping fails
  ///
  /// In en, this message translates to:
  /// **'unreachable'**
  String get unreachable;

  /// Open the downloaded file button
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// Snackbar when opening a file fails
  ///
  /// In en, this message translates to:
  /// **'Unable to open file!'**
  String get unableToOpenFile;

  /// Button opening the book page on the source site
  ///
  /// In en, this message translates to:
  /// **'Open in site'**
  String get openInSite;

  /// Snackbar after deleting a book
  ///
  /// In en, this message translates to:
  /// **'Book has been Deleted!'**
  String get bookDeleted;

  /// Delete confirmation dialog title
  ///
  /// In en, this message translates to:
  /// **'Delete Book'**
  String get deleteBook;

  /// Delete confirmation dialog body
  ///
  /// In en, this message translates to:
  /// **'This is permanent and cannot be undone'**
  String get deletePermanentWarning;

  /// Retry button on the error screen
  ///
  /// In en, this message translates to:
  /// **'Try Again'**
  String get tryAgain;

  /// Error screen action revealing page HTML
  ///
  /// In en, this message translates to:
  /// **'Show blocked page content'**
  String get showBlockedContent;

  /// Error screen action for manual captcha solving
  ///
  /// In en, this message translates to:
  /// **'Verify in Browser'**
  String get verifyInBrowser;

  /// Dialog title for the verification chooser
  ///
  /// In en, this message translates to:
  /// **'Manual Verification Required'**
  String get manualVerificationRequired;

  /// Verification option label
  ///
  /// In en, this message translates to:
  /// **'System Browser'**
  String get systemBrowser;

  /// Verification option label
  ///
  /// In en, this message translates to:
  /// **'Embedded Browser'**
  String get embeddedBrowser;

  /// Snackbar when the verification URL is missing
  ///
  /// In en, this message translates to:
  /// **'Unable to open verification page - no URL available'**
  String get unableToOpenVerification;

  /// Dialog title showing the blocked page HTML
  ///
  /// In en, this message translates to:
  /// **'Blocked Page Content'**
  String get blockedPageContent;

  /// Snackbar after copying text
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copiedToClipboard;

  /// Reader help overlay dismiss button
  ///
  /// In en, this message translates to:
  /// **'Got it!'**
  String get gotIt;

  /// Copy-to-clipboard button
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// Error screen hint heading
  ///
  /// In en, this message translates to:
  /// **'Try using a VPN'**
  String get tryUsingVpn;

  /// Home page header for the trending tab
  ///
  /// In en, this message translates to:
  /// **'Trending'**
  String get trending;

  /// Home page header for the genres tab
  ///
  /// In en, this message translates to:
  /// **'Genres'**
  String get genres;

  /// Snackbar after copying a book's file path
  ///
  /// In en, this message translates to:
  /// **'Copied the book path to your clipboard'**
  String get copiedBookPath;

  /// Tooltip on the pause button
  ///
  /// In en, this message translates to:
  /// **'Pause download'**
  String get pauseDownload;

  /// Tooltip on the resume button
  ///
  /// In en, this message translates to:
  /// **'Resume download'**
  String get resumeDownload;

  /// Tooltip on the cancel button
  ///
  /// In en, this message translates to:
  /// **'Cancel download'**
  String get cancelDownload;

  /// Snackbar after copying a book link
  ///
  /// In en, this message translates to:
  /// **'Copied the book link to your clipboard'**
  String get copiedBookLink;

  /// Snackbar when no mirror can serve the book
  ///
  /// In en, this message translates to:
  /// **'No mirrors available!'**
  String get noMirrors;

  /// Button saving the book to the library
  ///
  /// In en, this message translates to:
  /// **'Add To My Library'**
  String get addToMyLibrary;

  /// Snackbar when a download begins
  ///
  /// In en, this message translates to:
  /// **'Download started in background'**
  String get downloadStartedBackground;

  /// Snackbar when a download completes
  ///
  /// In en, this message translates to:
  /// **'Book has been downloaded!'**
  String get bookDownloaded;

  /// Snackbar when advancing without a folder
  ///
  /// In en, this message translates to:
  /// **'Please select a storage folder to continue'**
  String get selectStorageToContinue;

  /// Final onboarding button
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get getStarted;

  /// Onboarding advance button
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// Onboarding welcome heading
  ///
  /// In en, this message translates to:
  /// **'Welcome to LightLib'**
  String get welcomeTitle;

  /// Onboarding welcome body
  ///
  /// In en, this message translates to:
  /// **'Your personal gateway to a world of knowledge. Let\'s get you set up.'**
  String get welcomeSubtitle;

  /// Onboarding storage page heading
  ///
  /// In en, this message translates to:
  /// **'Where should we store your books?'**
  String get whereToStoreBooks;

  /// Storage path placeholder
  ///
  /// In en, this message translates to:
  /// **'No path selected'**
  String get noPathSelected;

  /// Storage folder picker button
  ///
  /// In en, this message translates to:
  /// **'Select Folder'**
  String get selectFolder;

  /// Storage folder explanation
  ///
  /// In en, this message translates to:
  /// **'We\'ll only look for PDF/EPUB files in this folder. No recursive scanning of subfolders.'**
  String get storageScanNote;

  /// Onboarding updates page heading
  ///
  /// In en, this message translates to:
  /// **'Automatic Updates'**
  String get automaticUpdates;

  /// Onboarding switch title
  ///
  /// In en, this message translates to:
  /// **'Enable Auto-Updates'**
  String get enableAutoUpdates;

  /// Onboarding switch subtitle
  ///
  /// In en, this message translates to:
  /// **'Not recommended if you installed via F-Droid (F-Droid handles updates).'**
  String get autoUpdatesFdroidNote;

  /// Onboarding switch title
  ///
  /// In en, this message translates to:
  /// **'Enable Beta Updates'**
  String get enableBetaUpdatesOnboarding;

  /// Onboarding switch subtitle
  ///
  /// In en, this message translates to:
  /// **'Get pre-release versions (beta updates) when available.'**
  String get betaUpdatesNote;

  /// Onboarding donation page heading
  ///
  /// In en, this message translates to:
  /// **'Support Anna\'s Archive'**
  String get supportAnnasArchive;

  /// Onboarding donation page body
  ///
  /// In en, this message translates to:
  /// **'Donating to Anna\'s Archive provides faster downloads and helps them keep the service running for everyone. You can enter your secret key below.'**
  String get donationPitch;

  /// Donation key field label on onboarding
  ///
  /// In en, this message translates to:
  /// **'Anna\'s Archive Secret Key'**
  String get annasSecretKey;

  /// Onboarding sponsor page heading
  ///
  /// In en, this message translates to:
  /// **'Support This App'**
  String get supportThisApp;

  /// Onboarding sponsor page body
  ///
  /// In en, this message translates to:
  /// **'If you enjoy this app, consider supporting its development. It helps me dedicate more time to making it better!'**
  String get sponsorPitch;

  /// Sponsor link button
  ///
  /// In en, this message translates to:
  /// **'Sponsor on GitHub'**
  String get sponsorOnGithub;

  /// Onboarding notifications page heading
  ///
  /// In en, this message translates to:
  /// **'Stay Updated'**
  String get stayUpdated;

  /// Onboarding notifications switch subtitle
  ///
  /// In en, this message translates to:
  /// **'Get notified when downloads complete.'**
  String get notifyOnComplete;

  /// Onboarding theme page heading
  ///
  /// In en, this message translates to:
  /// **'Choose a Theme'**
  String get chooseTheme;

  /// Theme card label
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get lightThemeShort;

  /// Theme card label
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get darkThemeShort;

  /// AppBar title on the challenge solver screen
  ///
  /// In en, this message translates to:
  /// **'Verifying Access'**
  String get verifyingAccess;

  /// Webview verification finish button
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// Snackbar when TTS has no text
  ///
  /// In en, this message translates to:
  /// **'Nothing to read on this page'**
  String get nothingToRead;

  /// Snackbar when TTS finds no voice
  ///
  /// In en, this message translates to:
  /// **'No voice available for reading aloud'**
  String get noVoiceAvailable;

  /// TTS pause tooltip
  ///
  /// In en, this message translates to:
  /// **'Pause reading aloud'**
  String get pauseReadingAloud;

  /// TTS start/resume tooltip
  ///
  /// In en, this message translates to:
  /// **'Read aloud'**
  String get resumeReadingAloud;

  /// TTS stop tooltip
  ///
  /// In en, this message translates to:
  /// **'Stop reading aloud'**
  String get stopReadingAloud;

  /// TTS speed control tooltip
  ///
  /// In en, this message translates to:
  /// **'Speech speed'**
  String get speechSpeed;

  /// Reader font control tooltip
  ///
  /// In en, this message translates to:
  /// **'Decrease font size'**
  String get decreaseFontSize;

  /// Reader font control tooltip
  ///
  /// In en, this message translates to:
  /// **'Increase font size'**
  String get increaseFontSize;

  /// Dialog dismiss button
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// Library sort menu tooltip
  ///
  /// In en, this message translates to:
  /// **'Sort library'**
  String get sortLibrary;

  /// Mirror health refresh tooltip
  ///
  /// In en, this message translates to:
  /// **'Reload health data'**
  String get reloadHealthData;

  /// Tooltip for adding a mirror of a given service
  ///
  /// In en, this message translates to:
  /// **'Add a {title} mirror'**
  String addServiceMirror(String title);

  /// Mirror delete button tooltip
  ///
  /// In en, this message translates to:
  /// **'Delete mirror'**
  String get deleteMirrorTooltip;

  /// Snackbar when the device has no TTS engine installed
  ///
  /// In en, this message translates to:
  /// **'No speech engine found. Install one (e.g. Speech Services) in system settings.'**
  String get ttsEngineMissing;

  /// PDF reader previous page button tooltip
  ///
  /// In en, this message translates to:
  /// **'Previous page'**
  String get previousPage;

  /// PDF reader next page button tooltip
  ///
  /// In en, this message translates to:
  /// **'Next page'**
  String get nextPage;

  /// Header on the search results page naming the catalog that produced the results
  ///
  /// In en, this message translates to:
  /// **'Results from {source}'**
  String searchingOn(String source);

  /// Short source label for Library Genesis results
  ///
  /// In en, this message translates to:
  /// **'LibGen'**
  String get sourceLibgen;

  /// Short source label for Z-Library results
  ///
  /// In en, this message translates to:
  /// **'Z-Library'**
  String get sourceZlib;

  /// Short source label for Anna's Archive results
  ///
  /// In en, this message translates to:
  /// **'Anna\'s Archive'**
  String get sourceAnnas;

  /// Notification/UI text naming the mirror serving the download
  ///
  /// In en, this message translates to:
  /// **'Downloading from {source}'**
  String downloadFrom(String source);

  /// Shown while a search redirects to the next catalog after an empty page
  ///
  /// In en, this message translates to:
  /// **'No results here, trying next source…'**
  String get tryingNextSource;

  /// Tiny hint that slow IPFS mirrors were deprioritized
  ///
  /// In en, this message translates to:
  /// **'Using faster mirrors'**
  String get slowMirrorsSkipped;

  /// Upgrade screen title naming the new version
  ///
  /// In en, this message translates to:
  /// **'What\'s new in {version}'**
  String whatsNewTitle(String version);

  /// One-line intro on the upgrade screen
  ///
  /// In en, this message translates to:
  /// **'LightLib was updated. Here is what changed.'**
  String get whatsNewIntro;

  /// Tab label listing this release's features
  ///
  /// In en, this message translates to:
  /// **'New features'**
  String get whatsNewTabFeatures;

  /// Tab label offering the instance-list update
  ///
  /// In en, this message translates to:
  /// **'Sources & mirrors'**
  String get whatsNewTabSources;

  /// Explains what the instance-list update on upgrade does
  ///
  /// In en, this message translates to:
  /// **'This release adds new search providers and mirrors. Update your list to drop dead mirrors and add the new ones; all three search providers get enabled.'**
  String get whatsNewProvidersHint;

  /// Button that re-syncs the stored mirror list with the shipped defaults
  ///
  /// In en, this message translates to:
  /// **'Update mirror list'**
  String get whatsNewUpdateInstances;

  /// Confirmation after the mirror list was re-synced
  ///
  /// In en, this message translates to:
  /// **'Mirror list updated'**
  String get whatsNewInstancesUpdated;

  /// Button closing the upgrade screen and entering the app
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get whatsNewContinue;

  /// Release note about the download speed fix
  ///
  /// In en, this message translates to:
  /// **'Downloads start faster: no mirror probing, fast hosts first, slow IPFS gateways last.'**
  String get whatsNewFeatureSpeed;

  /// Release note about the source badges
  ///
  /// In en, this message translates to:
  /// **'Every search result and download now shows which catalog it came from.'**
  String get whatsNewFeatureSourceLabels;

  /// Release note about the lazy cover fix
  ///
  /// In en, this message translates to:
  /// **'Missing LibGen covers are fetched from the book\'s detail page.'**
  String get whatsNewFeatureCovers;

  /// Heading of the Z-Library recommended-books mosaic under a book page
  ///
  /// In en, this message translates to:
  /// **'You may be interested in'**
  String get zlibRecommendationsTitle;

  /// Button that loads the next page of Z-Library recommended books
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get zlibRecommendationsLoadMore;

  /// Shown when loading more Z-Library recommendations failed
  ///
  /// In en, this message translates to:
  /// **'Could not load more books'**
  String get zlibRecommendationsLoadFailed;

  /// Results page while a search starts, before a source is known
  ///
  /// In en, this message translates to:
  /// **'Searching…'**
  String get searchingSources;

  /// Results page while the first source is searched
  ///
  /// In en, this message translates to:
  /// **'Searching {source}…'**
  String searchingSource(String source);

  /// Results page when a source found nothing and the next one is tried
  ///
  /// In en, this message translates to:
  /// **'Nothing on {previous}, trying {source}…'**
  String tryingNextSourceNamed(String previous, String source);

  /// Reader toolbar: turn translation on
  ///
  /// In en, this message translates to:
  /// **'Translate'**
  String get translationTranslate;

  /// Reader toolbar: turn translation off
  ///
  /// In en, this message translates to:
  /// **'Show original'**
  String get translationShowOriginal;

  /// Snackbar when no translation model is installed
  ///
  /// In en, this message translates to:
  /// **'No translation model installed yet.'**
  String get translationNoModel;

  /// Snackbar action opening translation settings
  ///
  /// In en, this message translates to:
  /// **'Set up'**
  String get translationOpenSettings;

  /// translationLoadingModel
  ///
  /// In en, this message translates to:
  /// **'Preparing the translation model… (the first time can take a few minutes)'**
  String get translationLoadingModel;

  /// Reader status while translating
  ///
  /// In en, this message translates to:
  /// **'Translating · {count} left · {device}'**
  String translationTranslating(int count, String device);

  /// Reader status when everything visible is translated
  ///
  /// In en, this message translates to:
  /// **'Translated on this device · {device}'**
  String translationReady(String device);

  /// Reader status while the app is in the background
  ///
  /// In en, this message translates to:
  /// **'Translation paused'**
  String get translationPaused;

  /// Reader status when the model could not run
  ///
  /// In en, this message translates to:
  /// **'The translation model could not run.'**
  String get translationFailed;

  /// Title of the translation settings page
  ///
  /// In en, this message translates to:
  /// **'On-device translation'**
  String get translationSettingsTitle;

  /// Settings tile subtitle for translation
  ///
  /// In en, this message translates to:
  /// **'Translate books in the reader with a local AI model'**
  String get translationSettingsSubtitle;

  /// Label for the target language picker
  ///
  /// In en, this message translates to:
  /// **'Translate into'**
  String get translationTargetLanguage;

  /// Header of the model list
  ///
  /// In en, this message translates to:
  /// **'Models'**
  String get translationModels;

  /// Explains the two model files
  ///
  /// In en, this message translates to:
  /// **'LiteRT runs on the GPU and falls back to the CPU. The GGUF file is for phones where LiteRT does not work.'**
  String get translationModelsHint;

  /// Badge on the recommended model
  ///
  /// In en, this message translates to:
  /// **'recommended'**
  String get translationRecommended;

  /// Button: download a model
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get translationDownload;

  /// Dialog before downloading a model
  ///
  /// In en, this message translates to:
  /// **'This downloads {size}. Use Wi-Fi if you can. The file stays on this device.'**
  String translationDownloadConfirm(String size);

  /// Model download: checksum check
  ///
  /// In en, this message translates to:
  /// **'Verifying the file…'**
  String get translationVerifying;

  /// Model download failed
  ///
  /// In en, this message translates to:
  /// **'Download failed: {error}'**
  String translationDownloadFailed(String error);

  /// Chip on the active model
  ///
  /// In en, this message translates to:
  /// **'In use'**
  String get translationInUse;

  /// Button: use this model
  ///
  /// In en, this message translates to:
  /// **'Use'**
  String get translationUse;

  /// Dialog before deleting a model
  ///
  /// In en, this message translates to:
  /// **'Delete this model file from the device?'**
  String get translationDeleteConfirm;

  /// Button: import a model file
  ///
  /// In en, this message translates to:
  /// **'Import a model file (.litertlm / .gguf)'**
  String get translationImportModel;

  /// The picked file is not a model
  ///
  /// In en, this message translates to:
  /// **'Pick a .litertlm or .gguf file.'**
  String get translationNotAModel;

  /// Model import succeeded
  ///
  /// In en, this message translates to:
  /// **'Model imported and selected.'**
  String get translationImported;

  /// Model import failed
  ///
  /// In en, this message translates to:
  /// **'Could not import the model file.'**
  String get translationImportFailed;

  /// Note about battery use
  ///
  /// In en, this message translates to:
  /// **'Only the paragraphs on screen and a few ahead are translated, and results are saved, so re-reading costs nothing. Translation pauses when the app is in the background.'**
  String get translationBatteryNote;

  /// Button: delete saved translations
  ///
  /// In en, this message translates to:
  /// **'Delete saved translations'**
  String get translationClearCache;

  /// Saved translations deleted
  ///
  /// In en, this message translates to:
  /// **'Saved translations deleted.'**
  String get translationCacheCleared;

  /// Library: import EPUB/PDF files from the device
  ///
  /// In en, this message translates to:
  /// **'Import EPUB / PDF'**
  String get importBooks;

  /// The file picker could not open
  ///
  /// In en, this message translates to:
  /// **'Could not open the file picker.'**
  String get importBooksFailed;

  /// Result of a book import
  ///
  /// In en, this message translates to:
  /// **'Added {imported} · already in library {existing} · failed {failed}'**
  String importBooksResult(int imported, int existing, int failed);

  /// Switch: translate library books in the background
  ///
  /// In en, this message translates to:
  /// **'Translate library books in the background'**
  String get translationAutoLibrary;

  /// translationAutoLibraryHint
  ///
  /// In en, this message translates to:
  /// **'Off unless turned on. Slow and gentle: rests after every paragraph, waits while you read or when the phone is warm or low on battery, and keeps going with a notification after you leave the app. Translations are saved next to each book.'**
  String get translationAutoLibraryHint;

  /// A book is fully translated
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get translationBookDone;

  /// Reader menu: view options
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get readerViewOptions;

  /// Reader layout: continuous scroll
  ///
  /// In en, this message translates to:
  /// **'Scroll'**
  String get readerLayoutScroll;

  /// Reader layout: pages turned left to right
  ///
  /// In en, this message translates to:
  /// **'Pages (left to right)'**
  String get readerLayoutPagesLtr;

  /// Reader layout: pages turned right to left, as in manga
  ///
  /// In en, this message translates to:
  /// **'Pages (right to left, manga style)'**
  String get readerLayoutPagesRtl;

  /// Title of the font settings
  ///
  /// In en, this message translates to:
  /// **'Fonts'**
  String get readerFonts;

  /// Settings tile subtitle for fonts
  ///
  /// In en, this message translates to:
  /// **'Fonts for Korean, Japanese and Latin text'**
  String get fontsSettingsSubtitle;

  /// Explains font options
  ///
  /// In en, this message translates to:
  /// **'Each script uses its own font. Google Fonts download once on first use and then work offline. You can also import a .ttf or .otf file.'**
  String get fontsHint;

  /// Font section: Korean
  ///
  /// In en, this message translates to:
  /// **'Korean text'**
  String get fontKorean;

  /// Font section: Japanese
  ///
  /// In en, this message translates to:
  /// **'Japanese text'**
  String get fontJapanese;

  /// Font section: Latin script
  ///
  /// In en, this message translates to:
  /// **'Latin text'**
  String get fontLatin;

  /// Font option: system font
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get fontSystem;

  /// Marks an imported font
  ///
  /// In en, this message translates to:
  /// **'file'**
  String get fontFile;

  /// Button: import a font file
  ///
  /// In en, this message translates to:
  /// **'Import a font file (.ttf / .otf)'**
  String get fontImport;

  /// Font import succeeded
  ///
  /// In en, this message translates to:
  /// **'Font imported: {family}'**
  String fontImported(String family);

  /// Font import failed
  ///
  /// In en, this message translates to:
  /// **'Could not import the font.'**
  String get fontImportFailed;

  /// readerThemesSettings
  ///
  /// In en, this message translates to:
  /// **'Themes & Settings'**
  String get readerThemesSettings;

  /// readerThemeOriginal
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get readerThemeOriginal;

  /// readerThemePaper
  ///
  /// In en, this message translates to:
  /// **'Paper'**
  String get readerThemePaper;

  /// readerThemeCalm
  ///
  /// In en, this message translates to:
  /// **'Calm'**
  String get readerThemeCalm;

  /// readerThemeQuiet
  ///
  /// In en, this message translates to:
  /// **'Quiet'**
  String get readerThemeQuiet;

  /// readerThemeBold
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get readerThemeBold;

  /// readerThemeNight
  ///
  /// In en, this message translates to:
  /// **'Night'**
  String get readerThemeNight;

  /// readerLayout
  ///
  /// In en, this message translates to:
  /// **'Layout'**
  String get readerLayout;

  /// readerLayoutPagesShort
  ///
  /// In en, this message translates to:
  /// **'Pages'**
  String get readerLayoutPagesShort;

  /// readerLayoutMangaShort
  ///
  /// In en, this message translates to:
  /// **'Manga'**
  String get readerLayoutMangaShort;

  /// readerFont
  ///
  /// In en, this message translates to:
  /// **'Font'**
  String get readerFont;

  /// readerAllFonts
  ///
  /// In en, this message translates to:
  /// **'Fonts for each language'**
  String get readerAllFonts;

  /// readerCustomize
  ///
  /// In en, this message translates to:
  /// **'Customize'**
  String get readerCustomize;

  /// readerFontSize
  ///
  /// In en, this message translates to:
  /// **'Text size'**
  String get readerFontSize;

  /// readerLineSpacing
  ///
  /// In en, this message translates to:
  /// **'Line spacing'**
  String get readerLineSpacing;

  /// readerLetterSpacing
  ///
  /// In en, this message translates to:
  /// **'Character spacing'**
  String get readerLetterSpacing;

  /// readerMargins
  ///
  /// In en, this message translates to:
  /// **'Margins'**
  String get readerMargins;

  /// readerJustify
  ///
  /// In en, this message translates to:
  /// **'Justify text'**
  String get readerJustify;

  /// readerBoldText
  ///
  /// In en, this message translates to:
  /// **'Bold text'**
  String get readerBoldText;

  /// readerReset
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get readerReset;

  /// readerContents
  ///
  /// In en, this message translates to:
  /// **'Contents'**
  String get readerContents;

  /// libraryContinueReading
  ///
  /// In en, this message translates to:
  /// **'Continue reading'**
  String get libraryContinueReading;

  /// libraryAllBooks
  ///
  /// In en, this message translates to:
  /// **'All books'**
  String get libraryAllBooks;

  /// libraryBookCount
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 book} other{{count} books}}'**
  String libraryBookCount(int count);

  /// libraryNoMatches
  ///
  /// In en, this message translates to:
  /// **'No books match the current filters'**
  String get libraryNoMatches;

  /// libraryEmpty
  ///
  /// In en, this message translates to:
  /// **'Your library is empty'**
  String get libraryEmpty;

  /// libraryEmptyHint
  ///
  /// In en, this message translates to:
  /// **'Import EPUB or PDF files you have to start reading.'**
  String get libraryEmptyHint;

  /// bookGenre
  ///
  /// In en, this message translates to:
  /// **'Genre'**
  String get bookGenre;

  /// bookCollections
  ///
  /// In en, this message translates to:
  /// **'Collections'**
  String get bookCollections;

  /// genreAll
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get genreAll;

  /// genreNone
  ///
  /// In en, this message translates to:
  /// **'No genre'**
  String get genreNone;

  /// genreLightNovel
  ///
  /// In en, this message translates to:
  /// **'Light novel'**
  String get genreLightNovel;

  /// genreComic
  ///
  /// In en, this message translates to:
  /// **'Comics'**
  String get genreComic;

  /// genreNovel
  ///
  /// In en, this message translates to:
  /// **'Novel'**
  String get genreNovel;

  /// genreEnglishNovel
  ///
  /// In en, this message translates to:
  /// **'English fiction'**
  String get genreEnglishNovel;

  /// genreEssay
  ///
  /// In en, this message translates to:
  /// **'Essay'**
  String get genreEssay;

  /// genreScience
  ///
  /// In en, this message translates to:
  /// **'Science'**
  String get genreScience;

  /// genreHumanities
  ///
  /// In en, this message translates to:
  /// **'Humanities'**
  String get genreHumanities;

  /// genreBusiness
  ///
  /// In en, this message translates to:
  /// **'Business'**
  String get genreBusiness;

  /// genrePaper
  ///
  /// In en, this message translates to:
  /// **'Papers'**
  String get genrePaper;

  /// genreTextbook
  ///
  /// In en, this message translates to:
  /// **'Study'**
  String get genreTextbook;

  /// genreOther
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get genreOther;

  /// translationLightNovelStyle
  ///
  /// In en, this message translates to:
  /// **'Light novel style'**
  String get translationLightNovelStyle;

  /// translationLightNovelStyleHint
  ///
  /// In en, this message translates to:
  /// **'Keeps casual and polite speech, character quirks, honorifics and sound words. Turn off for non-fiction. Each style keeps its own translations.'**
  String get translationLightNovelStyleHint;

  /// libraryBookOptions
  ///
  /// In en, this message translates to:
  /// **'Book options'**
  String get libraryBookOptions;

  /// libraryRecentlyAdded
  ///
  /// In en, this message translates to:
  /// **'Recently added'**
  String get libraryRecentlyAdded;

  /// libraryReadingNow
  ///
  /// In en, this message translates to:
  /// **'Reading now'**
  String get libraryReadingNow;

  /// libraryFinishedCount
  ///
  /// In en, this message translates to:
  /// **'{count} finished'**
  String libraryFinishedCount(int count);

  /// recentSearches
  ///
  /// In en, this message translates to:
  /// **'Recent searches'**
  String get recentSearches;

  /// clearAll
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get clearAll;

  /// removeFromHistory
  ///
  /// In en, this message translates to:
  /// **'Remove from history'**
  String get removeFromHistory;

  /// searchHistoryFill
  ///
  /// In en, this message translates to:
  /// **'Edit this search'**
  String get searchHistoryFill;

  /// showMore
  ///
  /// In en, this message translates to:
  /// **'Show more'**
  String get showMore;

  /// showLess
  ///
  /// In en, this message translates to:
  /// **'Show less'**
  String get showLess;

  /// searchHistorySection
  ///
  /// In en, this message translates to:
  /// **'Search History'**
  String get searchHistorySection;

  /// saveSearchHistory
  ///
  /// In en, this message translates to:
  /// **'Save search history'**
  String get saveSearchHistory;

  /// saveSearchHistoryHint
  ///
  /// In en, this message translates to:
  /// **'Show recent searches on the Search tab'**
  String get saveSearchHistoryHint;

  /// clearSearchHistory
  ///
  /// In en, this message translates to:
  /// **'Clear search history'**
  String get clearSearchHistory;

  /// savedSearchCount
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No saved searches} =1{1 saved search} other{{count} saved searches}}'**
  String savedSearchCount(int count);

  /// searchHistoryCleared
  ///
  /// In en, this message translates to:
  /// **'Search history cleared'**
  String get searchHistoryCleared;

  /// themeSystemShort
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystemShort;

  /// themeLightShort
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLightShort;

  /// themeDarkShort
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDarkShort;

  /// recapTitle
  ///
  /// In en, this message translates to:
  /// **'Reading record'**
  String get recapTitle;

  /// recapCheckpoints
  ///
  /// In en, this message translates to:
  /// **'Checkpoints'**
  String get recapCheckpoints;

  /// recapBooksUnit
  ///
  /// In en, this message translates to:
  /// **''**
  String get recapBooksUnit;

  /// recapDaysUnit
  ///
  /// In en, this message translates to:
  /// **''**
  String get recapDaysUnit;

  /// recapAllCheckpoints
  ///
  /// In en, this message translates to:
  /// **'Every checkpoint reached!'**
  String get recapAllCheckpoints;

  /// recapToNextCheckpoint
  ///
  /// In en, this message translates to:
  /// **'{remaining} more to reach {next}'**
  String recapToNextCheckpoint(int remaining, int next);

  /// recapStreak
  ///
  /// In en, this message translates to:
  /// **'day streak'**
  String get recapStreak;

  /// recapStreakStart
  ///
  /// In en, this message translates to:
  /// **'Read today to start'**
  String get recapStreakStart;

  /// recapLongestStreak
  ///
  /// In en, this message translates to:
  /// **'Best: {days} d'**
  String recapLongestStreak(int days);

  /// recapLastFourWeeks
  ///
  /// In en, this message translates to:
  /// **'Last 4 weeks'**
  String get recapLastFourWeeks;

  /// recapReadingDays
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{1 reading day} other{{days} reading days}}'**
  String recapReadingDays(int days);

  /// recapMonthTitle
  ///
  /// In en, this message translates to:
  /// **'{monthName} recap'**
  String recapMonthTitle(String monthName);

  /// recapFinishedThisMonth
  ///
  /// In en, this message translates to:
  /// **'finished this month'**
  String get recapFinishedThisMonth;

  /// recapGenreMix
  ///
  /// In en, this message translates to:
  /// **'Genre mix'**
  String get recapGenreMix;

  /// translationPromptFormat
  ///
  /// In en, this message translates to:
  /// **'Prompt format'**
  String get translationPromptFormat;

  /// translationPromptFormatHint
  ///
  /// In en, this message translates to:
  /// **'How requests are worded for this model. Dedicated translation models work best with the format they were trained on; Auto picks it from the model.'**
  String get translationPromptFormatHint;

  /// promptFormatAuto
  ///
  /// In en, this message translates to:
  /// **'Auto ({format})'**
  String promptFormatAuto(String format);

  /// promptFormatGeneral
  ///
  /// In en, this message translates to:
  /// **'General (Gemma and others)'**
  String get promptFormatGeneral;

  /// promptFormatHyMt
  ///
  /// In en, this message translates to:
  /// **'Hy-MT translation model'**
  String get promptFormatHyMt;

  /// promptFormatJaKo
  ///
  /// In en, this message translates to:
  /// **'Japanese→Korean dialogue model'**
  String get promptFormatJaKo;

  /// promptFormatKoreanOnly
  ///
  /// In en, this message translates to:
  /// **'This format translates into Korean only. For other languages the general format is used.'**
  String get promptFormatKoreanOnly;

  /// translationSomeFailed
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 paragraph could not be translated} other{{count} paragraphs could not be translated}}'**
  String translationSomeFailed(int count);

  /// translationReadyPlain
  ///
  /// In en, this message translates to:
  /// **'Translated on this device'**
  String get translationReadyPlain;

  /// translationNeedsRam
  ///
  /// In en, this message translates to:
  /// **'RAM {gb} GB or more'**
  String translationNeedsRam(int gb);

  /// translationFaster
  ///
  /// In en, this message translates to:
  /// **'faster'**
  String get translationFaster;

  /// translationChargingOnly
  ///
  /// In en, this message translates to:
  /// **'Only while charging'**
  String get translationChargingOnly;

  /// translationChargingOnlyHint
  ///
  /// In en, this message translates to:
  /// **'Waits for a charger, so the battery is never spent on it.'**
  String get translationChargingOnlyHint;

  /// translationDevice
  ///
  /// In en, this message translates to:
  /// **'Processor'**
  String get translationDevice;

  /// translationDeviceAuto
  ///
  /// In en, this message translates to:
  /// **'GPU first (faster)'**
  String get translationDeviceAuto;

  /// translationDeviceCpu
  ///
  /// In en, this message translates to:
  /// **'CPU (GPU left for the screen)'**
  String get translationDeviceCpu;

  /// translationDeviceHint
  ///
  /// In en, this message translates to:
  /// **'If scrolling stutters while translating, try the CPU: slower, but the screen keeps the GPU.'**
  String get translationDeviceHint;

  /// translationNoticeChannel
  ///
  /// In en, this message translates to:
  /// **'Background translation'**
  String get translationNoticeChannel;

  /// translationNoticeTitle
  ///
  /// In en, this message translates to:
  /// **'Translating library books'**
  String get translationNoticeTitle;

  /// translationNoticeProgress
  ///
  /// In en, this message translates to:
  /// **'{title} · {percent}%'**
  String translationNoticeProgress(String title, int percent);

  /// translationNoticeCount
  ///
  /// In en, this message translates to:
  /// **'{done}/{total} paragraphs · book {book} of {books}'**
  String translationNoticeCount(int done, int total, int book, int books);

  /// translationNoticeStop
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get translationNoticeStop;

  /// translationNoticeDone
  ///
  /// In en, this message translates to:
  /// **'Library translation finished'**
  String get translationNoticeDone;

  /// translationNoticeDoneCount
  ///
  /// In en, this message translates to:
  /// **'Books translated: {count}'**
  String translationNoticeDoneCount(int count);

  /// translationWaitReading
  ///
  /// In en, this message translates to:
  /// **'Waiting while you read'**
  String get translationWaitReading;

  /// translationWaitAppClosed
  ///
  /// In en, this message translates to:
  /// **'Continues when the app is open'**
  String get translationWaitAppClosed;

  /// translationWaitWarm
  ///
  /// In en, this message translates to:
  /// **'Phone is warm, resting'**
  String get translationWaitWarm;

  /// translationWaitBattery
  ///
  /// In en, this message translates to:
  /// **'Battery low, paused until charging'**
  String get translationWaitBattery;

  /// translationWaitPowerSave
  ///
  /// In en, this message translates to:
  /// **'Battery saver is on, paused'**
  String get translationWaitPowerSave;

  /// translationWaitCharger
  ///
  /// In en, this message translates to:
  /// **'Waiting for a charger'**
  String get translationWaitCharger;

  /// readerWriting
  ///
  /// In en, this message translates to:
  /// **'Text direction'**
  String get readerWriting;

  /// readerWritingAuto
  ///
  /// In en, this message translates to:
  /// **'Book'**
  String get readerWritingAuto;

  /// readerWritingHorizontal
  ///
  /// In en, this message translates to:
  /// **'Across'**
  String get readerWritingHorizontal;

  /// readerWritingVertical
  ///
  /// In en, this message translates to:
  /// **'Vertical'**
  String get readerWritingVertical;

  /// readerLoadFailed
  ///
  /// In en, this message translates to:
  /// **'This book could not be shown.'**
  String get readerLoadFailed;

  /// readerOpenSimple
  ///
  /// In en, this message translates to:
  /// **'Open in the simple reader'**
  String get readerOpenSimple;

  /// ok
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// downloadPreparing
  ///
  /// In en, this message translates to:
  /// **'Preparing…'**
  String get downloadPreparing;

  /// downloadStartedTitle
  ///
  /// In en, this message translates to:
  /// **'Download started'**
  String get downloadStartedTitle;

  /// downloadStartedBody
  ///
  /// In en, this message translates to:
  /// **'It joins your library when it finishes. The notification shows the progress.'**
  String get downloadStartedBody;

  /// downloadFastBadge
  ///
  /// In en, this message translates to:
  /// **'Fast download'**
  String get downloadFastBadge;

  /// downloadNotStartedTitle
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t start the download'**
  String get downloadNotStartedTitle;

  /// Update sheet title
  ///
  /// In en, this message translates to:
  /// **'A new version is out'**
  String get updateAvailableTitle;

  /// Update sheet title when the APK is downloaded
  ///
  /// In en, this message translates to:
  /// **'Update ready to install'**
  String get updateReadyTitle;

  /// Heading above the change list
  ///
  /// In en, this message translates to:
  /// **'What\'s changed'**
  String get updateChangesTitle;

  /// Shown when a release has no change lines
  ///
  /// In en, this message translates to:
  /// **'No change notes for this build.'**
  String get updateNoNotes;

  /// Progress before the size is known
  ///
  /// In en, this message translates to:
  /// **'Downloading…'**
  String get updateDownloading;

  /// Error under the retry button
  ///
  /// In en, this message translates to:
  /// **'The update could not be downloaded.'**
  String get updateDownloadFailed;

  /// Primary button
  ///
  /// In en, this message translates to:
  /// **'Download and install'**
  String get updateDownloadInstall;

  /// Primary button with the APK size
  ///
  /// In en, this message translates to:
  /// **'Download and install · {size}'**
  String updateDownloadInstallSize(String size);

  /// Primary button when downloaded
  ///
  /// In en, this message translates to:
  /// **'Install now'**
  String get updateInstallNow;

  /// Dismiss the update for a day
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get updateLater;

  /// Opens the releases page
  ///
  /// In en, this message translates to:
  /// **'GitHub'**
  String get updateViewOnGithub;

  /// Button on the update banner
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get updateAction;

  /// Settings switch
  ///
  /// In en, this message translates to:
  /// **'Download updates automatically'**
  String get autoDownloadUpdates;

  /// Settings switch subtitle
  ///
  /// In en, this message translates to:
  /// **'New builds are fetched over Wi-Fi, ready to install'**
  String get autoDownloadUpdatesHint;

  /// Settings tile and page title
  ///
  /// In en, this message translates to:
  /// **'Update history'**
  String get releaseHistoryTitle;

  /// Settings tile subtitle
  ///
  /// In en, this message translates to:
  /// **'Every build released on GitHub'**
  String get releaseHistoryHint;

  /// Error state
  ///
  /// In en, this message translates to:
  /// **'The update history could not be loaded.'**
  String get releaseHistoryFailed;

  /// Badge on the newest release
  ///
  /// In en, this message translates to:
  /// **'Latest'**
  String get releaseLatest;

  /// Badge on the running build
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get releaseInstalled;

  /// Home-screen widget with an empty library
  ///
  /// In en, this message translates to:
  /// **'Books you add to your library show up here'**
  String get widgetEmptyLibrary;

  /// Home-screen widget: the second book
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get widgetNextUp;

  /// Reader: the book glossary
  ///
  /// In en, this message translates to:
  /// **'Glossary'**
  String get glossaryTitle;

  /// Glossary sheet subtitle
  ///
  /// In en, this message translates to:
  /// **'Every translation writes these names and terms this way. Tap one to change it.'**
  String get glossaryHint;

  /// While the glossary is being made
  ///
  /// In en, this message translates to:
  /// **'Reading the book to make its glossary…'**
  String get glossaryMaking;

  /// Empty glossary
  ///
  /// In en, this message translates to:
  /// **'No glossary yet. It is made when you translate this book.'**
  String get glossaryEmpty;

  /// Remake the glossary (edits kept)
  ///
  /// In en, this message translates to:
  /// **'Make again'**
  String get glossaryRemake;

  /// Glossary kind
  ///
  /// In en, this message translates to:
  /// **'Person'**
  String get glossaryKindPerson;

  /// Glossary kind
  ///
  /// In en, this message translates to:
  /// **'Place'**
  String get glossaryKindPlace;

  /// Glossary kind
  ///
  /// In en, this message translates to:
  /// **'Term'**
  String get glossaryKindTerm;

  /// Glossary gender
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get glossaryGenderMale;

  /// Glossary gender
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get glossaryGenderFemale;

  /// Glossary gender
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get glossaryGenderUnknown;

  /// Glossary edit: the target form
  ///
  /// In en, this message translates to:
  /// **'Written as'**
  String get glossaryKorean;

  /// Home: Japanese books (BOOK☆WALKER)
  ///
  /// In en, this message translates to:
  /// **'Japan'**
  String get homeRegionJapan;

  /// Home: English-language books (Goodreads and others)
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get homeRegionWestern;

  /// Home: Japanese light novels
  ///
  /// In en, this message translates to:
  /// **'Light novels'**
  String get japanLightNovels;

  /// Home: Japanese new literature (web novels published as books)
  ///
  /// In en, this message translates to:
  /// **'Web novels in print'**
  String get japanNewLiterature;

  /// Home: Japanese manga
  ///
  /// In en, this message translates to:
  /// **'Manga'**
  String get japanManga;

  /// Settings/onboarding: the picked storage folder is not writable
  ///
  /// In en, this message translates to:
  /// **'Books can\'t be saved in that folder. Choose the app\'s folder, or one inside Download or Documents.'**
  String get storageNotWritable;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
        'de',
        'en',
        'es',
        'fr',
        'ja',
        'ko'
      ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'ja':
      return AppLocalizationsJa();
    case 'ko':
      return AppLocalizationsKo();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
