// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'OpenlibExtended';

  @override
  String get navHome => 'Inicio';

  @override
  String get navSearch => 'Buscar';

  @override
  String get navMyLibrary => 'Mi biblioteca';

  @override
  String get navSettings => 'Ajustes';

  @override
  String get cancel => 'Cancelar';

  @override
  String get save => 'Guardar';

  @override
  String get add => 'Añadir';

  @override
  String get delete => 'Eliminar';

  @override
  String get retry => 'Reintentar';

  @override
  String get advancedSearch => 'Búsqueda avanzada';

  @override
  String get author => 'Autor';

  @override
  String get publisher => 'Editorial';

  @override
  String get searchLibraryHint =>
      'Buscar en la biblioteca (título, autor, editorial, año)';

  @override
  String get newCollection => 'Nueva colección';

  @override
  String get noResultsFound => 'No se encontraron resultados';

  @override
  String resultsFor(String query) {
    return 'Resultados para «$query»';
  }

  @override
  String get followSystem => 'Seguir el sistema';

  @override
  String get lightTheme => 'Tema claro';

  @override
  String get darkTheme => 'Tema oscuro';

  @override
  String get languageSetting => 'Idioma';

  @override
  String get systemLanguage => 'Idioma del sistema';

  @override
  String get enableNotifications => 'Activar notificaciones';

  @override
  String get notificationsExplanation =>
      'OpenlibExtended necesita el permiso de notificaciones para mostrar el progreso de las descargas en segundo plano. Así puedes seguir tus descargas de libros aunque la aplicación esté minimizada.';

  @override
  String get maybeLater => 'Quizás más tarde';

  @override
  String get enable => 'Activar';

  @override
  String get statusUnread => 'Sin leer';

  @override
  String get statusInProgress => 'En progreso';

  @override
  String get statusCompleted => 'Completado';

  @override
  String get collectionNameHint => 'p. ej., Favoritos, Ciencia ficción';

  @override
  String get manageCollectionsHint =>
      'Mantén pulsado un libro para gestionar sus colecciones';

  @override
  String get results => 'Resultados';

  @override
  String get loading => 'Cargando...';

  @override
  String get unknown => 'Desconocido';

  @override
  String get about => 'Acerca de';

  @override
  String get aboutDescription =>
      'Una aplicación de código abierto para descargar y leer libros de bibliotecas en la sombra (Anna\'s Archive).';

  @override
  String get aboutForkNote =>
      'Versión bifurcada mantenida por warreth para uso personal y actualizaciones de la comunidad.';

  @override
  String get aboutOriginalNote =>
      'Aplicación original de dstark5 (https://github.com/dstark5/Openlib).';

  @override
  String get version => 'Versión';

  @override
  String get github => 'Github';

  @override
  String get thisForkByWarreth => 'Este fork (por warreth)';

  @override
  String get reportAnIssue => 'Informar de un problema';

  @override
  String get originalProject => 'Proyecto original (por dstark5)';

  @override
  String get licence => 'Licencia';

  @override
  String get gplLicense => 'Licencia GPL v3.0';

  @override
  String couldNotLaunch(String url) {
    return 'No se pudo abrir $url';
  }

  @override
  String get settingsTitle => 'Ajustes';

  @override
  String get searchProvidersSection => 'Fuentes de búsqueda';

  @override
  String get libraryInstancesSection => 'Biblioteca e instancias';

  @override
  String get appearanceSection => 'Apariencia';

  @override
  String get generalSection => 'General';

  @override
  String get readerSection => 'Lector';

  @override
  String get advancedSection => 'Avanzado';

  @override
  String get backupSection => 'Copia de seguridad';

  @override
  String get updatesSection => 'Actualizaciones';

  @override
  String get aboutSection => 'Acerca de';

  @override
  String get archiveInstance => 'Instancia de archivo';

  @override
  String get mirrorsAndProviders => 'Espejos y fuentes';

  @override
  String get fontSizeTitle => 'Tamaño de letra';

  @override
  String scaleValue(String value) {
    return 'Escala: ${value}x';
  }

  @override
  String get preview => 'Vista previa';

  @override
  String get storageLocation => 'Ubicación de almacenamiento';

  @override
  String get openPdfExternally => 'Abrir PDF externamente';

  @override
  String get useDefaultPdfViewer => 'Usar tu visor PDF predeterminado';

  @override
  String get openEpubExternally => 'Abrir EPUB externamente';

  @override
  String get useDefaultEpubReader => 'Usar tu lector EPUB predeterminado';

  @override
  String get manualDownloadButton => 'Botón de descarga manual';

  @override
  String get backgroundVerification => 'Verificar en segundo plano';

  @override
  String get backgroundVerificationHint =>
      'Resuelve comprobaciones DDoS de forma invisible. En algunos dispositivos falla - desactívalo para verificar en una ventana visible';

  @override
  String get backgroundVerificationFix =>
      'Si la verificación sigue fallando, desactiva \"Verificar en segundo plano\" en Ajustes: algunos dispositivos no pueden resolver comprobaciones de forma invisible.';

  @override
  String get showManualDownloadHint =>
      'Mostrar botón para iniciar descargas manualmente';

  @override
  String get donationKeyTitle => 'Clave de donación de Anna\'s Archive';

  @override
  String get enterKeyForFasterDownloads =>
      'Introduce la clave para descargas más rápidas';

  @override
  String get aboutOpenlib => 'Acerca de OpenlibExtended';

  @override
  String get redoOnboarding => 'Repetir la introducción';

  @override
  String get resetAppSetup => 'Restablecer la configuración y empezar de nuevo';

  @override
  String get exportLogs => 'Exportar registros';

  @override
  String get shareDiagnosticLogs =>
      'Compartir registros de diagnóstico (últimos 5 min)';

  @override
  String failedExportLogs(String error) {
    return 'Error al exportar registros: $error';
  }

  @override
  String get donationKeyDialog => 'Clave de donación';

  @override
  String get enterYourKey => 'Introduce tu clave';

  @override
  String get instanceChanged => 'Instancia cambiada correctamente';

  @override
  String rankingFailed(String error) {
    return 'Error al clasificar: $error';
  }

  @override
  String get autoRankInstances => 'Clasificar instancias automáticamente';

  @override
  String get sortBySpeedOnStartup =>
      'Ordenar automáticamente por velocidad al iniciar';

  @override
  String get rankInstancesNow => 'Clasificar instancias ahora';

  @override
  String onLatestVersion(String version) {
    return 'Ya tienes la última versión ($version)';
  }

  @override
  String failedCheckUpdates(String error) {
    return 'Error al buscar actualizaciones: $error';
  }

  @override
  String get includeBetaUpdates => 'Incluir versiones beta';

  @override
  String get getPreReleaseVersions => 'Obtener versiones preliminares';

  @override
  String get checkForUpdates => 'Buscar actualizaciones';

  @override
  String get backupSaved => 'Copia de seguridad guardada';

  @override
  String failedExportBackup(String error) {
    return 'Error al exportar la copia: $error';
  }

  @override
  String get backupRestored => 'Copia de seguridad restaurada';

  @override
  String failedImportBackup(String error) {
    return 'Error al importar la copia: $error';
  }

  @override
  String get atLeastOneSource => 'Se necesita al menos una fuente de búsqueda';

  @override
  String rankedFastest(String name, String time) {
    return '¡Clasificado! Más rápida: $name (${time}ms)';
  }

  @override
  String get rankingComplete => 'Clasificación completada';

  @override
  String get providerSourceOriginal =>
      'Se busca al final - protegido por DDoS-Guard';

  @override
  String get providerLibgenCatalog =>
      'Descargas rápidas y directas - se busca primero';

  @override
  String get providerZlibMirrors =>
      'Los espejos rotan; puede requerir inicio de sesión';

  @override
  String get themeTitle => 'Tema';

  @override
  String get saveBackupTitle => 'Guardar copia de seguridad';

  @override
  String get pickBackupFile => 'Elegir un archivo de copia';

  @override
  String get notABackup =>
      'Ese archivo no es una copia de seguridad de OpenlibExtended';

  @override
  String get donationKeyHelper =>
      'Se usa para descargas más rápidas en Anna\'s Archive';

  @override
  String get mirrorsTestedRanked =>
      'Espejos probados y clasificados por velocidad';

  @override
  String testingFailed(String error) {
    return 'Error al probar: $error';
  }

  @override
  String get addCustomMirror => 'Añadir espejo personalizado';

  @override
  String get nameLabel => 'Nombre';

  @override
  String get nameHint => 'p. ej., Mi espejo de LibGen';

  @override
  String get serviceLabel => 'Servicio';

  @override
  String get urlLabel => 'URL';

  @override
  String get urlHint => 'https://example.com';

  @override
  String get pleaseFillAllFields => 'Rellena todos los campos';

  @override
  String get enterValidUrl => 'Introduce una URL válida con http:// o https://';

  @override
  String get mirrorAdded => 'Espejo añadido correctamente';

  @override
  String get deleteMirror => 'Eliminar espejo';

  @override
  String deleteMirrorConfirm(String name) {
    return '¿Seguro que quieres eliminar «$name»?';
  }

  @override
  String get mirrorDeleted => 'Espejo eliminado';

  @override
  String get cannotDeleteDefaultMirrors =>
      'No se pueden eliminar los espejos predeterminados';

  @override
  String get manageMirrors => 'Gestionar espejos';

  @override
  String get noMirrorsAvailable => 'No hay espejos disponibles';

  @override
  String errorLabel(String error) {
    return 'Error: $error';
  }

  @override
  String get addMirror => 'Añadir espejo';

  @override
  String get testRankMirrors => 'Probar y clasificar espejos por velocidad';

  @override
  String get unreachable => 'inaccesible';

  @override
  String get open => 'Abrir';

  @override
  String get unableToOpenFile => '¡No se pudo abrir el archivo!';

  @override
  String get openInSite => 'Abrir en el sitio';

  @override
  String get bookDeleted => '¡Libro eliminado!';

  @override
  String get deleteBook => 'Eliminar libro';

  @override
  String get deletePermanentWarning =>
      'Esto es permanente y no se puede deshacer';

  @override
  String get tryAgain => 'Reintentar';

  @override
  String get showBlockedContent => 'Mostrar contenido de la página bloqueada';

  @override
  String get verifyInBrowser => 'Verificar en el navegador';

  @override
  String get manualVerificationRequired => 'Verificación manual requerida';

  @override
  String get systemBrowser => 'Navegador del sistema';

  @override
  String get embeddedBrowser => 'Navegador integrado';

  @override
  String get unableToOpenVerification =>
      'No se pudo abrir la página de verificación - no hay URL disponible';

  @override
  String get blockedPageContent => 'Contenido de la página bloqueada';

  @override
  String get copiedToClipboard => 'Copiado al portapapeles';

  @override
  String get gotIt => '¡Entendido!';

  @override
  String get copy => 'Copiar';

  @override
  String get tryUsingVpn => 'Prueba a usar una VPN';

  @override
  String get trending => 'Tendencias';

  @override
  String get genres => 'Géneros';

  @override
  String get copiedBookPath => 'Ruta del libro copiada al portapapeles';

  @override
  String get pauseDownload => 'Pausar descarga';

  @override
  String get resumeDownload => 'Reanudar descarga';

  @override
  String get cancelDownload => 'Cancelar descarga';

  @override
  String get copiedBookLink => 'Enlace del libro copiado al portapapeles';

  @override
  String get noMirrors => '¡No hay espejos disponibles!';

  @override
  String get addToMyLibrary => 'Añadir a mi biblioteca';

  @override
  String get downloadStartedBackground => 'Descarga iniciada en segundo plano';

  @override
  String get bookDownloaded => '¡Libro descargado!';

  @override
  String get selectStorageToContinue =>
      'Selecciona una carpeta de almacenamiento para continuar';

  @override
  String get getStarted => 'Comenzar';

  @override
  String get next => 'Siguiente';

  @override
  String get welcomeTitle => 'Bienvenido a OpenlibExtended';

  @override
  String get welcomeSubtitle =>
      'Tu puerta de entrada personal a un mundo de conocimiento. Vamos a configurarlo todo.';

  @override
  String get whereToStoreBooks => '¿Dónde guardamos tus libros?';

  @override
  String get noPathSelected => 'Ninguna ruta seleccionada';

  @override
  String get selectFolder => 'Elegir carpeta';

  @override
  String get storageScanNote =>
      'Solo buscaremos archivos PDF/EPUB en esta carpeta. No se escanean subcarpetas.';

  @override
  String get automaticUpdates => 'Actualizaciones automáticas';

  @override
  String get enableAutoUpdates => 'Activar actualizaciones automáticas';

  @override
  String get autoUpdatesFdroidNote =>
      'No se recomienda si instalaste desde F-Droid (F-Droid gestiona las actualizaciones).';

  @override
  String get enableBetaUpdatesOnboarding => 'Activar versiones beta';

  @override
  String get betaUpdatesNote =>
      'Recibir versiones preliminares (beta) cuando estén disponibles.';

  @override
  String get supportAnnasArchive => 'Apoyar a Anna\'s Archive';

  @override
  String get donationPitch =>
      'Donar a Anna\'s Archive permite descargas más rápidas y les ayuda a mantener el servicio para todos. Puedes introducir tu clave secreta abajo.';

  @override
  String get annasSecretKey => 'Clave secreta de Anna\'s Archive';

  @override
  String get supportThisApp => 'Apoyar esta aplicación';

  @override
  String get sponsorPitch =>
      'Si te gusta esta aplicación, considera apoyar su desarrollo. ¡Me ayuda a dedicar más tiempo a mejorarla!';

  @override
  String get sponsorOnGithub => 'Patrocinar en GitHub';

  @override
  String get stayUpdated => 'Mantente al día';

  @override
  String get notifyOnComplete => 'Recibir aviso cuando terminen las descargas.';

  @override
  String get chooseTheme => 'Elige un tema';

  @override
  String get lightThemeShort => 'Claro';

  @override
  String get darkThemeShort => 'Oscuro';

  @override
  String get verifyingAccess => 'Verificando acceso';

  @override
  String get done => 'Hecho';

  @override
  String get nothingToRead => 'Nada que leer en esta página';

  @override
  String get noVoiceAvailable => 'No hay voz disponible para leer en voz alta';

  @override
  String get pauseReadingAloud => 'Pausar lectura en voz alta';

  @override
  String get resumeReadingAloud => 'Leer en voz alta';

  @override
  String get stopReadingAloud => 'Detener lectura en voz alta';

  @override
  String get speechSpeed => 'Velocidad del habla';

  @override
  String get decreaseFontSize => 'Reducir tamaño de letra';

  @override
  String get increaseFontSize => 'Aumentar tamaño de letra';

  @override
  String get close => 'Cerrar';

  @override
  String get sortLibrary => 'Ordenar biblioteca';

  @override
  String get reloadHealthData => 'Recargar datos de salud';

  @override
  String addServiceMirror(String title) {
    return 'Añadir un espejo de $title';
  }

  @override
  String get deleteMirrorTooltip => 'Eliminar espejo';

  @override
  String get ttsEngineMissing =>
      'No se encontró ningún motor de síntesis de voz. Instala uno (p. ej. Servicios de voz) en los ajustes del sistema.';

  @override
  String get previousPage => 'Página anterior';

  @override
  String get nextPage => 'Página siguiente';

  @override
  String searchingOn(String source) {
    return 'Resultados de $source';
  }

  @override
  String get sourceLibgen => 'LibGen';

  @override
  String get sourceZlib => 'Z-Library';

  @override
  String get sourceAnnas => 'Anna\'s Archive';

  @override
  String downloadFrom(String source) {
    return 'Descargando desde $source';
  }

  @override
  String get tryingNextSource =>
      'Sin resultados aquí, probando la siguiente fuente…';

  @override
  String get slowMirrorsSkipped => 'Usando espejos más rápidos';

  @override
  String whatsNewTitle(String version) {
    return 'Novedades de $version';
  }

  @override
  String get whatsNewIntro =>
      'OpenlibExtended se ha actualizado. Esto es lo que cambió.';

  @override
  String get whatsNewTabFeatures => 'Nuevas funciones';

  @override
  String get whatsNewTabSources => 'Fuentes y mirrors';

  @override
  String get whatsNewProvidersHint =>
      'Esta versión añade nuevos proveedores de búsqueda y mirrors. Actualiza tu lista para eliminar los mirrors muertos y añadir los nuevos; los tres proveedores quedarán activados.';

  @override
  String get whatsNewUpdateInstances => 'Actualizar lista de mirrors';

  @override
  String get whatsNewInstancesUpdated => 'Lista de mirrors actualizada';

  @override
  String get whatsNewContinue => 'Continuar';

  @override
  String get whatsNewFeatureSpeed =>
      'Las descargas empiezan más rápido: sin sondear mirrors, servidores rápidos primero y las puertas IPFS lentas al final.';

  @override
  String get whatsNewFeatureSourceLabels =>
      'Cada resultado de búsqueda y cada descarga muestra ahora de qué catálogo proviene.';

  @override
  String get whatsNewFeatureCovers =>
      'Las portadas de LibGen que faltan se obtienen de la página de detalle del libro.';

  @override
  String get zlibRecommendationsTitle => 'También te puede interesar';

  @override
  String get zlibRecommendationsLoadMore => 'Cargar más';

  @override
  String get zlibRecommendationsLoadFailed =>
      'No se pudieron cargar más libros';

  @override
  String get searchingSources => 'Buscando…';

  @override
  String searchingSource(String source) {
    return 'Buscando en $source…';
  }

  @override
  String tryingNextSourceNamed(String previous, String source) {
    return 'Nada en $previous, probando $source…';
  }

  @override
  String get translationTranslate => 'Traducir';

  @override
  String get translationShowOriginal => 'Ver original';

  @override
  String get translationNoModel =>
      'Aún no hay ningún modelo de traducción instalado.';

  @override
  String get translationOpenSettings => 'Configurar';

  @override
  String get translationLoadingModel =>
      'Preparando el modelo de traducción… (la primera vez puede tardar unos minutos)';

  @override
  String translationTranslating(int count, String device) {
    return 'Traduciendo · quedan $count · $device';
  }

  @override
  String translationReady(String device) {
    return 'Traducido en este dispositivo · $device';
  }

  @override
  String get translationPaused => 'Traducción en pausa';

  @override
  String get translationFailed => 'El modelo de traducción no pudo ejecutarse.';

  @override
  String get translationSettingsTitle => 'Traducción en el dispositivo';

  @override
  String get translationSettingsSubtitle =>
      'Traduce libros en el lector con un modelo de IA local';

  @override
  String get translationTargetLanguage => 'Traducir a';

  @override
  String get translationModels => 'Modelos';

  @override
  String get translationModelsHint =>
      'LiteRT usa la GPU y recurre a la CPU. El archivo GGUF es para móviles donde LiteRT no funciona.';

  @override
  String get translationRecommended => 'recomendado';

  @override
  String get translationDownload => 'Descargar';

  @override
  String translationDownloadConfirm(String size) {
    return 'Se descargarán $size. Usa Wi-Fi si puedes. El archivo se queda en este dispositivo.';
  }

  @override
  String get translationVerifying => 'Verificando el archivo…';

  @override
  String translationDownloadFailed(String error) {
    return 'La descarga falló: $error';
  }

  @override
  String get translationInUse => 'En uso';

  @override
  String get translationUse => 'Usar';

  @override
  String get translationDeleteConfirm =>
      '¿Borrar este archivo de modelo del dispositivo?';

  @override
  String get translationImportModel =>
      'Importar un archivo de modelo (.litertlm / .gguf)';

  @override
  String get translationNotAModel => 'Elige un archivo .litertlm o .gguf.';

  @override
  String get translationImported => 'Modelo importado y seleccionado.';

  @override
  String get translationImportFailed =>
      'No se pudo importar el archivo de modelo.';

  @override
  String get translationBatteryNote =>
      'Solo se traducen los párrafos en pantalla y algunos siguientes, y el resultado se guarda. La traducción se pausa en segundo plano.';

  @override
  String get translationClearCache => 'Borrar traducciones guardadas';

  @override
  String get translationCacheCleared => 'Traducciones guardadas borradas.';

  @override
  String get importBooks => 'Importar EPUB / PDF';

  @override
  String get importBooksFailed => 'No se pudo abrir el selector de archivos.';

  @override
  String importBooksResult(int imported, int existing, int failed) {
    return 'Añadidos $imported · ya en la biblioteca $existing · fallidos $failed';
  }

  @override
  String get translationAutoLibrary =>
      'Traducir los libros de la biblioteca en segundo plano';

  @override
  String get translationAutoLibraryHint =>
      'Desactivado hasta que lo actives. Lento y suave: descansa tras cada párrafo, espera mientras lees o si el teléfono está caliente o con poca batería, y sigue con una notificación al salir de la app. Las traducciones se guardan junto a cada libro.';

  @override
  String get translationBookDone => 'Listo';

  @override
  String get readerViewOptions => 'Vista';

  @override
  String get readerLayoutScroll => 'Desplazamiento';

  @override
  String get readerLayoutPagesLtr => 'Páginas (izquierda a derecha)';

  @override
  String get readerLayoutPagesRtl => 'Páginas (derecha a izquierda, manga)';

  @override
  String get readerFonts => 'Fuentes';

  @override
  String get fontsSettingsSubtitle =>
      'Fuentes para texto coreano, japonés y latino';

  @override
  String get fontsHint =>
      'Cada escritura usa su propia fuente. Las Google Fonts se descargan una vez y luego funcionan sin conexión. También puedes importar un archivo .ttf u .otf.';

  @override
  String get fontKorean => 'Texto coreano';

  @override
  String get fontJapanese => 'Texto japonés';

  @override
  String get fontLatin => 'Texto latino';

  @override
  String get fontSystem => 'Predeterminada del sistema';

  @override
  String get fontFile => 'archivo';

  @override
  String get fontImport => 'Importar un archivo de fuente (.ttf / .otf)';

  @override
  String fontImported(String family) {
    return 'Fuente importada: $family';
  }

  @override
  String get fontImportFailed => 'No se pudo importar la fuente.';

  @override
  String get readerThemesSettings => 'Temas y ajustes';

  @override
  String get readerThemeOriginal => 'Original';

  @override
  String get readerThemePaper => 'Papel';

  @override
  String get readerThemeCalm => 'Calma';

  @override
  String get readerThemeQuiet => 'Silencio';

  @override
  String get readerThemeBold => 'Negrita';

  @override
  String get readerThemeNight => 'Noche';

  @override
  String get readerLayout => 'Diseño';

  @override
  String get readerLayoutPagesShort => 'Páginas';

  @override
  String get readerLayoutMangaShort => 'Manga';

  @override
  String get readerFont => 'Fuente';

  @override
  String get readerAllFonts => 'Fuentes por idioma';

  @override
  String get readerCustomize => 'Personalizar';

  @override
  String get readerFontSize => 'Tamaño del texto';

  @override
  String get readerLineSpacing => 'Interlineado';

  @override
  String get readerLetterSpacing => 'Espaciado entre caracteres';

  @override
  String get readerMargins => 'Márgenes';

  @override
  String get readerJustify => 'Justificar texto';

  @override
  String get readerBoldText => 'Texto en negrita';

  @override
  String get readerReset => 'Restablecer';

  @override
  String get readerContents => 'Índice';

  @override
  String get libraryContinueReading => 'Seguir leyendo';

  @override
  String get libraryAllBooks => 'Todos los libros';

  @override
  String libraryBookCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count libros',
      one: '1 libro',
    );
    return '$_temp0';
  }

  @override
  String get libraryNoMatches => 'Ningún libro coincide con los filtros';

  @override
  String get libraryEmpty => 'Tu biblioteca está vacía';

  @override
  String get libraryEmptyHint =>
      'Importa tus archivos EPUB o PDF para empezar a leer.';

  @override
  String get bookGenre => 'Género';

  @override
  String get bookCollections => 'Colecciones';

  @override
  String get genreAll => 'Todos';

  @override
  String get genreNone => 'Sin género';

  @override
  String get genreLightNovel => 'Novela ligera';

  @override
  String get genreComic => 'Cómics';

  @override
  String get genreNovel => 'Novela';

  @override
  String get genreEnglishNovel => 'Novela en inglés';

  @override
  String get genreEssay => 'Ensayo';

  @override
  String get genreScience => 'Ciencia';

  @override
  String get genreHumanities => 'Humanidades';

  @override
  String get genreBusiness => 'Negocios';

  @override
  String get genrePaper => 'Artículos científicos';

  @override
  String get genreTextbook => 'Libros de texto';

  @override
  String get genreOther => 'Otros';

  @override
  String get translationLightNovelStyle => 'Estilo de novela ligera';

  @override
  String get translationLightNovelStyleHint =>
      'Conserva el registro formal e informal, las muletillas de los personajes, los honoríficos y las onomatopeyas. Desactívalo para no ficción. Cada estilo guarda sus propias traducciones.';

  @override
  String get libraryBookOptions => 'Opciones del libro';

  @override
  String get libraryRecentlyAdded => 'Añadidos recientemente';

  @override
  String get libraryReadingNow => 'Leyendo ahora';

  @override
  String libraryFinishedCount(int count) {
    return '$count terminados';
  }

  @override
  String get recentSearches => 'Búsquedas recientes';

  @override
  String get clearAll => 'Borrar todo';

  @override
  String get removeFromHistory => 'Quitar del historial';

  @override
  String get searchHistoryFill => 'Editar búsqueda';

  @override
  String get showMore => 'Mostrar más';

  @override
  String get showLess => 'Mostrar menos';

  @override
  String get searchHistorySection => 'Historial de búsqueda';

  @override
  String get saveSearchHistory => 'Guardar historial de búsqueda';

  @override
  String get saveSearchHistoryHint =>
      'Mostrar búsquedas recientes en la pestaña Buscar';

  @override
  String get clearSearchHistory => 'Borrar historial de búsqueda';

  @override
  String savedSearchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count búsquedas guardadas',
      one: '1 búsqueda guardada',
      zero: 'Sin búsquedas guardadas',
    );
    return '$_temp0';
  }

  @override
  String get searchHistoryCleared => 'Historial borrado';

  @override
  String get themeSystemShort => 'Sistema';

  @override
  String get themeLightShort => 'Claro';

  @override
  String get themeDarkShort => 'Oscuro';

  @override
  String get recapTitle => 'Registro de lectura';

  @override
  String get recapCheckpoints => 'Hitos';

  @override
  String get recapBooksUnit => '';

  @override
  String get recapDaysUnit => '';

  @override
  String get recapAllCheckpoints => '¡Todos los hitos logrados!';

  @override
  String recapToNextCheckpoint(int remaining, int next) {
    return 'Faltan $remaining para $next';
  }

  @override
  String get recapStreak => 'días seguidos';

  @override
  String get recapStreakStart => 'Lee hoy para empezar';

  @override
  String recapLongestStreak(int days) {
    return 'Récord: $days d';
  }

  @override
  String get recapLastFourWeeks => 'Últimas 4 semanas';

  @override
  String recapReadingDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days días de lectura',
      one: '1 día de lectura',
    );
    return '$_temp0';
  }

  @override
  String recapMonthTitle(String monthName) {
    return 'Resumen de $monthName';
  }

  @override
  String get recapFinishedThisMonth => 'terminados este mes';

  @override
  String get recapGenreMix => 'Mezcla de géneros';

  @override
  String get translationPromptFormat => 'Formato de instrucciones';

  @override
  String get translationPromptFormatHint =>
      'Cómo se redactan las peticiones para este modelo. Los modelos de traducción funcionan mejor con el formato con el que se entrenaron; Automático lo elige según el modelo.';

  @override
  String promptFormatAuto(String format) {
    return 'Automático ($format)';
  }

  @override
  String get promptFormatGeneral => 'General (Gemma y otros)';

  @override
  String get promptFormatHyMt => 'Modelo de traducción Hy-MT';

  @override
  String get promptFormatJaKo => 'Modelo de diálogo japonés→coreano';

  @override
  String get promptFormatKoreanOnly =>
      'Este formato solo traduce al coreano. Para otros idiomas se usa el formato general.';

  @override
  String translationSomeFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'No se pudieron traducir $count párrafos',
      one: 'No se pudo traducir 1 párrafo',
    );
    return '$_temp0';
  }

  @override
  String get translationReadyPlain => 'Traducido en el dispositivo';

  @override
  String translationNeedsRam(int gb) {
    return 'RAM de $gb GB o más';
  }

  @override
  String get translationFaster => 'más rápido';

  @override
  String get translationChargingOnly => 'Solo mientras se carga';

  @override
  String get translationChargingOnlyHint =>
      'Espera a un cargador, para no gastar batería en ello.';

  @override
  String get translationDevice => 'Procesador';

  @override
  String get translationDeviceAuto => 'GPU primero (más rápido)';

  @override
  String get translationDeviceCpu => 'CPU (la GPU queda para la pantalla)';

  @override
  String get translationDeviceHint =>
      'Si el desplazamiento se entrecorta al traducir, prueba la CPU: más lenta, pero la pantalla conserva la GPU.';

  @override
  String get translationNoticeChannel => 'Traducción en segundo plano';

  @override
  String get translationNoticeTitle => 'Traduciendo libros de la biblioteca';

  @override
  String translationNoticeProgress(String title, int percent) {
    return '$title · $percent %';
  }

  @override
  String translationNoticeCount(int done, int total, int book, int books) {
    return '$done/$total párrafos · libro $book de $books';
  }

  @override
  String get translationNoticeStop => 'Detener';

  @override
  String get translationNoticeDone => 'Traducción de la biblioteca terminada';

  @override
  String translationNoticeDoneCount(int count) {
    return 'Libros traducidos: $count';
  }

  @override
  String get translationWaitReading => 'Esperando mientras lees';

  @override
  String get translationWaitAppClosed => 'Continúa cuando la app esté abierta';

  @override
  String get translationWaitWarm => 'El teléfono está caliente, en pausa';

  @override
  String get translationWaitBattery => 'Batería baja, en pausa hasta cargar';

  @override
  String get translationWaitPowerSave => 'Ahorro de batería activado, en pausa';

  @override
  String get translationWaitCharger => 'Esperando un cargador';

  @override
  String get readerWriting => 'Dirección del texto';

  @override
  String get readerWritingAuto => 'Libro';

  @override
  String get readerWritingHorizontal => 'Horizontal';

  @override
  String get readerWritingVertical => 'Vertical';

  @override
  String get readerLoadFailed => 'No se pudo mostrar este libro.';

  @override
  String get readerOpenSimple => 'Abrir en el lector simple';

  @override
  String get ok => 'Aceptar';

  @override
  String get downloadPreparing => 'Preparando…';

  @override
  String get downloadStartedTitle => 'Descarga iniciada';

  @override
  String get downloadStartedBody =>
      'Se añadirá a tu biblioteca al terminar. La notificación muestra el progreso.';

  @override
  String get downloadFastBadge => 'Descarga rápida';

  @override
  String get downloadNotStartedTitle => 'No se pudo iniciar la descarga';
}
