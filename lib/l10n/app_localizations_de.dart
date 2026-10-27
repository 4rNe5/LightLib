// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'LightLib';

  @override
  String get navHome => 'Start';

  @override
  String get navSearch => 'Suche';

  @override
  String get navMyLibrary => 'Meine Bibliothek';

  @override
  String get navSettings => 'Einstellungen';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get save => 'Speichern';

  @override
  String get add => 'Hinzufügen';

  @override
  String get delete => 'Löschen';

  @override
  String get retry => 'Erneut versuchen';

  @override
  String get advancedSearch => 'Erweiterte Suche';

  @override
  String get author => 'Autor';

  @override
  String get publisher => 'Verlag';

  @override
  String get searchLibraryHint =>
      'Bibliothek durchsuchen (Titel, Autor, Verlag, Jahr)';

  @override
  String get newCollection => 'Neue Sammlung';

  @override
  String get noResultsFound => 'Keine Ergebnisse gefunden';

  @override
  String resultsFor(String query) {
    return 'Ergebnisse für \'$query\'';
  }

  @override
  String get followSystem => 'Dem System folgen';

  @override
  String get lightTheme => 'Helles Design';

  @override
  String get darkTheme => 'Dunkles Design';

  @override
  String get languageSetting => 'Sprache';

  @override
  String get systemLanguage => 'Systemstandard';

  @override
  String get enableNotifications => 'Benachrichtigungen aktivieren';

  @override
  String get notificationsExplanation =>
      'LightLib benötigt die Berechtigung für Benachrichtigungen, um den Download-Fortschritt im Hintergrund anzuzeigen. So behalten Sie Ihre Buch-Downloads auch im minimierten Zustand im Blick.';

  @override
  String get maybeLater => 'Vielleicht später';

  @override
  String get enable => 'Aktivieren';

  @override
  String get statusUnread => 'Ungelesen';

  @override
  String get statusInProgress => 'In Bearbeitung';

  @override
  String get statusCompleted => 'Fertig';

  @override
  String get collectionNameHint => 'z. B. Favoriten, Science-Fiction';

  @override
  String get manageCollectionsHint =>
      'Halten Sie ein Buch lange gedrückt, um seine Sammlungen zu verwalten';

  @override
  String get results => 'Ergebnisse';

  @override
  String get loading => 'Wird geladen...';

  @override
  String get unknown => 'Unbekannt';

  @override
  String get about => 'Über';

  @override
  String get aboutDescription =>
      'Eine Open-Source-App zum Herunterladen und Lesen von Büchern aus Schattenbibliotheken (Anna\'s Archive).';

  @override
  String get aboutForkNote =>
      'Dies ist eine Fork-Version, gepflegt von warreth für den persönlichen Gebrauch und Community-Updates.';

  @override
  String get aboutOriginalNote =>
      'Original-App von dstark5 (https://github.com/dstark5/Openlib).';

  @override
  String get version => 'Version';

  @override
  String get github => 'Github';

  @override
  String get thisForkByWarreth => 'Dieser Fork (von warreth)';

  @override
  String get reportAnIssue => 'Problem melden';

  @override
  String get originalProject => 'Original-Projekt (von dstark5)';

  @override
  String get licence => 'Lizenz';

  @override
  String get gplLicense => 'GPL v3.0 Lizenz';

  @override
  String couldNotLaunch(String url) {
    return 'Konnte $url nicht öffnen';
  }

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get searchProvidersSection => 'Suchanbieter';

  @override
  String get libraryInstancesSection => 'Bibliothek & Instanzen';

  @override
  String get appearanceSection => 'Erscheinungsbild';

  @override
  String get generalSection => 'Allgemein';

  @override
  String get readerSection => 'Leser';

  @override
  String get advancedSection => 'Erweitert';

  @override
  String get backupSection => 'Sicherung';

  @override
  String get updatesSection => 'Updates';

  @override
  String get aboutSection => 'Über';

  @override
  String get archiveInstance => 'Archiv-Instanz';

  @override
  String get mirrorsAndProviders => 'Spiegel & Anbieter';

  @override
  String get fontSizeTitle => 'Schriftgröße';

  @override
  String scaleValue(String value) {
    return 'Skalierung: ${value}x';
  }

  @override
  String get preview => 'Vorschau';

  @override
  String get storageLocation => 'Speicherort';

  @override
  String get openPdfExternally => 'PDF extern öffnen';

  @override
  String get useDefaultPdfViewer => 'Standard-PDF-Viewer verwenden';

  @override
  String get openEpubExternally => 'EPUB extern öffnen';

  @override
  String get useDefaultEpubReader => 'Standard-EPUB-Reader verwenden';

  @override
  String get manualDownloadButton => 'Manuelle Download-Schaltfläche';

  @override
  String get backgroundVerification => 'Verifizierung im Hintergrund';

  @override
  String get backgroundVerificationHint =>
      'Löst DDoS-Prüfungen unsichtbar. Auf manchen Geräten schlägt das fehl - ausschalten, um stattdessen in einem sichtbaren Fenster zu prüfen';

  @override
  String get backgroundVerificationFix =>
      'Falls die Verifizierung immer wieder fehlschlägt, deaktiviere \"Verifizierung im Hintergrund\" in den Einstellungen - manche Geräte können Prüfungen nicht unsichtbar lösen.';

  @override
  String get showManualDownloadHint =>
      'Schaltfläche zum manuellen Starten von Downloads anzeigen';

  @override
  String get donationKeyTitle => 'Anna\'s Archive Spende-Schlüssel';

  @override
  String get enterKeyForFasterDownloads =>
      'Schlüssel für schnellere Downloads eingeben';

  @override
  String get aboutOpenlib => 'Über LightLib';

  @override
  String get redoOnboarding => 'Onboarding wiederholen';

  @override
  String get resetAppSetup => 'App-Setup zurücksetzen und neu starten';

  @override
  String get exportLogs => 'Protokolle exportieren';

  @override
  String get shareDiagnosticLogs => 'Diagnoseprotokolle teilen (letzte 5 Min.)';

  @override
  String failedExportLogs(String error) {
    return 'Protokolle konnten nicht exportiert werden: $error';
  }

  @override
  String get donationKeyDialog => 'Spende-Schlüssel';

  @override
  String get enterYourKey => 'Schlüssel eingeben';

  @override
  String get instanceChanged => 'Instanz erfolgreich geändert';

  @override
  String rankingFailed(String error) {
    return 'Rangfolge fehlgeschlagen: $error';
  }

  @override
  String get autoRankInstances => 'Instanzen automatisch sortieren';

  @override
  String get sortBySpeedOnStartup =>
      'Beim Start automatisch nach Geschwindigkeit sortieren';

  @override
  String get rankInstancesNow => 'Instanzen jetzt sortieren';

  @override
  String onLatestVersion(String version) {
    return 'Sie nutzen die neueste Version ($version)';
  }

  @override
  String failedCheckUpdates(String error) {
    return 'Update-Prüfung fehlgeschlagen: $error';
  }

  @override
  String get includeBetaUpdates => 'Beta-Updates einbeziehen';

  @override
  String get getPreReleaseVersions => 'Vorabversionen erhalten';

  @override
  String get checkForUpdates => 'Nach Updates suchen';

  @override
  String get backupSaved => 'Sicherung gespeichert';

  @override
  String failedExportBackup(String error) {
    return 'Sicherung konnte nicht exportiert werden: $error';
  }

  @override
  String get backupRestored => 'Sicherung wiederhergestellt';

  @override
  String failedImportBackup(String error) {
    return 'Sicherung konnte nicht importiert werden: $error';
  }

  @override
  String get atLeastOneSource => 'Mindestens eine Suchquelle ist erforderlich';

  @override
  String rankedFastest(String name, String time) {
    return 'Sortiert! Schnellste: $name (${time}ms)';
  }

  @override
  String get rankingComplete => 'Sortierung abgeschlossen';

  @override
  String get providerSourceOriginal =>
      'Wird zuletzt durchsucht - durch DDoS-Guard geschützt';

  @override
  String get providerLibgenCatalog =>
      'Schnelle, direkte Downloads - wird zuerst durchsucht';

  @override
  String get providerZlibMirrors =>
      'Spiegel wechseln; Anmeldung kann nötig sein';

  @override
  String get themeTitle => 'Design';

  @override
  String get saveBackupTitle => 'Sicherung speichern';

  @override
  String get pickBackupFile => 'Sicherungsdatei auswählen';

  @override
  String get notABackup => 'Diese Datei ist keine LightLib-Sicherung';

  @override
  String get donationKeyHelper =>
      'Wird für schnellere Downloads auf Anna\'s Archive verwendet';

  @override
  String get mirrorsTestedRanked =>
      'Spiegel getestet und nach Geschwindigkeit sortiert';

  @override
  String testingFailed(String error) {
    return 'Test fehlgeschlagen: $error';
  }

  @override
  String get addCustomMirror => 'Benutzerdefinierten Spiegel hinzufügen';

  @override
  String get nameLabel => 'Name';

  @override
  String get nameHint => 'z. B. Mein LibGen-Spiegel';

  @override
  String get serviceLabel => 'Dienst';

  @override
  String get urlLabel => 'URL';

  @override
  String get urlHint => 'https://example.com';

  @override
  String get pleaseFillAllFields => 'Bitte alle Felder ausfüllen';

  @override
  String get enterValidUrl =>
      'Bitte eine gültige URL mit http:// oder https:// eingeben';

  @override
  String get mirrorAdded => 'Spiegel erfolgreich hinzugefügt';

  @override
  String get deleteMirror => 'Spiegel löschen';

  @override
  String deleteMirrorConfirm(String name) {
    return 'Möchten Sie \"$name\" wirklich löschen?';
  }

  @override
  String get mirrorDeleted => 'Spiegel gelöscht';

  @override
  String get cannotDeleteDefaultMirrors =>
      'Standard-Spiegel können nicht gelöscht werden';

  @override
  String get manageMirrors => 'Spiegel verwalten';

  @override
  String get noMirrorsAvailable => 'Keine Spiegel verfügbar';

  @override
  String errorLabel(String error) {
    return 'Fehler: $error';
  }

  @override
  String get addMirror => 'Spiegel hinzufügen';

  @override
  String get testRankMirrors =>
      'Spiegel testen und nach Geschwindigkeit sortieren';

  @override
  String get unreachable => 'nicht erreichbar';

  @override
  String get open => 'Öffnen';

  @override
  String get unableToOpenFile => 'Datei konnte nicht geöffnet werden!';

  @override
  String get openInSite => 'Auf der Seite öffnen';

  @override
  String get bookDeleted => 'Buch wurde gelöscht!';

  @override
  String get deleteBook => 'Buch löschen';

  @override
  String get deletePermanentWarning =>
      'Dies ist dauerhaft und kann nicht rückgängig gemacht werden';

  @override
  String get tryAgain => 'Erneut versuchen';

  @override
  String get showBlockedContent => 'Gesperrten Seiteninhalt anzeigen';

  @override
  String get verifyInBrowser => 'Im Browser verifizieren';

  @override
  String get manualVerificationRequired =>
      'Manuelle Verifizierung erforderlich';

  @override
  String get systemBrowser => 'Systembrowser';

  @override
  String get embeddedBrowser => 'Eingebetteter Browser';

  @override
  String get unableToOpenVerification =>
      'Verifizierungsseite konnte nicht geöffnet werden – keine URL verfügbar';

  @override
  String get blockedPageContent => 'Gesperrter Seiteninhalt';

  @override
  String get copiedToClipboard => 'In die Zwischenablage kopiert';

  @override
  String get gotIt => 'Verstanden!';

  @override
  String get copy => 'Kopieren';

  @override
  String get tryUsingVpn => 'Versuchen Sie ein VPN';

  @override
  String get trending => 'Beliebt';

  @override
  String get genres => 'Genres';

  @override
  String get copiedBookPath => 'Buchpfad in die Zwischenablage kopiert';

  @override
  String get pauseDownload => 'Download anhalten';

  @override
  String get resumeDownload => 'Download fortsetzen';

  @override
  String get cancelDownload => 'Download abbrechen';

  @override
  String get copiedBookLink => 'Buchlink in die Zwischenablage kopiert';

  @override
  String get noMirrors => 'Keine Spiegel verfügbar!';

  @override
  String get addToMyLibrary => 'Zu Meiner Bibliothek hinzufügen';

  @override
  String get downloadStartedBackground => 'Download im Hintergrund gestartet';

  @override
  String get bookDownloaded => 'Buch wurde heruntergeladen!';

  @override
  String get selectStorageToContinue =>
      'Bitte wählen Sie einen Speicherordner aus, um fortzufahren';

  @override
  String get getStarted => 'Loslegen';

  @override
  String get next => 'Weiter';

  @override
  String get welcomeTitle => 'Willkommen bei LightLib';

  @override
  String get welcomeSubtitle =>
      'Ihr persönliches Tor zu einer Welt voller Wissen. Lassen Sie uns alles einrichten.';

  @override
  String get whereToStoreBooks => 'Wo sollen Ihre Bücher gespeichert werden?';

  @override
  String get noPathSelected => 'Kein Pfad ausgewählt';

  @override
  String get selectFolder => 'Ordner auswählen';

  @override
  String get storageScanNote =>
      'Wir durchsuchen diesen Ordner nur nach PDF-/EPUB-Dateien. Unterordner werden nicht eingescannt.';

  @override
  String get automaticUpdates => 'Automatische Updates';

  @override
  String get enableAutoUpdates => 'Auto-Updates aktivieren';

  @override
  String get autoUpdatesFdroidNote =>
      'Nicht empfohlen bei Installation über F-Droid (F-Droid verwaltet die Updates).';

  @override
  String get enableBetaUpdatesOnboarding => 'Beta-Updates aktivieren';

  @override
  String get betaUpdatesNote =>
      'Vorabversionen (Beta-Updates) erhalten, wenn verfügbar.';

  @override
  String get supportAnnasArchive => 'Anna\'s Archive unterstützen';

  @override
  String get donationPitch =>
      'Eine Spende an Anna\'s Archive ermöglicht schnellere Downloads und hilft, den Dienst für alle am Laufen zu halten. Sie können Ihren geheimen Schlüssel unten eingeben.';

  @override
  String get annasSecretKey => 'Geheimer Schlüssel von Anna\'s Archive';

  @override
  String get supportThisApp => 'Diese App unterstützen';

  @override
  String get sponsorPitch =>
      'Wenn Ihnen diese App gefällt, ziehen Sie in Betracht, die Entwicklung zu unterstützen. So kann ich mehr Zeit in die Verbesserung stecken!';

  @override
  String get sponsorOnGithub => 'Auf GitHub sponsern';

  @override
  String get stayUpdated => 'Auf dem Laufenden bleiben';

  @override
  String get notifyOnComplete =>
      'Benachrichtigung erhalten, wenn Downloads abgeschlossen sind.';

  @override
  String get chooseTheme => 'Design wählen';

  @override
  String get lightThemeShort => 'Hell';

  @override
  String get darkThemeShort => 'Dunkel';

  @override
  String get verifyingAccess => 'Zugriff wird verifiziert';

  @override
  String get done => 'Fertig';

  @override
  String get nothingToRead => 'Nichts auf dieser Seite zu lesen';

  @override
  String get noVoiceAvailable => 'Keine Stimme für das Vorlesen verfügbar';

  @override
  String get pauseReadingAloud => 'Vorlesen anhalten';

  @override
  String get resumeReadingAloud => 'Vorlesen';

  @override
  String get stopReadingAloud => 'Vorlesen beenden';

  @override
  String get speechSpeed => 'Sprechgeschwindigkeit';

  @override
  String get decreaseFontSize => 'Schriftgröße verkleinern';

  @override
  String get increaseFontSize => 'Schriftgröße vergrößern';

  @override
  String get close => 'Schließen';

  @override
  String get sortLibrary => 'Bibliothek sortieren';

  @override
  String get reloadHealthData => 'Gesundheitsdaten neu laden';

  @override
  String addServiceMirror(String title) {
    return '$title-Spiegel hinzufügen';
  }

  @override
  String get deleteMirrorTooltip => 'Spiegel löschen';

  @override
  String get ttsEngineMissing =>
      'Keine Sprachausgabe-Engine gefunden. Installiere eine (z.B. Sprachdienste) in den Systemeinstellungen.';

  @override
  String get previousPage => 'Vorherige Seite';

  @override
  String get nextPage => 'Nächste Seite';

  @override
  String searchingOn(String source) {
    return 'Ergebnisse von $source';
  }

  @override
  String get sourceLibgen => 'LibGen';

  @override
  String get sourceZlib => 'Z-Library';

  @override
  String get sourceAnnas => 'Anna\'s Archive';

  @override
  String downloadFrom(String source) {
    return 'Download von $source';
  }

  @override
  String get tryingNextSource =>
      'Keine Ergebnisse, nächste Quelle wird versucht…';

  @override
  String get slowMirrorsSkipped => 'Schnellere Spiegel werden verwendet';

  @override
  String whatsNewTitle(String version) {
    return 'Neu in $version';
  }

  @override
  String get whatsNewIntro =>
      'LightLib wurde aktualisiert. Das hat sich geändert.';

  @override
  String get whatsNewTabFeatures => 'Neue Funktionen';

  @override
  String get whatsNewTabSources => 'Quellen & Mirror';

  @override
  String get whatsNewProvidersHint =>
      'Dieses Release fügt neue Suchanbieter und Mirror hinzu. Aktualisiere deine Liste, um tote Mirror zu entfernen und die neuen hinzuzufügen; alle drei Suchanbieter werden aktiviert.';

  @override
  String get whatsNewUpdateInstances => 'Mirror-Liste aktualisieren';

  @override
  String get whatsNewInstancesUpdated => 'Mirror-Liste aktualisiert';

  @override
  String get whatsNewContinue => 'Weiter';

  @override
  String get whatsNewFeatureSpeed =>
      'Downloads starten schneller: keine Mirror-Prüfung mehr, schnelle Hosts zuerst, langsame IPFS-Gateways zuletzt.';

  @override
  String get whatsNewFeatureSourceLabels =>
      'Jedes Suchergebnis und jeder Download zeigt jetzt, aus welchem Katalog er stammt.';

  @override
  String get whatsNewFeatureCovers =>
      'Fehlende LibGen-Cover werden von der Detailseite des Buchs geladen.';

  @override
  String get zlibRecommendationsTitle => 'Das könnte dich auch interessieren';

  @override
  String get zlibRecommendationsLoadMore => 'Mehr laden';

  @override
  String get zlibRecommendationsLoadFailed =>
      'Weitere Bücher konnten nicht geladen werden';

  @override
  String get searchingSources => 'Suche läuft…';

  @override
  String searchingSource(String source) {
    return 'Suche in $source…';
  }

  @override
  String tryingNextSourceNamed(String previous, String source) {
    return 'Nichts in $previous, versuche $source…';
  }

  @override
  String get translationTranslate => 'Übersetzen';

  @override
  String get translationShowOriginal => 'Original anzeigen';

  @override
  String get translationNoModel => 'Noch kein Übersetzungsmodell installiert.';

  @override
  String get translationOpenSettings => 'Einrichten';

  @override
  String get translationLoadingModel =>
      'Übersetzungsmodell wird vorbereitet… (beim ersten Mal einige Minuten)';

  @override
  String translationTranslating(int count, String device) {
    return 'Übersetze · noch $count · $device';
  }

  @override
  String translationReady(String device) {
    return 'Auf diesem Gerät übersetzt · $device';
  }

  @override
  String get translationPaused => 'Übersetzung pausiert';

  @override
  String get translationFailed => 'Das Übersetzungsmodell konnte nicht laufen.';

  @override
  String get translationSettingsTitle => 'Übersetzung auf dem Gerät';

  @override
  String get translationSettingsSubtitle =>
      'Bücher im Reader mit einem lokalen KI-Modell übersetzen';

  @override
  String get translationTargetLanguage => 'Übersetzen in';

  @override
  String get translationModels => 'Modelle';

  @override
  String get translationModelsHint =>
      'LiteRT läuft auf der GPU und weicht auf die CPU aus. Die GGUF-Datei ist für Geräte, auf denen LiteRT nicht läuft.';

  @override
  String get translationRecommended => 'empfohlen';

  @override
  String get translationDownload => 'Herunterladen';

  @override
  String translationDownloadConfirm(String size) {
    return 'Es werden $size heruntergeladen. Nutze nach Möglichkeit WLAN. Die Datei bleibt auf dem Gerät.';
  }

  @override
  String get translationVerifying => 'Datei wird geprüft…';

  @override
  String translationDownloadFailed(String error) {
    return 'Download fehlgeschlagen: $error';
  }

  @override
  String get translationInUse => 'Aktiv';

  @override
  String get translationUse => 'Verwenden';

  @override
  String get translationDeleteConfirm => 'Diese Modelldatei vom Gerät löschen?';

  @override
  String get translationImportModel =>
      'Modelldatei importieren (.litertlm / .gguf)';

  @override
  String get translationNotAModel => 'Wähle eine .litertlm- oder .gguf-Datei.';

  @override
  String get translationImported => 'Modell importiert und ausgewählt.';

  @override
  String get translationImportFailed =>
      'Die Modelldatei konnte nicht importiert werden.';

  @override
  String get translationBatteryNote =>
      'Übersetzt werden nur die sichtbaren und einige folgende Absätze; Ergebnisse werden gespeichert. Im Hintergrund pausiert die Übersetzung.';

  @override
  String get translationClearCache => 'Gespeicherte Übersetzungen löschen';

  @override
  String get translationCacheCleared => 'Gespeicherte Übersetzungen gelöscht.';

  @override
  String get importBooks => 'EPUB / PDF importieren';

  @override
  String get importBooksFailed =>
      'Die Dateiauswahl konnte nicht geöffnet werden.';

  @override
  String importBooksResult(int imported, int existing, int failed) {
    return 'Hinzugefügt $imported · schon vorhanden $existing · fehlgeschlagen $failed';
  }

  @override
  String get translationAutoLibrary =>
      'Bibliotheksbücher im Hintergrund übersetzen';

  @override
  String get translationAutoLibraryHint =>
      'Aus, bis du es einschaltest. Langsam und schonend: Pause nach jedem Absatz, wartet beim Lesen oder wenn das Gerät warm oder der Akku schwach ist, und läuft mit einer Benachrichtigung weiter, wenn du die App verlässt. Übersetzungen werden neben jedem Buch gespeichert.';

  @override
  String get translationBookDone => 'Fertig';

  @override
  String get readerViewOptions => 'Ansicht';

  @override
  String get readerLayoutScroll => 'Scrollen';

  @override
  String get readerLayoutPagesLtr => 'Seiten (links nach rechts)';

  @override
  String get readerLayoutPagesRtl => 'Seiten (rechts nach links, Manga)';

  @override
  String get readerFonts => 'Schriften';

  @override
  String get fontsSettingsSubtitle =>
      'Schriften für koreanischen, japanischen und lateinischen Text';

  @override
  String get fontsHint =>
      'Jede Schrift nutzt ihre eigene Schriftart. Google Fonts werden einmal geladen und funktionieren danach offline. Du kannst auch eine .ttf- oder .otf-Datei importieren.';

  @override
  String get fontKorean => 'Koreanischer Text';

  @override
  String get fontJapanese => 'Japanischer Text';

  @override
  String get fontLatin => 'Lateinischer Text';

  @override
  String get fontSystem => 'Systemstandard';

  @override
  String get fontFile => 'Datei';

  @override
  String get fontImport => 'Schriftdatei importieren (.ttf / .otf)';

  @override
  String fontImported(String family) {
    return 'Schrift importiert: $family';
  }

  @override
  String get fontImportFailed => 'Die Schrift konnte nicht importiert werden.';

  @override
  String get readerThemesSettings => 'Themen & Einstellungen';

  @override
  String get readerThemeOriginal => 'Original';

  @override
  String get readerThemePaper => 'Papier';

  @override
  String get readerThemeCalm => 'Ruhig';

  @override
  String get readerThemeQuiet => 'Leise';

  @override
  String get readerThemeBold => 'Fett';

  @override
  String get readerThemeNight => 'Nacht';

  @override
  String get readerLayout => 'Layout';

  @override
  String get readerLayoutPagesShort => 'Seiten';

  @override
  String get readerLayoutMangaShort => 'Manga';

  @override
  String get readerFont => 'Schrift';

  @override
  String get readerAllFonts => 'Schriften je Sprache';

  @override
  String get readerCustomize => 'Anpassen';

  @override
  String get readerFontSize => 'Textgröße';

  @override
  String get readerLineSpacing => 'Zeilenabstand';

  @override
  String get readerLetterSpacing => 'Zeichenabstand';

  @override
  String get readerMargins => 'Ränder';

  @override
  String get readerJustify => 'Blocksatz';

  @override
  String get readerBoldText => 'Fetter Text';

  @override
  String get readerReset => 'Zurücksetzen';

  @override
  String get readerContents => 'Inhalt';

  @override
  String get libraryContinueReading => 'Weiterlesen';

  @override
  String get libraryAllBooks => 'Alle Bücher';

  @override
  String libraryBookCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Bücher',
      one: '1 Buch',
    );
    return '$_temp0';
  }

  @override
  String get libraryNoMatches => 'Keine Bücher entsprechen den Filtern';

  @override
  String get libraryEmpty => 'Deine Bibliothek ist leer';

  @override
  String get libraryEmptyHint =>
      'Importiere eigene EPUB- oder PDF-Dateien, um mit dem Lesen zu beginnen.';

  @override
  String get bookGenre => 'Genre';

  @override
  String get bookCollections => 'Sammlungen';

  @override
  String get genreAll => 'Alle';

  @override
  String get genreNone => 'Kein Genre';

  @override
  String get genreLightNovel => 'Light Novel';

  @override
  String get genreComic => 'Comics';

  @override
  String get genreNovel => 'Roman';

  @override
  String get genreEnglishNovel => 'Englische Romane';

  @override
  String get genreEssay => 'Essay';

  @override
  String get genreScience => 'Wissenschaft';

  @override
  String get genreHumanities => 'Geisteswissenschaften';

  @override
  String get genreBusiness => 'Wirtschaft';

  @override
  String get genrePaper => 'Fachartikel';

  @override
  String get genreTextbook => 'Lehrbücher';

  @override
  String get genreOther => 'Sonstiges';

  @override
  String get translationLightNovelStyle => 'Light-Novel-Stil';

  @override
  String get translationLightNovelStyleHint =>
      'Erhält Du- und Sie-Form, Sprechweisen der Figuren, Anreden und Lautmalerei. Für Sachbücher ausschalten. Jeder Stil speichert eigene Übersetzungen.';

  @override
  String get libraryBookOptions => 'Buchoptionen';

  @override
  String get libraryRecentlyAdded => 'Zuletzt hinzugefügt';

  @override
  String get libraryReadingNow => 'Lese ich gerade';

  @override
  String libraryFinishedCount(int count) {
    return '$count beendet';
  }

  @override
  String get recentSearches => 'Letzte Suchen';

  @override
  String get clearAll => 'Alle löschen';

  @override
  String get removeFromHistory => 'Aus dem Verlauf entfernen';

  @override
  String get searchHistoryFill => 'Suche bearbeiten';

  @override
  String get showMore => 'Mehr anzeigen';

  @override
  String get showLess => 'Weniger anzeigen';

  @override
  String get searchHistorySection => 'Suchverlauf';

  @override
  String get saveSearchHistory => 'Suchverlauf speichern';

  @override
  String get saveSearchHistoryHint => 'Letzte Suchen im Suche-Tab anzeigen';

  @override
  String get clearSearchHistory => 'Suchverlauf löschen';

  @override
  String savedSearchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count gespeicherte Suchen',
      one: '1 gespeicherte Suche',
      zero: 'Keine gespeicherten Suchen',
    );
    return '$_temp0';
  }

  @override
  String get searchHistoryCleared => 'Suchverlauf gelöscht';

  @override
  String get themeSystemShort => 'System';

  @override
  String get themeLightShort => 'Hell';

  @override
  String get themeDarkShort => 'Dunkel';

  @override
  String get recapTitle => 'Lesebilanz';

  @override
  String get recapCheckpoints => 'Meilensteine';

  @override
  String get recapBooksUnit => '';

  @override
  String get recapDaysUnit => '';

  @override
  String get recapAllCheckpoints => 'Alle Meilensteine erreicht!';

  @override
  String recapToNextCheckpoint(int remaining, int next) {
    return 'Noch $remaining bis $next';
  }

  @override
  String get recapStreak => 'Tage in Folge';

  @override
  String get recapStreakStart => 'Heute lesen und starten';

  @override
  String recapLongestStreak(int days) {
    return 'Rekord: $days T.';
  }

  @override
  String get recapLastFourWeeks => 'Letzte 4 Wochen';

  @override
  String recapReadingDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days Lesetage',
      one: '1 Lesetag',
    );
    return '$_temp0';
  }

  @override
  String recapMonthTitle(String monthName) {
    return '$monthName im Rückblick';
  }

  @override
  String get recapFinishedThisMonth => 'diesen Monat beendet';

  @override
  String get recapGenreMix => 'Genre-Mix';

  @override
  String get translationPromptFormat => 'Prompt-Format';

  @override
  String get translationPromptFormatHint =>
      'Wie Anfragen an dieses Modell formuliert werden. Übersetzungsmodelle arbeiten am besten mit ihrem Trainingsformat; Automatisch wählt es anhand des Modells.';

  @override
  String promptFormatAuto(String format) {
    return 'Automatisch ($format)';
  }

  @override
  String get promptFormatGeneral => 'Allgemein (Gemma u. a.)';

  @override
  String get promptFormatHyMt => 'Hy-MT-Übersetzungsmodell';

  @override
  String get promptFormatJaKo => 'Japanisch→Koreanisch-Dialogmodell';

  @override
  String get promptFormatKoreanOnly =>
      'Dieses Format übersetzt nur ins Koreanische. Für andere Sprachen wird das allgemeine Format verwendet.';

  @override
  String translationSomeFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Absätze konnten nicht übersetzt werden',
      one: '1 Absatz konnte nicht übersetzt werden',
    );
    return '$_temp0';
  }

  @override
  String get translationReadyPlain => 'Auf dem Gerät übersetzt';

  @override
  String translationNeedsRam(int gb) {
    return 'ab $gb GB RAM';
  }

  @override
  String get translationFaster => 'schneller';

  @override
  String get translationChargingOnly => 'Nur beim Laden';

  @override
  String get translationChargingOnlyHint =>
      'Wartet auf ein Ladegerät, damit kein Akku dafür verbraucht wird.';

  @override
  String get translationDevice => 'Prozessor';

  @override
  String get translationDeviceAuto => 'Zuerst GPU (schneller)';

  @override
  String get translationDeviceCpu => 'CPU (GPU bleibt für den Bildschirm)';

  @override
  String get translationDeviceHint =>
      'Ruckelt das Scrollen beim Übersetzen, probiere die CPU: langsamer, aber der Bildschirm behält die GPU.';

  @override
  String get translationNoticeChannel => 'Hintergrundübersetzung';

  @override
  String get translationNoticeTitle => 'Bibliotheksbücher werden übersetzt';

  @override
  String translationNoticeProgress(String title, int percent) {
    return '$title · $percent %';
  }

  @override
  String translationNoticeCount(int done, int total, int book, int books) {
    return '$done/$total Absätze · Buch $book von $books';
  }

  @override
  String get translationNoticeStop => 'Beenden';

  @override
  String get translationNoticeDone => 'Bibliotheksübersetzung fertig';

  @override
  String translationNoticeDoneCount(int count) {
    return 'Übersetzte Bücher: $count';
  }

  @override
  String get translationWaitReading => 'Wartet, während du liest';

  @override
  String get translationWaitAppClosed => 'Geht weiter, wenn die App offen ist';

  @override
  String get translationWaitWarm => 'Gerät ist warm, Pause';

  @override
  String get translationWaitBattery => 'Akku schwach, pausiert bis zum Laden';

  @override
  String get translationWaitPowerSave => 'Energiesparmodus an, pausiert';

  @override
  String get translationWaitCharger => 'Wartet auf ein Ladegerät';

  @override
  String get readerWriting => 'Schreibrichtung';

  @override
  String get readerWritingAuto => 'Buch';

  @override
  String get readerWritingHorizontal => 'Waagerecht';

  @override
  String get readerWritingVertical => 'Senkrecht';

  @override
  String get readerLoadFailed => 'Dieses Buch konnte nicht angezeigt werden.';

  @override
  String get readerOpenSimple => 'Im einfachen Reader öffnen';

  @override
  String get ok => 'OK';

  @override
  String get downloadPreparing => 'Wird vorbereitet…';

  @override
  String get downloadStartedTitle => 'Download gestartet';

  @override
  String get downloadStartedBody =>
      'Es kommt in deine Bibliothek, sobald es fertig ist. Die Benachrichtigung zeigt den Fortschritt.';

  @override
  String get downloadFastBadge => 'Schneller Download';

  @override
  String get downloadNotStartedTitle => 'Download konnte nicht starten';

  @override
  String get updateAvailableTitle => 'Eine neue Version ist da';

  @override
  String get updateReadyTitle => 'Update bereit zur Installation';

  @override
  String get updateChangesTitle => 'Änderungen';

  @override
  String get updateNoNotes => 'Keine Änderungsnotizen für diesen Build.';

  @override
  String get updateDownloading => 'Wird heruntergeladen…';

  @override
  String get updateDownloadFailed =>
      'Das Update konnte nicht heruntergeladen werden.';

  @override
  String get updateDownloadInstall => 'Herunterladen und installieren';

  @override
  String updateDownloadInstallSize(String size) {
    return 'Herunterladen und installieren · $size';
  }

  @override
  String get updateInstallNow => 'Jetzt installieren';

  @override
  String get updateLater => 'Später';

  @override
  String get updateViewOnGithub => 'GitHub';

  @override
  String get updateAction => 'Aktualisieren';

  @override
  String get autoDownloadUpdates => 'Updates automatisch herunterladen';

  @override
  String get autoDownloadUpdatesHint =>
      'Neue Builds werden über WLAN geladen und sind sofort installierbar';

  @override
  String get releaseHistoryTitle => 'Update-Verlauf';

  @override
  String get releaseHistoryHint => 'Jeder auf GitHub veröffentlichte Build';

  @override
  String get releaseHistoryFailed =>
      'Der Update-Verlauf konnte nicht geladen werden.';

  @override
  String get releaseLatest => 'Neueste';

  @override
  String get releaseInstalled => 'Installiert';

  @override
  String get widgetEmptyLibrary =>
      'Bücher aus deiner Bibliothek erscheinen hier';

  @override
  String get widgetNextUp => 'Als Nächstes';

  @override
  String get glossaryTitle => 'Glossar';

  @override
  String get glossaryHint =>
      'Jede Übersetzung schreibt diese Namen und Begriffe so. Tippe zum Ändern.';

  @override
  String get glossaryMaking =>
      'Das Buch wird gelesen, um das Glossar zu erstellen…';

  @override
  String get glossaryEmpty =>
      'Noch kein Glossar. Es entsteht, wenn du dieses Buch übersetzt.';

  @override
  String get glossaryRemake => 'Neu erstellen';

  @override
  String get glossaryKindPerson => 'Person';

  @override
  String get glossaryKindPlace => 'Ort';

  @override
  String get glossaryKindTerm => 'Begriff';

  @override
  String get glossaryGenderMale => 'Männlich';

  @override
  String get glossaryGenderFemale => 'Weiblich';

  @override
  String get glossaryGenderUnknown => 'Unbekannt';

  @override
  String get glossaryKorean => 'Geschrieben als';

  @override
  String get homeRegionJapan => 'Japan';

  @override
  String get homeRegionWestern => 'Englisch';

  @override
  String get japanLightNovels => 'Light Novels';

  @override
  String get japanNewLiterature => 'Webromane in Buchform';

  @override
  String get japanManga => 'Manga';

  @override
  String get storageNotWritable =>
      'In diesem Ordner können keine Bücher gespeichert werden. Wähle den App-Ordner oder einen Ordner in Download oder Documents.';

  @override
  String get priorityTranslate => 'Ganzes Buch übersetzen';

  @override
  String get priorityTranslateHint =>
      'Vor allen anderen Büchern und ohne Pausen, bis es fertig ist – auch bei ausgeschaltetem Bildschirm. Nur wenn das Telefon sehr heiß wird, hält es kurz an.';

  @override
  String get priorityTranslating => 'Dieses Buch wird zuerst übersetzt';

  @override
  String get priorityTranslateDone => 'Übersetzt';

  @override
  String get priorityTranslatePreparing => 'Wird vorbereitet…';

  @override
  String get priorityTranslateNoModel =>
      'Zuerst ein Übersetzungsmodell installieren (Einstellungen > Übersetzung auf dem Gerät)';

  @override
  String priorityTranslateProgress(int done, int total, int percent) {
    return '$done/$total Absätze · $percent %';
  }

  @override
  String translationNoticeBookDone(String title) {
    return '„$title“ ist übersetzt';
  }

  @override
  String get coverHide => 'Cover ausblenden';

  @override
  String get coverShow => 'Cover anzeigen';

  @override
  String get coverHideHint =>
      'Bibliothek, Buchseite und Startbildschirm-Widgets zeigen stattdessen den Titel';

  @override
  String get translationEngine => 'Übersetzungs-Engine';

  @override
  String get translationEngineDevice => 'Auf dem Gerät';

  @override
  String get translationEngineGemini => 'Gemini';

  @override
  String get translationEngineGeminiHint =>
      'Google Gemini übersetzt über das Internet: ein Buch in Minuten, besser als das Modell auf dem Telefon.';

  @override
  String get geminiKey => 'API-Schlüssel';

  @override
  String get geminiKeyHint =>
      'Kostenlos bei Google AI Studio (aistudio.google.com/apikey). Nur auf diesem Gerät gespeichert, nie in Sicherungen.';

  @override
  String geminiKeySaved(String hint) {
    return 'Gespeicherter Schlüssel $hint';
  }

  @override
  String get geminiGetKey => 'Schlüssel holen';

  @override
  String get geminiTest => 'Speichern und testen';

  @override
  String get geminiTestOk => 'Verbunden';

  @override
  String get geminiTestBadKey => 'Der Schlüssel funktioniert nicht';

  @override
  String geminiTestFailed(String error) {
    return 'Keine Verbindung: $error';
  }

  @override
  String get geminiModel => 'Modell';

  @override
  String geminiModelInfo(int rpd, String input, String output) {
    return 'Kostenlos: etwa $rpd Anfragen am Tag · bezahlt \$$input / \$$output pro 1 Mio. Tokens';
  }

  @override
  String get geminiUsageTitle => 'Heutige Nutzung';

  @override
  String geminiUsageResets(String time) {
    return 'Zurückgesetzt um $time (Mitternacht US-Pazifik)';
  }

  @override
  String geminiUsageRequests(int count, int limit) {
    return 'Anfragen $count / $limit';
  }

  @override
  String geminiUsageRequestsEstimate(int count, int limit) {
    return 'Anfragen $count (kostenloses Limit etwa $limit)';
  }

  @override
  String geminiUsageTokens(String input, String output) {
    return 'Tokens rein $input · raus $output';
  }

  @override
  String geminiUsageParagraphs(int count) {
    return 'Übersetzte Absätze $count';
  }

  @override
  String geminiUsageBlocked(int safety, int prohibited) {
    return 'Von Filtern blockiert $safety · laut Richtlinie abgelehnt $prohibited';
  }

  @override
  String geminiUsageOnDevice(int count) {
    return 'Stattdessen auf dem Gerät übersetzt $count';
  }

  @override
  String get geminiTierFree => 'Kostenlose Stufe';

  @override
  String get geminiTierPaid => 'Bezahlte Stufe';

  @override
  String get geminiTierUnknown =>
      'Stufe noch unbekannt (wird beim ersten Limit angezeigt)';

  @override
  String geminiCost(String cost) {
    return 'Zu Bezahlpreisen: $cost';
  }

  @override
  String get geminiExhausted =>
      'Das heutige Kontingent ist aufgebraucht: bis zum Zurücksetzen übersetzt das Gerät.';

  @override
  String get geminiSafety => 'Sicherheitsfilter';

  @override
  String get geminiSafetyHint =>
      'Für Bücher ab 15 oder für Erwachsene ausgeschaltet lassen. Was Google immer sperrt (etwa alles, was Kinder gefährdet), bleibt gesperrt; solche Absätze bleiben im Original.';

  @override
  String get geminiHarmHarassment => 'Belästigung';

  @override
  String get geminiHarmHate => 'Hassrede';

  @override
  String get geminiHarmSexual => 'Sexuelle Inhalte';

  @override
  String get geminiHarmDangerous => 'Gefährliche Inhalte';

  @override
  String get geminiBlockOff => 'Aus';

  @override
  String get geminiBlockOnlyHigh => 'Nur hoch';

  @override
  String get geminiBlockMedium => 'Mittel und höher';

  @override
  String get geminiBlockLow => 'Niedrig und höher';

  @override
  String get geminiDeviceFallback =>
      'Auf dem Gerät weiter, wenn Gemini nicht kann';

  @override
  String get geminiDeviceFallbackHint =>
      'Kontingent aufgebraucht, ein Filter, keine Verbindung: nur diese Absätze, mit dem Modell auf dem Telefon.';

  @override
  String get geminiConcurrency => 'Gleichzeitige Anfragen';

  @override
  String get geminiPrivacyNote =>
      'Der Buchtext wird an Google gesendet. In der kostenlosen Stufe kann Google ihn zur Verbesserung seiner Produkte nutzen, in der bezahlten nicht.';
}
