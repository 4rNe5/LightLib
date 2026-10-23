// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get appTitle => 'OpenlibExtended';

  @override
  String get navHome => '홈';

  @override
  String get navSearch => '검색';

  @override
  String get navMyLibrary => '내 서재';

  @override
  String get navSettings => '설정';

  @override
  String get cancel => '취소';

  @override
  String get save => '저장';

  @override
  String get add => '추가';

  @override
  String get delete => '삭제';

  @override
  String get retry => '다시 시도';

  @override
  String get advancedSearch => '상세 검색';

  @override
  String get author => '저자';

  @override
  String get publisher => '출판사';

  @override
  String get searchLibraryHint => '서재 검색 (제목, 저자, 출판사, 연도)';

  @override
  String get newCollection => '새 컬렉션';

  @override
  String get noResultsFound => '검색 결과가 없습니다';

  @override
  String resultsFor(String query) {
    return '\'$query\' 검색 결과';
  }

  @override
  String get followSystem => '시스템 설정 따르기';

  @override
  String get lightTheme => '라이트 테마';

  @override
  String get darkTheme => '다크 테마';

  @override
  String get languageSetting => '언어';

  @override
  String get systemLanguage => '시스템 기본값';

  @override
  String get enableNotifications => '알림 켜기';

  @override
  String get notificationsExplanation =>
      '백그라운드에서 다운로드 진행 상황을 보여 주려면 알림 권한이 필요합니다. 앱을 내려 두어도 책 다운로드 상황을 확인할 수 있습니다.';

  @override
  String get maybeLater => '나중에';

  @override
  String get enable => '켜기';

  @override
  String get statusUnread => '안 읽음';

  @override
  String get statusInProgress => '읽는 중';

  @override
  String get statusCompleted => '다 읽음';

  @override
  String get collectionNameHint => '예: 즐겨찾기, SF';

  @override
  String get manageCollectionsHint => '책을 길게 누르면 컬렉션을 관리할 수 있습니다';

  @override
  String get results => '결과';

  @override
  String get loading => '불러오는 중...';

  @override
  String get unknown => '알 수 없음';

  @override
  String get about => '정보';

  @override
  String get aboutDescription =>
      '섀도 라이브러리(Anna\'s Archive)에서 책을 내려받아 읽는 오픈 소스 앱입니다.';

  @override
  String get aboutForkNote => 'warreth가 개인 용도와 커뮤니티 업데이트를 위해 관리하는 포크 버전입니다.';

  @override
  String get aboutOriginalNote =>
      '원작 앱: dstark5 (https://github.com/dstark5/Openlib).';

  @override
  String get version => '버전';

  @override
  String get github => 'GitHub';

  @override
  String get thisForkByWarreth => '이 포크 (warreth)';

  @override
  String get reportAnIssue => '문제 신고';

  @override
  String get originalProject => '원본 프로젝트 (dstark5)';

  @override
  String get licence => '라이선스';

  @override
  String get gplLicense => 'GPL v3.0 라이선스';

  @override
  String couldNotLaunch(String url) {
    return '$url을(를) 열 수 없습니다';
  }

  @override
  String get settingsTitle => '설정';

  @override
  String get searchProvidersSection => '검색 소스';

  @override
  String get libraryInstancesSection => '라이브러리 및 인스턴스';

  @override
  String get appearanceSection => '화면';

  @override
  String get generalSection => '일반';

  @override
  String get readerSection => '리더';

  @override
  String get advancedSection => '고급';

  @override
  String get backupSection => '백업';

  @override
  String get updatesSection => '업데이트';

  @override
  String get aboutSection => '정보';

  @override
  String get archiveInstance => 'Archive 인스턴스';

  @override
  String get mirrorsAndProviders => '미러 및 소스';

  @override
  String get fontSizeTitle => '글자 크기';

  @override
  String scaleValue(String value) {
    return '배율: ${value}x';
  }

  @override
  String get preview => '미리보기';

  @override
  String get storageLocation => '저장 위치';

  @override
  String get openPdfExternally => 'PDF를 외부 앱으로 열기';

  @override
  String get useDefaultPdfViewer => '기본 PDF 뷰어 사용';

  @override
  String get openEpubExternally => 'EPUB을 외부 앱으로 열기';

  @override
  String get useDefaultEpubReader => '기본 EPUB 리더 사용';

  @override
  String get manualDownloadButton => '수동 다운로드 버튼';

  @override
  String get backgroundVerification => '백그라운드에서 확인 처리';

  @override
  String get backgroundVerificationHint =>
      'DDoS 확인을 보이지 않게 처리합니다. 일부 기기에서는 실패하니, 그럴 때는 끄고 창에서 직접 확인하세요';

  @override
  String get backgroundVerificationFix =>
      '확인이 계속 실패하면 설정에서 \"백그라운드에서 확인 처리\"를 꺼 보세요. 일부 기기는 보이지 않는 상태로 확인을 처리하지 못합니다.';

  @override
  String get showManualDownloadHint => '다운로드를 직접 시작하는 버튼 표시';

  @override
  String get donationKeyTitle => 'Anna\'s Archive 후원 키';

  @override
  String get enterKeyForFasterDownloads => '더 빠른 다운로드를 위해 키 입력';

  @override
  String get aboutOpenlib => 'OpenlibExtended 정보';

  @override
  String get redoOnboarding => '초기 설정 다시 하기';

  @override
  String get resetAppSetup => '앱 설정을 초기화하고 처음부터 시작';

  @override
  String get exportLogs => '로그 내보내기';

  @override
  String get shareDiagnosticLogs => '진단 로그 공유 (최근 5분)';

  @override
  String failedExportLogs(String error) {
    return '로그를 내보내지 못했습니다: $error';
  }

  @override
  String get donationKeyDialog => '후원 키';

  @override
  String get enterYourKey => '키를 입력하세요';

  @override
  String get instanceChanged => '인스턴스를 변경했습니다';

  @override
  String rankingFailed(String error) {
    return '순위 매기기 실패: $error';
  }

  @override
  String get autoRankInstances => '인스턴스 자동 순위';

  @override
  String get sortBySpeedOnStartup => '시작할 때 속도순으로 자동 정렬';

  @override
  String get rankInstancesNow => '지금 순위 매기기';

  @override
  String onLatestVersion(String version) {
    return '최신 버전입니다 ($version)';
  }

  @override
  String failedCheckUpdates(String error) {
    return '업데이트를 확인하지 못했습니다: $error';
  }

  @override
  String get includeBetaUpdates => '베타 업데이트 포함';

  @override
  String get getPreReleaseVersions => '정식 출시 전 버전 받기';

  @override
  String get checkForUpdates => '업데이트 확인';

  @override
  String get backupSaved => '백업을 저장했습니다';

  @override
  String failedExportBackup(String error) {
    return '백업을 내보내지 못했습니다: $error';
  }

  @override
  String get backupRestored => '백업을 복원했습니다';

  @override
  String failedImportBackup(String error) {
    return '백업을 가져오지 못했습니다: $error';
  }

  @override
  String get atLeastOneSource => '검색 소스가 하나 이상 필요합니다';

  @override
  String rankedFastest(String name, String time) {
    return '순위 완료! 가장 빠름: $name (${time}ms)';
  }

  @override
  String get rankingComplete => '순위 매기기 완료';

  @override
  String get providerSourceOriginal => '마지막에 검색 - DDoS-Guard로 보호됨';

  @override
  String get providerLibgenCatalog => '빠른 직접 다운로드 - 가장 먼저 검색';

  @override
  String get providerZlibMirrors => '미러가 바뀔 수 있고 로그인이 필요할 수 있음';

  @override
  String get themeTitle => '테마';

  @override
  String get saveBackupTitle => '백업 저장';

  @override
  String get pickBackupFile => '백업 파일 선택';

  @override
  String get notABackup => 'OpenlibExtended 백업 파일이 아닙니다';

  @override
  String get donationKeyHelper => 'Anna\'s Archive에서 더 빠르게 내려받는 데 쓰입니다';

  @override
  String get mirrorsTestedRanked => '미러를 테스트하고 속도순으로 정렬했습니다';

  @override
  String testingFailed(String error) {
    return '테스트 실패: $error';
  }

  @override
  String get addCustomMirror => '사용자 미러 추가';

  @override
  String get nameLabel => '이름';

  @override
  String get nameHint => '예: 내 LibGen 미러';

  @override
  String get serviceLabel => '서비스';

  @override
  String get urlLabel => 'URL';

  @override
  String get urlHint => 'https://example.com';

  @override
  String get pleaseFillAllFields => '모든 항목을 입력하세요';

  @override
  String get enterValidUrl => 'http:// 또는 https://로 시작하는 올바른 URL을 입력하세요';

  @override
  String get mirrorAdded => '미러를 추가했습니다';

  @override
  String get deleteMirror => '미러 삭제';

  @override
  String deleteMirrorConfirm(String name) {
    return '\"$name\"을(를) 삭제할까요?';
  }

  @override
  String get mirrorDeleted => '미러를 삭제했습니다';

  @override
  String get cannotDeleteDefaultMirrors => '기본 미러는 삭제할 수 없습니다';

  @override
  String get manageMirrors => '미러 관리';

  @override
  String get noMirrorsAvailable => '사용 가능한 미러가 없습니다';

  @override
  String errorLabel(String error) {
    return '오류: $error';
  }

  @override
  String get addMirror => '미러 추가';

  @override
  String get testRankMirrors => '미러 속도 테스트 및 정렬';

  @override
  String get unreachable => '연결 불가';

  @override
  String get open => '열기';

  @override
  String get unableToOpenFile => '파일을 열 수 없습니다!';

  @override
  String get openInSite => '사이트에서 열기';

  @override
  String get bookDeleted => '책을 삭제했습니다!';

  @override
  String get deleteBook => '책 삭제';

  @override
  String get deletePermanentWarning => '영구적으로 삭제되며 되돌릴 수 없습니다';

  @override
  String get tryAgain => '다시 시도';

  @override
  String get showBlockedContent => '차단된 페이지 내용 보기';

  @override
  String get verifyInBrowser => '브라우저에서 확인';

  @override
  String get manualVerificationRequired => '직접 확인이 필요합니다';

  @override
  String get systemBrowser => '시스템 브라우저';

  @override
  String get embeddedBrowser => '내장 브라우저';

  @override
  String get unableToOpenVerification => '확인 페이지를 열 수 없습니다 - URL이 없습니다';

  @override
  String get blockedPageContent => '차단된 페이지 내용';

  @override
  String get copiedToClipboard => '클립보드에 복사했습니다';

  @override
  String get gotIt => '알겠어요!';

  @override
  String get copy => '복사';

  @override
  String get tryUsingVpn => 'VPN을 사용해 보세요';

  @override
  String get trending => '인기';

  @override
  String get genres => '장르';

  @override
  String get copiedBookPath => '책 경로를 클립보드에 복사했습니다';

  @override
  String get pauseDownload => '다운로드 일시정지';

  @override
  String get resumeDownload => '다운로드 재개';

  @override
  String get cancelDownload => '다운로드 취소';

  @override
  String get copiedBookLink => '책 링크를 클립보드에 복사했습니다';

  @override
  String get noMirrors => '사용 가능한 미러가 없습니다!';

  @override
  String get addToMyLibrary => '내 서재에 추가';

  @override
  String get downloadStartedBackground => '백그라운드에서 다운로드를 시작했습니다';

  @override
  String get bookDownloaded => '책을 내려받았습니다!';

  @override
  String get selectStorageToContinue => '계속하려면 저장 폴더를 선택하세요';

  @override
  String get getStarted => '시작하기';

  @override
  String get next => '다음';

  @override
  String get welcomeTitle => 'OpenlibExtended에 오신 것을 환영합니다';

  @override
  String get welcomeSubtitle => '지식의 세계로 가는 나만의 입구입니다. 먼저 설정을 해 볼게요.';

  @override
  String get whereToStoreBooks => '책을 어디에 저장할까요?';

  @override
  String get noPathSelected => '선택한 경로가 없습니다';

  @override
  String get selectFolder => '폴더 선택';

  @override
  String get storageScanNote => '이 폴더에서 PDF/EPUB 파일만 찾습니다. 하위 폴더는 검색하지 않습니다.';

  @override
  String get automaticUpdates => '자동 업데이트';

  @override
  String get enableAutoUpdates => '자동 업데이트 켜기';

  @override
  String get autoUpdatesFdroidNote =>
      'F-Droid로 설치했다면 권장하지 않습니다 (F-Droid가 업데이트를 관리합니다).';

  @override
  String get enableBetaUpdatesOnboarding => '베타 업데이트 켜기';

  @override
  String get betaUpdatesNote => '정식 출시 전 버전(베타)이 나오면 받습니다.';

  @override
  String get supportAnnasArchive => 'Anna\'s Archive 후원';

  @override
  String get donationPitch =>
      'Anna\'s Archive에 후원하면 더 빠르게 내려받을 수 있고, 모두를 위한 서비스 운영에 도움이 됩니다. 아래에 비밀 키를 입력할 수 있습니다.';

  @override
  String get annasSecretKey => 'Anna\'s Archive 비밀 키';

  @override
  String get supportThisApp => '이 앱 후원하기';

  @override
  String get sponsorPitch =>
      '앱이 마음에 드셨다면 개발을 후원해 주세요. 앱을 더 낫게 만드는 데 시간을 쓸 수 있게 됩니다!';

  @override
  String get sponsorOnGithub => 'GitHub에서 후원';

  @override
  String get stayUpdated => '소식 받기';

  @override
  String get notifyOnComplete => '다운로드가 끝나면 알림을 받습니다.';

  @override
  String get chooseTheme => '테마 선택';

  @override
  String get lightThemeShort => '라이트';

  @override
  String get darkThemeShort => '다크';

  @override
  String get verifyingAccess => '접근 확인 중';

  @override
  String get done => '완료';

  @override
  String get nothingToRead => '이 페이지에는 읽을 내용이 없습니다';

  @override
  String get noVoiceAvailable => '소리 내어 읽기에 쓸 음성이 없습니다';

  @override
  String get pauseReadingAloud => '읽어 주기 일시정지';

  @override
  String get resumeReadingAloud => '소리 내어 읽기';

  @override
  String get stopReadingAloud => '읽어 주기 중지';

  @override
  String get speechSpeed => '읽기 속도';

  @override
  String get decreaseFontSize => '글자 작게';

  @override
  String get increaseFontSize => '글자 크게';

  @override
  String get close => '닫기';

  @override
  String get sortLibrary => '서재 정렬';

  @override
  String get reloadHealthData => '상태 정보 새로고침';

  @override
  String addServiceMirror(String title) {
    return '$title 미러 추가';
  }

  @override
  String get deleteMirrorTooltip => '미러 삭제';

  @override
  String get ttsEngineMissing =>
      '음성 엔진이 없습니다. 시스템 설정에서 설치해 주세요 (예: Speech Services).';

  @override
  String get previousPage => '이전 페이지';

  @override
  String get nextPage => '다음 페이지';

  @override
  String searchingOn(String source) {
    return '$source 검색 결과';
  }

  @override
  String get sourceLibgen => 'LibGen';

  @override
  String get sourceZlib => 'Z-Library';

  @override
  String get sourceAnnas => 'Anna\'s Archive';

  @override
  String downloadFrom(String source) {
    return '$source에서 내려받는 중';
  }

  @override
  String get tryingNextSource => '결과가 없어 다음 소스를 찾는 중…';

  @override
  String get slowMirrorsSkipped => '더 빠른 미러 사용 중';

  @override
  String whatsNewTitle(String version) {
    return '$version의 새로운 점';
  }

  @override
  String get whatsNewIntro => 'OpenlibExtended가 업데이트되었습니다. 바뀐 점을 알려 드릴게요.';

  @override
  String get whatsNewTabFeatures => '새 기능';

  @override
  String get whatsNewTabSources => '소스 및 미러';

  @override
  String get whatsNewProvidersHint =>
      '이번 버전에서 검색 소스와 미러가 추가되었습니다. 목록을 업데이트하면 죽은 미러는 빠지고 새 미러가 들어가며, 세 가지 검색 소스가 모두 켜집니다.';

  @override
  String get whatsNewUpdateInstances => '미러 목록 업데이트';

  @override
  String get whatsNewInstancesUpdated => '미러 목록을 업데이트했습니다';

  @override
  String get whatsNewContinue => '계속';

  @override
  String get whatsNewFeatureSpeed =>
      '다운로드가 더 빨리 시작됩니다: 미러 탐색 없이 빠른 호스트부터, 느린 IPFS 게이트웨이는 마지막에.';

  @override
  String get whatsNewFeatureSourceLabels =>
      '모든 검색 결과와 다운로드에 어느 카탈로그에서 왔는지 표시됩니다.';

  @override
  String get whatsNewFeatureCovers => 'LibGen 표지가 없으면 책 상세 페이지에서 가져옵니다.';

  @override
  String get zlibRecommendationsTitle => '이런 책은 어떠세요';

  @override
  String get zlibRecommendationsLoadMore => '더 보기';

  @override
  String get zlibRecommendationsLoadFailed => '책을 더 불러오지 못했습니다';

  @override
  String get searchingSources => '검색 중…';

  @override
  String searchingSource(String source) {
    return '$source 검색 중…';
  }

  @override
  String tryingNextSourceNamed(String previous, String source) {
    return '$previous에 결과가 없어 $source 검색 중…';
  }

  @override
  String get translationTranslate => '번역';

  @override
  String get translationShowOriginal => '원문 보기';

  @override
  String get translationNoModel => '아직 번역 모델이 설치되지 않았습니다.';

  @override
  String get translationOpenSettings => '설정';

  @override
  String get translationLoadingModel => '번역 모델 준비 중… (처음 한 번은 몇 분 걸릴 수 있어요)';

  @override
  String translationTranslating(int count, String device) {
    return '번역 중 · 남은 문단 $count · $device';
  }

  @override
  String translationReady(String device) {
    return '기기에서 번역됨 · $device';
  }

  @override
  String get translationPaused => '번역 일시정지';

  @override
  String get translationFailed => '번역 모델을 실행하지 못했습니다.';

  @override
  String get translationSettingsTitle => '기기 내 번역';

  @override
  String get translationSettingsSubtitle => '기기 안의 AI 모델로 리더에서 책을 번역';

  @override
  String get translationTargetLanguage => '번역할 언어';

  @override
  String get translationModels => '모델';

  @override
  String get translationModelsHint =>
      'LiteRT는 GPU에서 실행되고 안 되면 CPU로 전환합니다. GGUF 파일은 LiteRT가 동작하지 않는 기기용입니다.';

  @override
  String get translationRecommended => '권장';

  @override
  String get translationDownload => '다운로드';

  @override
  String translationDownloadConfirm(String size) {
    return '$size를 내려받습니다. 가능하면 Wi-Fi를 쓰세요. 파일은 이 기기에만 저장됩니다.';
  }

  @override
  String get translationVerifying => '파일 확인 중…';

  @override
  String translationDownloadFailed(String error) {
    return '다운로드 실패: $error';
  }

  @override
  String get translationInUse => '사용 중';

  @override
  String get translationUse => '사용';

  @override
  String get translationDeleteConfirm => '이 모델 파일을 기기에서 삭제할까요?';

  @override
  String get translationImportModel => '모델 파일 가져오기 (.litertlm / .gguf)';

  @override
  String get translationNotAModel => '.litertlm 또는 .gguf 파일을 선택하세요.';

  @override
  String get translationImported => '모델을 가져와서 선택했습니다.';

  @override
  String get translationImportFailed => '모델 파일을 가져오지 못했습니다.';

  @override
  String get translationBatteryNote =>
      '읽는 중에는 화면에 보이는 문단부터 먼저 번역하고, 결과는 저장되어 다시 읽을 때는 바로 표시됩니다. 앱이 백그라운드에 있으면 번역을 멈춥니다.';

  @override
  String get translationClearCache => '저장된 번역 삭제';

  @override
  String get translationCacheCleared => '저장된 번역을 삭제했습니다.';

  @override
  String get importBooks => 'EPUB / PDF 가져오기';

  @override
  String get importBooksFailed => '파일 선택기를 열 수 없습니다.';

  @override
  String importBooksResult(int imported, int existing, int failed) {
    return '추가 $imported권 · 이미 있음 $existing권 · 실패 $failed권';
  }

  @override
  String get translationAutoLibrary => '서재의 책을 백그라운드에서 번역';

  @override
  String get translationAutoLibraryHint =>
      '켜야만 동작합니다. 문단마다 쉬어 가며 천천히 번역하고, 책을 읽는 중이거나 기기가 뜨겁거나 배터리가 부족하면 기다립니다. 앱을 나가도 알림과 함께 계속됩니다. 번역은 각 책 옆에 저장됩니다.';

  @override
  String get translationBookDone => '완료';

  @override
  String get readerViewOptions => '보기';

  @override
  String get readerLayoutScroll => '스크롤';

  @override
  String get readerLayoutPagesLtr => '페이지 넘기기 (왼쪽→오른쪽)';

  @override
  String get readerLayoutPagesRtl => '페이지 넘기기 (오른쪽→왼쪽, 만화식)';

  @override
  String get readerFonts => '글꼴';

  @override
  String get fontsSettingsSubtitle => '한국어·일본어·라틴 문자 글꼴';

  @override
  String get fontsHint =>
      '문자마다 다른 글꼴을 씁니다. Google Fonts는 처음 쓸 때 한 번 내려받고, 그 뒤로는 오프라인에서도 쓸 수 있습니다. .ttf/.otf 파일을 직접 가져올 수도 있습니다.';

  @override
  String get fontKorean => '한국어 글꼴';

  @override
  String get fontJapanese => '일본어 글꼴';

  @override
  String get fontLatin => '라틴 문자 글꼴';

  @override
  String get fontSystem => '시스템 기본';

  @override
  String get fontFile => '파일';

  @override
  String get fontImport => '글꼴 파일 가져오기 (.ttf / .otf)';

  @override
  String fontImported(String family) {
    return '글꼴을 가져왔습니다: $family';
  }

  @override
  String get fontImportFailed => '글꼴을 가져오지 못했습니다.';

  @override
  String get readerThemesSettings => '테마 및 설정';

  @override
  String get readerThemeOriginal => '기본';

  @override
  String get readerThemePaper => '종이';

  @override
  String get readerThemeCalm => '차분함';

  @override
  String get readerThemeQuiet => '고요함';

  @override
  String get readerThemeBold => '굵게';

  @override
  String get readerThemeNight => '야간';

  @override
  String get readerLayout => '보기 방식';

  @override
  String get readerLayoutPagesShort => '페이지';

  @override
  String get readerLayoutMangaShort => '만화식';

  @override
  String get readerFont => '글꼴';

  @override
  String get readerAllFonts => '언어별 글꼴 설정';

  @override
  String get readerCustomize => '사용자화';

  @override
  String get readerFontSize => '글자 크기';

  @override
  String get readerLineSpacing => '줄 간격';

  @override
  String get readerLetterSpacing => '자간';

  @override
  String get readerMargins => '여백';

  @override
  String get readerJustify => '양쪽 정렬';

  @override
  String get readerBoldText => '굵은 텍스트';

  @override
  String get readerReset => '초기화';

  @override
  String get readerContents => '목차';

  @override
  String get libraryContinueReading => '이어 읽기';

  @override
  String get libraryAllBooks => '모든 책';

  @override
  String libraryBookCount(int count) {
    return '$count권';
  }

  @override
  String get libraryNoMatches => '조건에 맞는 책이 없습니다';

  @override
  String get libraryEmpty => '서재가 비어 있습니다';

  @override
  String get libraryEmptyHint => '가지고 있는 EPUB·PDF 파일을 가져와 읽기 시작하세요.';

  @override
  String get bookGenre => '장르';

  @override
  String get bookCollections => '컬렉션';

  @override
  String get genreAll => '전체';

  @override
  String get genreNone => '미지정';

  @override
  String get genreLightNovel => '라이트노벨';

  @override
  String get genreComic => '코믹스';

  @override
  String get genreNovel => '소설';

  @override
  String get genreEnglishNovel => '영문 소설';

  @override
  String get genreEssay => '에세이';

  @override
  String get genreScience => '과학';

  @override
  String get genreHumanities => '인문';

  @override
  String get genreBusiness => '경제·경영';

  @override
  String get genrePaper => '논문';

  @override
  String get genreTextbook => '학습·교재';

  @override
  String get genreOther => '기타';

  @override
  String get translationLightNovelStyle => '라이트노벨 문체';

  @override
  String get translationLightNovelStyleHint =>
      '반말·존댓말, 캐릭터 고유 말투, 호칭, 의성어를 살리고 지문은 \'-다\'체로 씁니다. 비문학 책은 끄세요. 문체별 번역은 따로 저장됩니다.';

  @override
  String get libraryBookOptions => '책 설정';

  @override
  String get libraryRecentlyAdded => '최근 추가';

  @override
  String get libraryReadingNow => '읽는 중';

  @override
  String libraryFinishedCount(int count) {
    return '$count권 완독';
  }

  @override
  String get recentSearches => '최근 검색';

  @override
  String get clearAll => '전체 삭제';

  @override
  String get removeFromHistory => '기록에서 삭제';

  @override
  String get searchHistoryFill => '검색어 수정';

  @override
  String get showMore => '더 보기';

  @override
  String get showLess => '접기';

  @override
  String get searchHistorySection => '검색 기록';

  @override
  String get saveSearchHistory => '검색 기록 저장';

  @override
  String get saveSearchHistoryHint => '검색 탭에 최근 검색어를 표시합니다';

  @override
  String get clearSearchHistory => '검색 기록 지우기';

  @override
  String savedSearchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '저장된 검색어 $count개',
      zero: '저장된 검색어 없음',
    );
    return '$_temp0';
  }

  @override
  String get searchHistoryCleared => '검색 기록을 지웠습니다';

  @override
  String get themeSystemShort => '시스템';

  @override
  String get themeLightShort => '라이트';

  @override
  String get themeDarkShort => '다크';

  @override
  String get recapTitle => '독서 기록';

  @override
  String get recapCheckpoints => '완독 체크포인트';

  @override
  String get recapBooksUnit => '권';

  @override
  String get recapDaysUnit => '일';

  @override
  String get recapAllCheckpoints => '모든 체크포인트 달성!';

  @override
  String recapToNextCheckpoint(int remaining, int next) {
    return '$next권까지 $remaining권 남음';
  }

  @override
  String get recapStreak => '연속 독서';

  @override
  String get recapStreakStart => '오늘 읽고 시작해요';

  @override
  String recapLongestStreak(int days) {
    return '최장 $days일';
  }

  @override
  String get recapLastFourWeeks => '최근 4주';

  @override
  String recapReadingDays(int days) {
    return '독서일 $days일';
  }

  @override
  String recapMonthTitle(String monthName) {
    return '$monthName 리캡';
  }

  @override
  String get recapFinishedThisMonth => '이번 달 완독';

  @override
  String get recapGenreMix => '장르 구성';

  @override
  String get translationPromptFormat => '프롬프트 형식';

  @override
  String get translationPromptFormatHint =>
      '이 모델에 요청을 보내는 방식입니다. 번역 전용 모델은 학습 때와 같은 형식에서 품질이 가장 좋습니다. 자동은 모델에 맞춰 고릅니다.';

  @override
  String promptFormatAuto(String format) {
    return '자동 ($format)';
  }

  @override
  String get promptFormatGeneral => '일반 (Gemma 등)';

  @override
  String get promptFormatHyMt => 'Hy-MT 번역 모델';

  @override
  String get promptFormatJaKo => '일→한 대사 번역 모델';

  @override
  String get promptFormatKoreanOnly => '이 형식은 한국어로만 번역합니다. 다른 언어로는 일반 형식을 씁니다.';

  @override
  String translationSomeFailed(int count) {
    return '번역하지 못한 문단 $count개';
  }

  @override
  String get translationReadyPlain => '기기에서 번역됨';

  @override
  String translationNeedsRam(int gb) {
    return 'RAM ${gb}GB 이상';
  }

  @override
  String get translationFaster => '더 빠름';

  @override
  String get translationChargingOnly => '충전 중에만';

  @override
  String get translationChargingOnlyHint => '충전기가 연결될 때까지 기다려 배터리를 쓰지 않습니다.';

  @override
  String get translationDevice => '연산 장치';

  @override
  String get translationDeviceAuto => 'GPU 우선 (더 빠름)';

  @override
  String get translationDeviceCpu => 'CPU (GPU는 화면용으로 비움)';

  @override
  String get translationDeviceHint =>
      '번역 중 화면이 끊기면 CPU를 써 보세요. 느리지만 GPU를 화면 그리기에 남겨 둡니다.';

  @override
  String get translationNoticeChannel => '백그라운드 번역';

  @override
  String get translationNoticeTitle => '서재의 책 번역 중';

  @override
  String translationNoticeProgress(String title, int percent) {
    return '$title · $percent%';
  }

  @override
  String translationNoticeCount(int done, int total, int book, int books) {
    return '$done/$total 문단 · $books권 중 $book번째';
  }

  @override
  String get translationNoticeStop => '중지';

  @override
  String get translationNoticeDone => '서재 번역 완료';

  @override
  String translationNoticeDoneCount(int count) {
    return '번역된 책 $count권';
  }

  @override
  String get translationWaitReading => '책을 읽는 동안 대기 중';

  @override
  String get translationWaitAppClosed => '앱을 열면 이어서 번역';

  @override
  String get translationWaitWarm => '기기가 뜨거워 쉬는 중';

  @override
  String get translationWaitBattery => '배터리 부족, 충전 시 재개';

  @override
  String get translationWaitPowerSave => '절전 모드라 일시정지';

  @override
  String get translationWaitCharger => '충전기 연결 대기 중';

  @override
  String get readerWriting => '글 방향';

  @override
  String get readerWritingAuto => '책 설정';

  @override
  String get readerWritingHorizontal => '가로쓰기';

  @override
  String get readerWritingVertical => '세로쓰기';

  @override
  String get readerLoadFailed => '이 책을 표시하지 못했습니다.';

  @override
  String get readerOpenSimple => '기본 리더로 열기';

  @override
  String get ok => '확인';

  @override
  String get downloadPreparing => '준비 중…';

  @override
  String get downloadStartedTitle => '다운로드를 시작했어요';

  @override
  String get downloadStartedBody => '완료되면 내 서재에 추가돼요. 진행 상황은 알림에서 볼 수 있어요.';

  @override
  String get downloadFastBadge => '빠른 다운로드';

  @override
  String get downloadNotStartedTitle => '다운로드를 시작하지 못했어요';
}
