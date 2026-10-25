// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => 'OpenlibExtended';

  @override
  String get navHome => 'ホーム';

  @override
  String get navSearch => '検索';

  @override
  String get navMyLibrary => 'マイライブラリ';

  @override
  String get navSettings => '設定';

  @override
  String get cancel => 'キャンセル';

  @override
  String get save => '保存';

  @override
  String get add => '追加';

  @override
  String get delete => '削除';

  @override
  String get retry => '再試行';

  @override
  String get advancedSearch => '詳細検索';

  @override
  String get author => '著者';

  @override
  String get publisher => '出版社';

  @override
  String get searchLibraryHint => 'ライブラリを検索(タイトル・著者・出版社・年)';

  @override
  String get newCollection => '新しいコレクション';

  @override
  String get noResultsFound => '見つかりませんでした';

  @override
  String resultsFor(String query) {
    return '「$query」の検索結果';
  }

  @override
  String get followSystem => 'システムに合わせる';

  @override
  String get lightTheme => 'ライトテーマ';

  @override
  String get darkTheme => 'ダークテーマ';

  @override
  String get languageSetting => '言語';

  @override
  String get systemLanguage => 'システムのデフォルト';

  @override
  String get enableNotifications => '通知を有効にする';

  @override
  String get notificationsExplanation =>
      'バックグラウンドでダウンロードの進行状況を表示するには通知の許可が必要です。アプリを閉じていてもダウンロード状況を確認できます。';

  @override
  String get maybeLater => 'あとで';

  @override
  String get enable => '有効にする';

  @override
  String get statusUnread => '未読';

  @override
  String get statusInProgress => '読書中';

  @override
  String get statusCompleted => '読了';

  @override
  String get collectionNameHint => '例:お気に入り、SF';

  @override
  String get manageCollectionsHint => '本を長押しするとコレクションを管理できます';

  @override
  String get results => '結果';

  @override
  String get loading => '読み込み中...';

  @override
  String get unknown => '不明';

  @override
  String get about => 'このアプリについて';

  @override
  String get aboutDescription =>
      'シャドウライブラリ(Anna\'s Archive)から本をダウンロードして読めるオープンソースアプリです。';

  @override
  String get aboutForkNote => 'warreth が個人利用とコミュニティ向けの更新のために管理しているフォーク版です。';

  @override
  String get aboutOriginalNote =>
      'オリジナルのアプリ:dstark5(https://github.com/dstark5/Openlib)。';

  @override
  String get version => 'バージョン';

  @override
  String get github => 'GitHub';

  @override
  String get thisForkByWarreth => 'このフォーク(warreth)';

  @override
  String get reportAnIssue => '問題を報告';

  @override
  String get originalProject => 'オリジナルプロジェクト(dstark5)';

  @override
  String get licence => 'ライセンス';

  @override
  String get gplLicense => 'GPL v3.0 ライセンス';

  @override
  String couldNotLaunch(String url) {
    return '$url を開けませんでした';
  }

  @override
  String get settingsTitle => '設定';

  @override
  String get searchProvidersSection => '検索ソース';

  @override
  String get libraryInstancesSection => 'ライブラリとインスタンス';

  @override
  String get appearanceSection => '外観';

  @override
  String get generalSection => '一般';

  @override
  String get readerSection => 'リーダー';

  @override
  String get advancedSection => '詳細';

  @override
  String get backupSection => 'バックアップ';

  @override
  String get updatesSection => 'アップデート';

  @override
  String get aboutSection => 'このアプリについて';

  @override
  String get archiveInstance => 'Archive インスタンス';

  @override
  String get mirrorsAndProviders => 'ミラーとソース';

  @override
  String get fontSizeTitle => '文字サイズ';

  @override
  String scaleValue(String value) {
    return '倍率:${value}x';
  }

  @override
  String get preview => 'プレビュー';

  @override
  String get storageLocation => '保存先';

  @override
  String get openPdfExternally => 'PDFを外部アプリで開く';

  @override
  String get useDefaultPdfViewer => '既定のPDFビューアを使う';

  @override
  String get openEpubExternally => 'EPUBを外部アプリで開く';

  @override
  String get useDefaultEpubReader => '既定のEPUBリーダーを使う';

  @override
  String get manualDownloadButton => '手動ダウンロードボタン';

  @override
  String get backgroundVerification => 'バックグラウンドで認証を処理';

  @override
  String get backgroundVerificationHint =>
      'DDoS チェックを見えないところで処理します。失敗する端末もあるので、その場合はオフにして画面上で認証してください';

  @override
  String get backgroundVerificationFix =>
      '認証が何度も失敗する場合は、設定の「バックグラウンドで認証を処理」をオフにしてみてください。見えない状態では処理できない端末があります。';

  @override
  String get showManualDownloadHint => 'ダウンロードを手動で始めるボタンを表示';

  @override
  String get donationKeyTitle => 'Anna\'s Archive 寄付キー';

  @override
  String get enterKeyForFasterDownloads => '高速ダウンロード用のキーを入力';

  @override
  String get aboutOpenlib => 'OpenlibExtended について';

  @override
  String get redoOnboarding => '初期設定をやり直す';

  @override
  String get resetAppSetup => 'アプリの設定をリセットして最初から';

  @override
  String get exportLogs => 'ログを書き出す';

  @override
  String get shareDiagnosticLogs => '診断ログを共有(直近5分)';

  @override
  String failedExportLogs(String error) {
    return 'ログを書き出せませんでした:$error';
  }

  @override
  String get donationKeyDialog => '寄付キー';

  @override
  String get enterYourKey => 'キーを入力';

  @override
  String get instanceChanged => 'インスタンスを変更しました';

  @override
  String rankingFailed(String error) {
    return 'ランキングに失敗しました:$error';
  }

  @override
  String get autoRankInstances => 'インスタンスを自動ランキング';

  @override
  String get sortBySpeedOnStartup => '起動時に速度順で自動並べ替え';

  @override
  String get rankInstancesNow => '今すぐランキング';

  @override
  String onLatestVersion(String version) {
    return '最新バージョンです($version)';
  }

  @override
  String failedCheckUpdates(String error) {
    return 'アップデートを確認できませんでした:$error';
  }

  @override
  String get includeBetaUpdates => 'ベータ版のアップデートを含める';

  @override
  String get getPreReleaseVersions => 'プレリリース版を受け取る';

  @override
  String get checkForUpdates => 'アップデートを確認';

  @override
  String get backupSaved => 'バックアップを保存しました';

  @override
  String failedExportBackup(String error) {
    return 'バックアップを書き出せませんでした:$error';
  }

  @override
  String get backupRestored => 'バックアップを復元しました';

  @override
  String failedImportBackup(String error) {
    return 'バックアップを読み込めませんでした:$error';
  }

  @override
  String get atLeastOneSource => '検索ソースが少なくとも1つ必要です';

  @override
  String rankedFastest(String name, String time) {
    return '完了!最速:$name(${time}ms)';
  }

  @override
  String get rankingComplete => 'ランキング完了';

  @override
  String get providerSourceOriginal => '最後に検索 - DDoS-Guard で保護';

  @override
  String get providerLibgenCatalog => '高速な直接ダウンロード - 最初に検索';

  @override
  String get providerZlibMirrors => 'ミラーが変わることがあり、ログインが必要な場合あり';

  @override
  String get themeTitle => 'テーマ';

  @override
  String get saveBackupTitle => 'バックアップを保存';

  @override
  String get pickBackupFile => 'バックアップファイルを選択';

  @override
  String get notABackup => 'OpenlibExtended のバックアップファイルではありません';

  @override
  String get donationKeyHelper => 'Anna\'s Archive で高速ダウンロードに使われます';

  @override
  String get mirrorsTestedRanked => 'ミラーをテストして速度順に並べました';

  @override
  String testingFailed(String error) {
    return 'テストに失敗しました:$error';
  }

  @override
  String get addCustomMirror => 'カスタムミラーを追加';

  @override
  String get nameLabel => '名前';

  @override
  String get nameHint => '例:自分の LibGen ミラー';

  @override
  String get serviceLabel => 'サービス';

  @override
  String get urlLabel => 'URL';

  @override
  String get urlHint => 'https://example.com';

  @override
  String get pleaseFillAllFields => 'すべての項目を入力してください';

  @override
  String get enterValidUrl => 'http:// または https:// で始まる正しいURLを入力してください';

  @override
  String get mirrorAdded => 'ミラーを追加しました';

  @override
  String get deleteMirror => 'ミラーを削除';

  @override
  String deleteMirrorConfirm(String name) {
    return '「$name」を削除しますか?';
  }

  @override
  String get mirrorDeleted => 'ミラーを削除しました';

  @override
  String get cannotDeleteDefaultMirrors => '既定のミラーは削除できません';

  @override
  String get manageMirrors => 'ミラーの管理';

  @override
  String get noMirrorsAvailable => '利用できるミラーがありません';

  @override
  String errorLabel(String error) {
    return 'エラー:$error';
  }

  @override
  String get addMirror => 'ミラーを追加';

  @override
  String get testRankMirrors => 'ミラーの速度をテストして並べ替え';

  @override
  String get unreachable => '接続不可';

  @override
  String get open => '開く';

  @override
  String get unableToOpenFile => 'ファイルを開けません!';

  @override
  String get openInSite => 'サイトで開く';

  @override
  String get bookDeleted => '本を削除しました!';

  @override
  String get deleteBook => '本を削除';

  @override
  String get deletePermanentWarning => '完全に削除され、元に戻せません';

  @override
  String get tryAgain => 'もう一度';

  @override
  String get showBlockedContent => 'ブロックされたページの内容を表示';

  @override
  String get verifyInBrowser => 'ブラウザで認証';

  @override
  String get manualVerificationRequired => '手動での認証が必要です';

  @override
  String get systemBrowser => 'システムブラウザ';

  @override
  String get embeddedBrowser => '内蔵ブラウザ';

  @override
  String get unableToOpenVerification => '認証ページを開けません - URLがありません';

  @override
  String get blockedPageContent => 'ブロックされたページの内容';

  @override
  String get copiedToClipboard => 'クリップボードにコピーしました';

  @override
  String get gotIt => 'OK!';

  @override
  String get copy => 'コピー';

  @override
  String get tryUsingVpn => 'VPN を試してください';

  @override
  String get trending => 'トレンド';

  @override
  String get genres => 'ジャンル';

  @override
  String get copiedBookPath => '本のパスをクリップボードにコピーしました';

  @override
  String get pauseDownload => 'ダウンロードを一時停止';

  @override
  String get resumeDownload => 'ダウンロードを再開';

  @override
  String get cancelDownload => 'ダウンロードをキャンセル';

  @override
  String get copiedBookLink => '本のリンクをクリップボードにコピーしました';

  @override
  String get noMirrors => '利用できるミラーがありません!';

  @override
  String get addToMyLibrary => 'マイライブラリに追加';

  @override
  String get downloadStartedBackground => 'バックグラウンドでダウンロードを開始しました';

  @override
  String get bookDownloaded => '本をダウンロードしました!';

  @override
  String get selectStorageToContinue => '続けるには保存フォルダを選んでください';

  @override
  String get getStarted => 'はじめる';

  @override
  String get next => '次へ';

  @override
  String get welcomeTitle => 'OpenlibExtended へようこそ';

  @override
  String get welcomeSubtitle => '知識の世界へのあなただけの入り口です。まずは設定をしましょう。';

  @override
  String get whereToStoreBooks => '本をどこに保存しますか?';

  @override
  String get noPathSelected => 'パスが選ばれていません';

  @override
  String get selectFolder => 'フォルダを選択';

  @override
  String get storageScanNote => 'このフォルダ内の PDF/EPUB ファイルだけを探します。サブフォルダは検索しません。';

  @override
  String get automaticUpdates => '自動アップデート';

  @override
  String get enableAutoUpdates => '自動アップデートを有効にする';

  @override
  String get autoUpdatesFdroidNote =>
      'F-Droid でインストールした場合はおすすめしません(F-Droid が更新を管理します)。';

  @override
  String get enableBetaUpdatesOnboarding => 'ベータ版のアップデートを有効にする';

  @override
  String get betaUpdatesNote => 'プレリリース版(ベータ)が出たら受け取ります。';

  @override
  String get supportAnnasArchive => 'Anna\'s Archive を支援';

  @override
  String get donationPitch =>
      'Anna\'s Archive に寄付すると高速ダウンロードが使え、みんなのためのサービス運営を支えられます。下に秘密キーを入力できます。';

  @override
  String get annasSecretKey => 'Anna\'s Archive 秘密キー';

  @override
  String get supportThisApp => 'このアプリを支援';

  @override
  String get sponsorPitch => 'このアプリを気に入っていただけたら、開発を支援してください。より良くするための時間を作れます!';

  @override
  String get sponsorOnGithub => 'GitHub でスポンサー';

  @override
  String get stayUpdated => 'お知らせを受け取る';

  @override
  String get notifyOnComplete => 'ダウンロードが終わったら通知します。';

  @override
  String get chooseTheme => 'テーマを選ぶ';

  @override
  String get lightThemeShort => 'ライト';

  @override
  String get darkThemeShort => 'ダーク';

  @override
  String get verifyingAccess => 'アクセスを確認中';

  @override
  String get done => '完了';

  @override
  String get nothingToRead => 'このページには読み上げる内容がありません';

  @override
  String get noVoiceAvailable => '読み上げに使える音声がありません';

  @override
  String get pauseReadingAloud => '読み上げを一時停止';

  @override
  String get resumeReadingAloud => '読み上げ';

  @override
  String get stopReadingAloud => '読み上げを停止';

  @override
  String get speechSpeed => '読み上げ速度';

  @override
  String get decreaseFontSize => '文字を小さく';

  @override
  String get increaseFontSize => '文字を大きく';

  @override
  String get close => '閉じる';

  @override
  String get sortLibrary => 'ライブラリを並べ替え';

  @override
  String get reloadHealthData => '状態を再読み込み';

  @override
  String addServiceMirror(String title) {
    return '$title のミラーを追加';
  }

  @override
  String get deleteMirrorTooltip => 'ミラーを削除';

  @override
  String get ttsEngineMissing =>
      '音声エンジンが見つかりません。システム設定でインストールしてください(例:Speech Services)。';

  @override
  String get previousPage => '前のページ';

  @override
  String get nextPage => '次のページ';

  @override
  String searchingOn(String source) {
    return '$source の検索結果';
  }

  @override
  String get sourceLibgen => 'LibGen';

  @override
  String get sourceZlib => 'Z-Library';

  @override
  String get sourceAnnas => 'Anna\'s Archive';

  @override
  String downloadFrom(String source) {
    return '$source からダウンロード中';
  }

  @override
  String get tryingNextSource => '見つからないため次のソースを検索中…';

  @override
  String get slowMirrorsSkipped => '速いミラーを使用中';

  @override
  String whatsNewTitle(String version) {
    return '$version の新機能';
  }

  @override
  String get whatsNewIntro => 'OpenlibExtended がアップデートされました。変更点をお知らせします。';

  @override
  String get whatsNewTabFeatures => '新機能';

  @override
  String get whatsNewTabSources => 'ソースとミラー';

  @override
  String get whatsNewProvidersHint =>
      'このバージョンで検索ソースとミラーが追加されました。リストを更新すると使えないミラーが外れて新しいミラーが入り、3つの検索ソースがすべて有効になります。';

  @override
  String get whatsNewUpdateInstances => 'ミラーリストを更新';

  @override
  String get whatsNewInstancesUpdated => 'ミラーリストを更新しました';

  @override
  String get whatsNewContinue => '続ける';

  @override
  String get whatsNewFeatureSpeed =>
      'ダウンロードの開始が速くなりました:ミラーの事前確認なしで速いホストから、遅い IPFS ゲートウェイは最後に。';

  @override
  String get whatsNewFeatureSourceLabels => '検索結果とダウンロードに、どのカタログから来たかが表示されます。';

  @override
  String get whatsNewFeatureCovers => 'LibGen の表紙がない場合は本の詳細ページから取得します。';

  @override
  String get zlibRecommendationsTitle => 'こちらもおすすめ';

  @override
  String get zlibRecommendationsLoadMore => 'もっと見る';

  @override
  String get zlibRecommendationsLoadFailed => '本をこれ以上読み込めませんでした';

  @override
  String get searchingSources => '検索中…';

  @override
  String searchingSource(String source) {
    return '$source を検索中…';
  }

  @override
  String tryingNextSourceNamed(String previous, String source) {
    return '$previous で見つからないため $source を検索中…';
  }

  @override
  String get translationTranslate => '翻訳';

  @override
  String get translationShowOriginal => '原文を表示';

  @override
  String get translationNoModel => '翻訳モデルがまだインストールされていません。';

  @override
  String get translationOpenSettings => '設定';

  @override
  String get translationLoadingModel => '翻訳モデルを準備中…(初回は数分かかることがあります)';

  @override
  String translationTranslating(int count, String device) {
    return '翻訳中 · 残り $count 段落 · $device';
  }

  @override
  String translationReady(String device) {
    return '端末で翻訳済み · $device';
  }

  @override
  String get translationPaused => '翻訳を一時停止中';

  @override
  String get translationFailed => '翻訳モデルを実行できませんでした。';

  @override
  String get translationSettingsTitle => '端末内翻訳';

  @override
  String get translationSettingsSubtitle => '端末内のAIモデルでリーダーの本を翻訳';

  @override
  String get translationTargetLanguage => '翻訳先の言語';

  @override
  String get translationModels => 'モデル';

  @override
  String get translationModelsHint =>
      'LiteRT は GPU で動き、だめなら CPU に切り替えます。GGUF ファイルは LiteRT が動かない端末向けです。';

  @override
  String get translationRecommended => 'おすすめ';

  @override
  String get translationDownload => 'ダウンロード';

  @override
  String translationDownloadConfirm(String size) {
    return '$size をダウンロードします。できれば Wi-Fi を使ってください。ファイルはこの端末にだけ保存されます。';
  }

  @override
  String get translationVerifying => 'ファイルを確認中…';

  @override
  String translationDownloadFailed(String error) {
    return 'ダウンロードに失敗しました:$error';
  }

  @override
  String get translationInUse => '使用中';

  @override
  String get translationUse => '使う';

  @override
  String get translationDeleteConfirm => 'このモデルファイルを端末から削除しますか?';

  @override
  String get translationImportModel => 'モデルファイルを読み込む(.litertlm / .gguf)';

  @override
  String get translationNotAModel => '.litertlm か .gguf ファイルを選んでください。';

  @override
  String get translationImported => 'モデルを読み込んで選択しました。';

  @override
  String get translationImportFailed => 'モデルファイルを読み込めませんでした。';

  @override
  String get translationBatteryNote =>
      '読書中は画面に表示されている段落から先に翻訳し、結果は保存されるので読み返すときはすぐに表示されます。アプリがバックグラウンドにあるときは翻訳を止めます。';

  @override
  String get translationClearCache => '保存した翻訳を削除';

  @override
  String get translationCacheCleared => '保存した翻訳を削除しました。';

  @override
  String get importBooks => 'EPUB / PDF を読み込む';

  @override
  String get importBooksFailed => 'ファイル選択を開けませんでした。';

  @override
  String importBooksResult(int imported, int existing, int failed) {
    return '追加 $imported 冊 · 登録済み $existing 冊 · 失敗 $failed 冊';
  }

  @override
  String get translationAutoLibrary => 'ライブラリの本をバックグラウンドで翻訳';

  @override
  String get translationAutoLibraryHint =>
      'オンにしたときだけ動作します。1段落ごとに休みながらゆっくり翻訳し、読書中や端末が熱いとき、バッテリーが少ないときは待機します。アプリを離れても通知とともに続きます。翻訳は各本の隣に保存されます。';

  @override
  String get translationBookDone => '完了';

  @override
  String get readerViewOptions => '表示';

  @override
  String get readerLayoutScroll => 'スクロール';

  @override
  String get readerLayoutPagesLtr => 'ページめくり(左→右)';

  @override
  String get readerLayoutPagesRtl => 'ページめくり(右→左・マンガ式)';

  @override
  String get readerFonts => 'フォント';

  @override
  String get fontsSettingsSubtitle => '韓国語・日本語・ラテン文字のフォント';

  @override
  String get fontsHint =>
      '文字ごとに別のフォントを使います。Google Fonts は最初に一度ダウンロードすれば、あとはオフラインでも使えます。.ttf/.otf ファイルを読み込むこともできます。';

  @override
  String get fontKorean => '韓国語のフォント';

  @override
  String get fontJapanese => '日本語のフォント';

  @override
  String get fontLatin => 'ラテン文字のフォント';

  @override
  String get fontSystem => 'システムのデフォルト';

  @override
  String get fontFile => 'ファイル';

  @override
  String get fontImport => 'フォントファイルを読み込む(.ttf / .otf)';

  @override
  String fontImported(String family) {
    return 'フォントを読み込みました:$family';
  }

  @override
  String get fontImportFailed => 'フォントを読み込めませんでした。';

  @override
  String get readerThemesSettings => 'テーマと設定';

  @override
  String get readerThemeOriginal => 'オリジナル';

  @override
  String get readerThemePaper => 'ペーパー';

  @override
  String get readerThemeCalm => 'カーム';

  @override
  String get readerThemeQuiet => 'クワイエット';

  @override
  String get readerThemeBold => 'ボールド';

  @override
  String get readerThemeNight => 'ナイト';

  @override
  String get readerLayout => '表示方式';

  @override
  String get readerLayoutPagesShort => 'ページ';

  @override
  String get readerLayoutMangaShort => '右綴じ';

  @override
  String get readerFont => 'フォント';

  @override
  String get readerAllFonts => '言語別フォント設定';

  @override
  String get readerCustomize => 'カスタマイズ';

  @override
  String get readerFontSize => '文字サイズ';

  @override
  String get readerLineSpacing => '行間';

  @override
  String get readerLetterSpacing => '字間';

  @override
  String get readerMargins => '余白';

  @override
  String get readerJustify => '両端揃え';

  @override
  String get readerBoldText => '太字テキスト';

  @override
  String get readerReset => 'リセット';

  @override
  String get readerContents => '目次';

  @override
  String get libraryContinueReading => '続きを読む';

  @override
  String get libraryAllBooks => 'すべての本';

  @override
  String libraryBookCount(int count) {
    return '$count冊';
  }

  @override
  String get libraryNoMatches => '条件に合う本がありません';

  @override
  String get libraryEmpty => 'ライブラリは空です';

  @override
  String get libraryEmptyHint => 'お手持ちのEPUB・PDFファイルを読み込んで読み始めましょう。';

  @override
  String get bookGenre => 'ジャンル';

  @override
  String get bookCollections => 'コレクション';

  @override
  String get genreAll => 'すべて';

  @override
  String get genreNone => '未設定';

  @override
  String get genreLightNovel => 'ライトノベル';

  @override
  String get genreComic => 'コミック';

  @override
  String get genreNovel => '小説';

  @override
  String get genreEnglishNovel => '英語小説';

  @override
  String get genreEssay => 'エッセイ';

  @override
  String get genreScience => '科学';

  @override
  String get genreHumanities => '人文';

  @override
  String get genreBusiness => 'ビジネス';

  @override
  String get genrePaper => '論文';

  @override
  String get genreTextbook => '学習・教材';

  @override
  String get genreOther => 'その他';

  @override
  String get translationLightNovelStyle => 'ライトノベル文体';

  @override
  String get translationLightNovelStyleHint =>
      'タメ口・敬語、キャラ固有の口調、呼称、擬音を活かします。ノンフィクションではオフにしてください。文体ごとに翻訳は別に保存されます。';

  @override
  String get libraryBookOptions => '本の設定';

  @override
  String get libraryRecentlyAdded => '最近追加';

  @override
  String get libraryReadingNow => '読書中';

  @override
  String libraryFinishedCount(int count) {
    return '$count冊読了';
  }

  @override
  String get recentSearches => '最近の検索';

  @override
  String get clearAll => 'すべて削除';

  @override
  String get removeFromHistory => '履歴から削除';

  @override
  String get searchHistoryFill => '検索語を編集';

  @override
  String get showMore => 'もっと見る';

  @override
  String get showLess => '閉じる';

  @override
  String get searchHistorySection => '検索履歴';

  @override
  String get saveSearchHistory => '検索履歴を保存';

  @override
  String get saveSearchHistoryHint => '検索タブに最近の検索を表示します';

  @override
  String get clearSearchHistory => '検索履歴を消去';

  @override
  String savedSearchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '保存された検索 $count件',
      zero: '保存された検索はありません',
    );
    return '$_temp0';
  }

  @override
  String get searchHistoryCleared => '検索履歴を消去しました';

  @override
  String get themeSystemShort => 'システム';

  @override
  String get themeLightShort => 'ライト';

  @override
  String get themeDarkShort => 'ダーク';

  @override
  String get recapTitle => '読書記録';

  @override
  String get recapCheckpoints => '読了チェックポイント';

  @override
  String get recapBooksUnit => '冊';

  @override
  String get recapDaysUnit => '日';

  @override
  String get recapAllCheckpoints => 'すべてのチェックポイントを達成！';

  @override
  String recapToNextCheckpoint(int remaining, int next) {
    return '$next冊まであと$remaining冊';
  }

  @override
  String get recapStreak => '連続読書';

  @override
  String get recapStreakStart => '今日読んで始めよう';

  @override
  String recapLongestStreak(int days) {
    return '最長 $days日';
  }

  @override
  String get recapLastFourWeeks => '直近4週間';

  @override
  String recapReadingDays(int days) {
    return '読書日 $days日';
  }

  @override
  String recapMonthTitle(String monthName) {
    return '$monthNameのまとめ';
  }

  @override
  String get recapFinishedThisMonth => '今月の読了';

  @override
  String get recapGenreMix => 'ジャンル構成';

  @override
  String get translationPromptFormat => 'プロンプト形式';

  @override
  String get translationPromptFormatHint =>
      'このモデルへの依頼の書き方です。翻訳専用モデルは学習時と同じ形式で最も良く動きます。自動はモデルに合わせて選びます。';

  @override
  String promptFormatAuto(String format) {
    return '自動（$format）';
  }

  @override
  String get promptFormatGeneral => '汎用（Gemma など）';

  @override
  String get promptFormatHyMt => 'Hy-MT 翻訳モデル';

  @override
  String get promptFormatJaKo => '日→韓 台詞翻訳モデル';

  @override
  String get promptFormatKoreanOnly => 'この形式は韓国語にのみ翻訳します。他の言語には汎用形式を使います。';

  @override
  String translationSomeFailed(int count) {
    return '翻訳できなかった段落 $count件';
  }

  @override
  String get translationReadyPlain => '端末で翻訳済み';

  @override
  String translationNeedsRam(int gb) {
    return 'RAM ${gb}GB以上';
  }

  @override
  String get translationFaster => '高速';

  @override
  String get translationChargingOnly => '充電中のみ';

  @override
  String get translationChargingOnlyHint => '充電器がつながるまで待ち、バッテリーを使いません。';

  @override
  String get translationDevice => '演算装置';

  @override
  String get translationDeviceAuto => 'GPU優先(速い)';

  @override
  String get translationDeviceCpu => 'CPU(GPUは画面用に空ける)';

  @override
  String get translationDeviceHint =>
      '翻訳中に画面がカクつくならCPUを試してください。遅くなりますが、GPUを画面描画に残します。';

  @override
  String get translationNoticeChannel => 'バックグラウンド翻訳';

  @override
  String get translationNoticeTitle => 'ライブラリの本を翻訳中';

  @override
  String translationNoticeProgress(String title, int percent) {
    return '$title · $percent%';
  }

  @override
  String translationNoticeCount(int done, int total, int book, int books) {
    return '$done/$total 段落 · $books冊中$book冊目';
  }

  @override
  String get translationNoticeStop => '停止';

  @override
  String get translationNoticeDone => 'ライブラリの翻訳が完了';

  @override
  String translationNoticeDoneCount(int count) {
    return '翻訳済みの本 $count冊';
  }

  @override
  String get translationWaitReading => '読書中のため待機中';

  @override
  String get translationWaitAppClosed => 'アプリを開くと再開';

  @override
  String get translationWaitWarm => '端末が熱いため休憩中';

  @override
  String get translationWaitBattery => 'バッテリー残量不足、充電で再開';

  @override
  String get translationWaitPowerSave => '省電力モードのため一時停止';

  @override
  String get translationWaitCharger => '充電器の接続待ち';

  @override
  String get readerWriting => '組み方向';

  @override
  String get readerWritingAuto => '本の設定';

  @override
  String get readerWritingHorizontal => '横書き';

  @override
  String get readerWritingVertical => '縦書き';

  @override
  String get readerLoadFailed => 'この本を表示できませんでした。';

  @override
  String get readerOpenSimple => 'シンプルリーダーで開く';

  @override
  String get ok => 'OK';

  @override
  String get downloadPreparing => '準備中…';

  @override
  String get downloadStartedTitle => 'ダウンロードを開始しました';

  @override
  String get downloadStartedBody => '完了するとライブラリに追加されます。進行状況は通知で確認できます。';

  @override
  String get downloadFastBadge => '高速ダウンロード';

  @override
  String get downloadNotStartedTitle => 'ダウンロードを開始できませんでした';

  @override
  String get updateAvailableTitle => '新しいバージョンがあります';

  @override
  String get updateReadyTitle => 'アップデートの準備ができました';

  @override
  String get updateChangesTitle => '変更点';

  @override
  String get updateNoNotes => 'このビルドの変更点はありません。';

  @override
  String get updateDownloading => 'ダウンロード中…';

  @override
  String get updateDownloadFailed => 'アップデートをダウンロードできませんでした。';

  @override
  String get updateDownloadInstall => 'ダウンロードしてインストール';

  @override
  String updateDownloadInstallSize(String size) {
    return 'ダウンロードしてインストール · $size';
  }

  @override
  String get updateInstallNow => '今すぐインストール';

  @override
  String get updateLater => 'あとで';

  @override
  String get updateViewOnGithub => 'GitHub';

  @override
  String get updateAction => 'アップデート';

  @override
  String get autoDownloadUpdates => 'アップデートを自動でダウンロード';

  @override
  String get autoDownloadUpdatesHint => 'Wi-Fi で新しいビルドを先に取得し、すぐインストールできます';

  @override
  String get releaseHistoryTitle => 'アップデート履歴';

  @override
  String get releaseHistoryHint => 'GitHub で公開されたすべてのビルド';

  @override
  String get releaseHistoryFailed => 'アップデート履歴を読み込めませんでした。';

  @override
  String get releaseLatest => '最新';

  @override
  String get releaseInstalled => '使用中';

  @override
  String get widgetEmptyLibrary => 'ライブラリに追加した本がここに表示されます';

  @override
  String get widgetNextUp => '次の本';

  @override
  String get glossaryTitle => '用語集';

  @override
  String get glossaryHint => '翻訳はいつもこの表記を使います。タップして修正できます。';

  @override
  String get glossaryMaking => '本を読んで用語集を作成中…';

  @override
  String get glossaryEmpty => 'まだ用語集がありません。この本を翻訳すると作成されます。';

  @override
  String get glossaryRemake => '作り直す';

  @override
  String get glossaryKindPerson => '人物';

  @override
  String get glossaryKindPlace => '場所';

  @override
  String get glossaryKindTerm => '用語';

  @override
  String get glossaryGenderMale => '男';

  @override
  String get glossaryGenderFemale => '女';

  @override
  String get glossaryGenderUnknown => '不明';

  @override
  String get glossaryKorean => '翻訳での表記';

  @override
  String get homeRegionJapan => '日本';

  @override
  String get homeRegionWestern => '英語圏';

  @override
  String get japanLightNovels => 'ライトノベル';

  @override
  String get japanNewLiterature => '新文芸';

  @override
  String get japanManga => 'マンガ';
}
