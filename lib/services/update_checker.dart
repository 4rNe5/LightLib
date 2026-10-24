// Dart imports:
import 'dart:convert';
import 'dart:io';

// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:android_package_installer/android_package_installer.dart';
import 'package:apk_sideload/install_apk.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

// Project imports:
import 'package:openlib/services/app_release.dart';
import 'package:openlib/services/database.dart';
import 'package:openlib/services/download_notification.dart';
import 'package:openlib/services/logger.dart';
import 'package:openlib/ui/components/update_sheet.dart';

// Release information from GitHub
class ReleaseInfo {
  final String version;
  final String tagName;
  final String name;
  final String body;
  final String htmlUrl;
  final bool isPrerelease;
  final DateTime publishedAt;
  final Map<String, String> downloadUrls;

  /// Asset sizes in bytes by download URL.
  final Map<String, int> assetSizes;

  /// The build the tag names (`v1.7.2-build.35`), null for other tags.
  AppBuild? get build => AppBuild.tryParse(tagName);

  /// `1.7.2 (build 35)`, or the version for a tag without a build.
  String get label => build?.label ?? version;

  /// The APK checksum from the description, when the workflow wrote one.
  String? get sha256 => releaseSha256(body);

  ReleaseInfo({
    required this.version,
    required this.tagName,
    required this.name,
    required this.body,
    required this.htmlUrl,
    required this.isPrerelease,
    required this.publishedAt,
    required this.downloadUrls,
    this.assetSizes = const {},
  });

  factory ReleaseInfo.fromJson(Map<String, dynamic> json) {
    final tagName = json["tag_name"] as String;
    final version = tagName.startsWith("v") ? tagName.substring(1) : tagName;

    // Parse download URLs from assets
    final assets = json["assets"] as List<dynamic>? ?? [];
    final downloadUrls = <String, String>{};
    final assetSizes = <String, int>{};

    for (final asset in assets) {
      final name = asset["name"] as String;
      final url = asset["browser_download_url"] as String;
      if (asset["size"] is int) assetSizes[url] = asset["size"] as int;
      // Checksum files ride along with each APK.
      if (name.endsWith(".sha256")) continue;

      // Categorize by platform
      if (name.contains("android") || name.endsWith(".apk")) {
        if (name.contains("arm64")) {
          downloadUrls["android-arm64"] = url;
        } else if (name.contains("armeabi") || name.contains("arm-v7a")) {
          downloadUrls["android-arm32"] = url;
        } else if (name.contains("x86_64")) {
          downloadUrls["android-x64"] = url;
        } else if (name.contains("universal")) {
          downloadUrls["android-universal"] = url;
        } else {
          downloadUrls["android"] = url;
        }
      } else if (name.endsWith(".ipa")) {
        downloadUrls["ios"] = url;
      } else if (name.contains("windows") ||
          name.endsWith(".exe") ||
          name.endsWith(".msix") ||
          (name.endsWith(".zip") &&
              (name.contains("win") || name.contains("x64")))) {
        downloadUrls["windows"] = url;
      } else if (name.contains("linux") ||
          name.endsWith(".AppImage") ||
          name.endsWith(".flatpak")) {
        if (name.endsWith(".AppImage")) {
          downloadUrls["linux-appimage"] = url;
        } else if (name.endsWith(".flatpak")) {
          downloadUrls["linux-flatpak"] = url;
        } else if (name.endsWith(".tar.gz")) {
          downloadUrls["linux-tar"] = url;
        } else if (name.endsWith(".deb")) {
          downloadUrls["linux-deb"] = url;
        } else if (name.endsWith(".rpm")) {
          downloadUrls["linux-rpm"] = url;
        } else {
          downloadUrls["linux"] = url;
        }
      } else if (name.endsWith(".dmg") ||
          name.contains("macos") ||
          name.contains("darwin")) {
        downloadUrls["macos"] = url;
      }
    }

    return ReleaseInfo(
      version: version,
      tagName: tagName,
      name: json["name"] as String? ?? tagName,
      body: json["body"] as String? ?? "",
      htmlUrl: json["html_url"] as String,
      isPrerelease: json["prerelease"] as bool? ?? false,
      publishedAt: DateTime.parse(json["published_at"] as String),
      downloadUrls: downloadUrls,
      assetSizes: assetSizes,
    );
  }
}

// Update check result
class UpdateCheckResult {
  final bool updateAvailable;
  final ReleaseInfo? latestRelease;
  final String currentVersion;

  UpdateCheckResult({
    required this.updateAvailable,
    this.latestRelease,
    required this.currentVersion,
  });
}

// GitHub Update Checker Service
class UpdateCheckerService {
  static final UpdateCheckerService _instance =
      UpdateCheckerService._internal();
  factory UpdateCheckerService() => _instance;
  UpdateCheckerService._internal();

  final AppLogger _logger = AppLogger();
  final MyLibraryDb _database = MyLibraryDb.instance;

  // The fork this app is built from: every push to main is released as
  // v<version>-build.<n> with a signed arm64 APK.
  static const String owner = "4rNe5";
  static const String repo = "LightLib";
  static const String _apiUrl = "https://api.github.com/repos";
  static const String releasesPage = "https://github.com/$owner/$repo/releases";
  static const String _userAgent = "LightLib-App";

  /// The running build (version name + build number).
  static Future<AppBuild> currentBuild() async {
    final info = await PackageInfo.fromPlatform();
    return AppBuild.of(info.version, info.buildNumber);
  }

  // Check for updates
  Future<UpdateCheckResult> checkForUpdates(
      {bool includePrereleases = false}) async {
    try {
      final current = await currentBuild();

      _logger.info("Checking for updates", tag: "UpdateChecker", metadata: {
        "current": current.label,
        "includePrereleases": includePrereleases,
      });

      final releases = await fetchReleases();
      ReleaseInfo? newest;
      AppBuild? newestBuild;
      for (final release in releases) {
        if (release.isPrerelease && !includePrereleases) continue;
        if (getDownloadUrlForPlatform(release) == null &&
            (Platform.isAndroid || Platform.isIOS)) {
          continue;
        }
        final build = release.build ?? AppBuild.tryParse(release.version);
        if (build == null || !(build > current)) continue;
        if (newestBuild == null || build > newestBuild) {
          newest = release;
          newestBuild = build;
        }
      }

      _logger.info("Update check completed", tag: "UpdateChecker", metadata: {
        "latest": newest?.label,
        "updateAvailable": newest != null,
      });

      return UpdateCheckResult(
        updateAvailable: newest != null,
        latestRelease: newest,
        currentVersion: current.label,
      );
    } catch (e, stackTrace) {
      _logger.error("Failed to check for updates",
          tag: "UpdateChecker", error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  List<ReleaseInfo>? _cached;
  DateTime? _cachedAt;

  /// The repository's releases, newest first. Kept for five minutes:
  /// GitHub allows 60 unauthenticated requests an hour.
  Future<List<ReleaseInfo>> fetchReleases({bool refresh = false}) async {
    final cached = _cached;
    if (!refresh &&
        cached != null &&
        DateTime.now().difference(_cachedAt!) < const Duration(minutes: 5)) {
      return cached;
    }
    final url = Uri.parse("$_apiUrl/$owner/$repo/releases?per_page=40");

    final response = await http.get(url, headers: {
      "Accept": "application/vnd.github+json",
      "User-Agent": _userAgent,
    }).timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception("Failed to fetch releases: ${response.statusCode}");
    }

    final List<dynamic> data = json.decode(response.body);
    final releases = [
      for (final r in data)
        if (r is Map<String, dynamic> && r["draft"] != true)
          ReleaseInfo.fromJson(r),
    ];
    _cached = releases;
    _cachedAt = DateTime.now();
    return releases;
  }

  /// The changes released after [after] up to [upTo] as markdown (one
  /// heading per build, newest first), '' when none or offline.
  Future<String> fetchChangeLog(
      {AppBuild? after, AppBuild? upTo, int? limit}) async {
    try {
      final releases = await fetchReleases();
      return changeLog([
        for (final r in releases)
          if (r.build != null)
            (build: r.build!, body: r.body, publishedAt: r.publishedAt),
      ], after: after, upTo: upTo, limit: limit);
    } catch (e) {
      _logger.warning("Could not load the change log",
          tag: "UpdateChecker", error: e);
      return '';
    }
  }

  /// Fetches the release notes (GitHub release description) for the
  /// running version. Returns null when offline, rate-limited, or the
  /// release has no description - callers fall back to the built-in
  /// notes. The tag must match the running version so a mismatched
  /// (e.g. beta) build never shows another release's notes.
  Future<String?> fetchReleaseNotes() async {
    try {
      final running = await currentBuild();

      final releases = await fetchReleases();
      ReleaseInfo? matching;
      for (final r in releases) {
        if (r.build == running) {
          matching = r;
          break;
        }
      }

      final body = matching?.body ?? '';
      if (body.trim().isEmpty) return null;
      return body;
    } catch (e) {
      _logger.warning("Could not load release notes",
          tag: "UpdateChecker", error: e);
      return null;
    }
  }

  // Get the download URL for the current platform
  String? getDownloadUrlForPlatform(ReleaseInfo release) {
    if (Platform.isAndroid) {
      // Prefer arm64 for modern devices
      return release.downloadUrls["android-arm64"] ??
          release.downloadUrls["android-universal"] ??
          release.downloadUrls["android"];
    } else if (Platform.isIOS) {
      return release.downloadUrls["ios"];
    } else if (Platform.isWindows) {
      return release.downloadUrls["windows"];
    } else if (Platform.isLinux) {
      return release.downloadUrls["linux-appimage"] ??
          release.downloadUrls["linux-tar"] ??
          release.downloadUrls["linux-deb"] ??
          release.downloadUrls["linux-flatpak"] ??
          release.downloadUrls["linux"];
    } else if (Platform.isMacOS) {
      return release.downloadUrls["macos"];
    }
    return null;
  }

  // Get file extension for download based on platform
  String _getFileExtension() {
    if (Platform.isAndroid) {
      return "apk";
    } else if (Platform.isIOS) {
      return "ipa";
    } else if (Platform.isWindows) {
      return "exe";
    } else if (Platform.isLinux) {
      return "AppImage";
    } else if (Platform.isMacOS) {
      return "dmg";
    }
    return "bin";
  }

  // Get the downloads directory for storing the update file
  Future<Directory> _getDownloadsDirectory() async {
    // Use temp directory for all platforms - this works better with FileProvider on Android
    return await getTemporaryDirectory();
  }

  // Check and request install packages permission on Android
  Future<bool> _checkAndRequestInstallPermission(BuildContext context) async {
    if (!Platform.isAndroid) return true;

    // Check if permission is already granted
    final status = await Permission.requestInstallPackages.status;
    if (status.isGranted) return true;

    // Show explanation dialog and request permission
    if (!context.mounted) return false;

    final shouldRequest = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.security,
                  color: Theme.of(dialogContext).colorScheme.secondary),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  "Permission Required",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: const Text(
            "To install app updates, OpenlibExtended needs permission to install packages.\n\n"
            "This allows the app to automatically install new versions with bug fixes and new features.\n\n"
            "You will be taken to Settings to enable this permission.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                "Cancel",
                style: TextStyle(
                  color: Theme.of(dialogContext)
                      .colorScheme
                      .tertiary
                      .withValues(alpha: 0.7),
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                "Open Settings",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(dialogContext).colorScheme.secondary,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (shouldRequest != true) return false;

    // Request permission - this will open settings on Android 8+
    final result = await Permission.requestInstallPackages.request();
    return result.isGranted;
  }

  // Download update file with progress tracking and move to install dir (Linux/Windows)
  Future<String?> downloadUpdate({
    required ReleaseInfo release,
    required Function(double progress, int downloaded, int total) onProgress,
    CancelToken? cancelToken,
  }) async {
    final downloadUrl = getDownloadUrlForPlatform(release);
    if (downloadUrl == null) {
      _logger.warning("No download URL available for platform",
          tag: "UpdateChecker");
      return null;
    }

    if (Platform.isAndroid) {
      return _downloadApk(release, downloadUrl, onProgress, cancelToken);
    }

    try {
      final dio = Dio();
      final downloadsDir = await _getDownloadsDirectory();
      final fileExtension = _getFileExtension();
      final tempFileName = "openlib_update_temp.$fileExtension";
      final tempFilePath = "${downloadsDir.path}/$tempFileName";

      _logger.info("Starting update download", tag: "UpdateChecker", metadata: {
        "url": downloadUrl,
        "destination": tempFilePath,
      });

      // Delete existing temp file if present
      final existingFile = File(tempFilePath);
      if (await existingFile.exists()) {
        await existingFile.delete();
      }

      await dio.download(
        downloadUrl,
        tempFilePath,
        cancelToken: cancelToken,
        options: Options(
          headers: {
            "User-Agent": "OpenlibExtended-App",
          },
        ),
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = received / total;
            onProgress(progress, received, total);
          }
        },
      );

      dio.close();

      // Determine install directory and target filename
      String installDirPath;
      String targetFileName;
      if (Platform.isWindows) {
        // Use the directory of the running executable
        installDirPath = File(Platform.resolvedExecutable).parent.path;
        targetFileName = "openlib.exe";
      } else if (Platform.isLinux) {
        installDirPath = File(Platform.resolvedExecutable).parent.path;
        targetFileName = "openlib.AppImage";
      } else {
        // For other platforms, just return the temp file path
        if (Platform.isMacOS || Platform.isIOS || Platform.isAndroid) {
          // No special move needed
          if (Platform.isLinux) {
            await Process.run("chmod", ["+x", tempFilePath]);
          }
          return tempFilePath;
        }
        return tempFilePath;
      }

      final targetFilePath = "$installDirPath/$targetFileName";

      // Remove old versioned executables in the install dir
      final dir = Directory(installDirPath);
      final files = dir.listSync();
      for (final f in files) {
        if (f is File) {
          final name = f.path.split(Platform.pathSeparator).last;
          if ((Platform.isWindows &&
                  name.startsWith("openlib_") &&
                  name.endsWith(".exe")) ||
              (Platform.isLinux &&
                  name.startsWith("openlib_") &&
                  name.endsWith(".AppImage"))) {
            try {
              await f.delete();
            } catch (_) {}
          }
        }
      }

      // Move the downloaded file to the install directory, overwrite if exists
      final tempFile = File(tempFilePath);
      final targetFile = File(targetFilePath);
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      try {
        await tempFile.rename(targetFilePath);
      } on FileSystemException catch (e) {
        // errno=18 is EXDEV (cross-device link)
        if (e.osError != null && e.osError!.errorCode == 18) {
          // Fallback: copy then delete
          await tempFile.copy(targetFilePath);
          await tempFile.delete();
        } else {
          rethrow;
        }
      }

      // Make file executable on Linux
      if (Platform.isLinux) {
        await Process.run("chmod", ["+x", targetFilePath]);
      }

      _logger.info("Update moved to install directory",
          tag: "UpdateChecker",
          metadata: {
            "path": targetFilePath,
          });

      return targetFilePath;
    } catch (e, stackTrace) {
      if (e is DioException && e.type == DioExceptionType.cancel) {
        _logger.info("Update download cancelled", tag: "UpdateChecker");
        return null;
      }
      _logger.error("Failed to download/move update",
          tag: "UpdateChecker", error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Where [release]'s APK is kept once downloaded: one file per build,
  /// so a download finished in the background is installed later
  /// without fetching it again.
  Future<File> _apkFile(ReleaseInfo release) async {
    final dir = Directory("${(await _getDownloadsDirectory()).path}/updates");
    if (!await dir.exists()) await dir.create(recursive: true);
    final name = release.build?.build ?? release.version;
    return File("${dir.path}/LightLib-$name.apk");
  }

  /// [file] is complete: its checksum matches the one the release
  /// published (or, for a release without one, it has the asset's size).
  Future<bool> _verified(File file, ReleaseInfo release) async {
    if (!await file.exists()) return false;
    final expected = release.sha256;
    if (expected != null) {
      final digest = await sha256.bind(file.openRead()).first;
      return digest.toString().toLowerCase() == expected.toLowerCase();
    }
    final url = getDownloadUrlForPlatform(release);
    final size = url == null ? null : release.assetSizes[url];
    return size != null && await file.length() == size;
  }

  /// The APK of [release] when it is already downloaded and verified.
  Future<String?> preparedUpdate(ReleaseInfo release) async {
    if (!Platform.isAndroid) return null;
    final file = await _apkFile(release);
    return await _verified(file, release) ? file.path : null;
  }

  /// Removes downloaded APKs of builds not newer than the running one.
  Future<void> cleanUpDownloads() async {
    if (!Platform.isAndroid) return;
    try {
      final current = await currentBuild();
      final dir = Directory("${(await _getDownloadsDirectory()).path}/updates");
      if (!await dir.exists()) return;
      await for (final f in dir.list()) {
        final m = RegExp(r'LightLib-(\d+)\.apk(\.part)?$').firstMatch(f.path);
        final build = int.tryParse(m?.group(1) ?? '');
        if (build != null && build <= current.build) {
          await f.delete().catchError((_) => f);
        }
      }
      // The single file earlier versions downloaded to.
      final old =
          File("${(await _getDownloadsDirectory()).path}/openlib_update_temp.apk");
      if (await old.exists()) await old.delete();
    } catch (_) {}
  }

  Future<String?> _downloadApk(
    ReleaseInfo release,
    String url,
    Function(double progress, int downloaded, int total) onProgress,
    CancelToken? cancelToken,
  ) async {
    final file = await _apkFile(release);
    if (await _verified(file, release)) {
      final size = await file.length();
      onProgress(1, size, size);
      return file.path;
    }
    final part = File("${file.path}.part");
    final dio = Dio();
    try {
      _logger.info("Starting update download",
          tag: "UpdateChecker",
          metadata: {"release": release.label, "url": url});
      // Continues a download cut off earlier.
      var have = await part.exists() ? await part.length() : 0;
      final response = await dio.get<ResponseBody>(
        url,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: true,
          headers: {
            "User-Agent": _userAgent,
            if (have > 0) "Range": "bytes=$have-",
          },
          validateStatus: (code) => code == 200 || code == 206,
        ),
      );
      if (response.statusCode == 200) have = 0;
      final total = have +
          (int.tryParse(response.headers.value(Headers.contentLengthHeader) ??
                  '') ??
              0);
      final sink = part.openWrite(
          mode: have > 0 ? FileMode.writeOnlyAppend : FileMode.writeOnly);
      var received = have;
      try {
        await for (final chunk in response.data!.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress(received / total, received, total);
        }
      } finally {
        await sink.close();
      }
      if (await file.exists()) await file.delete();
      await part.rename(file.path);
      if (!await _verified(file, release)) {
        await file.delete();
        throw Exception("The downloaded update did not match its checksum");
      }
      _logger.info("Update downloaded",
          tag: "UpdateChecker",
          metadata: {"release": release.label, "bytes": received});
      return file.path;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        _logger.info("Update download cancelled", tag: "UpdateChecker");
        return null;
      }
      _logger.error("Failed to download update",
          tag: "UpdateChecker", error: e);
      rethrow;
    } finally {
      dio.close();
    }
  }

  static const _autoDownloadPref = "autoDownloadUpdates";
  static const _snoozePref = "updateSnoozedBuild";
  static const _channel = MethodChannel('lightlib/background_translation');

  /// New builds download on their own over Wi-Fi (on unless turned off).
  Future<bool> getAutoDownload() async {
    try {
      return await _database.getPreference(_autoDownloadPref) != 0;
    } catch (_) {
      return true;
    }
  }

  Future<void> setAutoDownload(bool value) =>
      _database.savePreference(_autoDownloadPref, value ? 1 : 0);

  /// The network counts its data (mobile data, a metered hotspot).
  Future<bool> _metered() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isMetered') ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<String?>? _preparing;
  int? _preparingBuild;

  /// Downloads [release] in the background, its progress in a
  /// notification. One download at a time; null on failure.
  Future<String?> prepareInBackground(ReleaseInfo release) {
    final build = release.build?.build;
    if (_preparing != null && _preparingBuild == build) return _preparing!;
    _preparingBuild = build;
    return _preparing = _prepare(release).whenComplete(() => _preparing = null);
  }

  Future<String?> _prepare(ReleaseInfo release) async {
    const id = 7310;
    final notifications = DownloadNotificationService();
    await notifications.initialize().catchError((_) {});
    var shown = -1;
    try {
      final path = await downloadUpdate(
        release: release,
        onProgress: (progress, _, __) {
          final percent = (progress * 100).floor();
          if (percent == shown || percent >= 100) return;
          shown = percent;
          notifications
              .showDownloadNotification(
                  id: id,
                  title: "LightLib ${release.label}",
                  body: "$percent%",
                  progress: percent)
              .catchError((_) {});
        },
      );
      await notifications.cancelNotification(id).catchError((_) {});
      return path;
    } catch (e) {
      await notifications.cancelNotification(id).catchError((_) {});
      _logger.warning("Background update download failed",
          tag: "UpdateChecker", error: e);
      return null;
    }
  }

  /// "Later" on [release]: not offered again on its own for a day.
  Future<void> snooze(ReleaseInfo release) => _database.savePreference(
      _snoozePref,
      "${release.build?.build ?? release.version}@"
      "${DateTime.now().millisecondsSinceEpoch}");

  Future<bool> _snoozed(ReleaseInfo release) async {
    try {
      final raw = "${await _database.getPreference(_snoozePref)}";
      final at = raw.lastIndexOf('@');
      if (at < 0) return false;
      final build = raw.substring(0, at);
      final since = int.tryParse(raw.substring(at + 1)) ?? 0;
      return build == "${release.build?.build ?? release.version}" &&
          DateTime.now().millisecondsSinceEpoch - since <
              const Duration(hours: 24).inMilliseconds;
    } catch (_) {
      return false;
    }
  }

  // Open/Install the downloaded update file with fallback mechanisms
  Future<bool> openUpdateFile(String filePath, BuildContext context,
      {ReleaseInfo? release}) async {
    _logger.info("Opening update file", tag: "UpdateChecker", metadata: {
      "path": filePath,
    });

    // Verify file exists and has content
    final file = File(filePath);
    if (!await file.exists()) {
      _logger.error("Update file does not exist", tag: "UpdateChecker");
      if (context.mounted) {
        _showInstallErrorDialog(context, filePath, "Downloaded file not found",
            release: release);
      }
      return false;
    }

    final fileSize = await file.length();
    if (fileSize < 10240) {
      _logger.error("Update file is too small, likely corrupted",
          tag: "UpdateChecker", metadata: {"size": fileSize});
      if (context.mounted) {
        _showInstallErrorDialog(context, filePath,
            "Downloaded file appears to be corrupted (only ${_formatBytes(fileSize)})",
            release: release);
      }
      return false;
    }

    _logger.info("File verified", tag: "UpdateChecker", metadata: {
      "size": fileSize,
    });

    if (Platform.isAndroid) {
      if (!context.mounted) return false;
      return await _installApkWithFallbacks(filePath, context,
          release: release);
    } else if (Platform.isWindows || Platform.isLinux) {
      // Always use the non-versioned filename in the install dir
      String installDirPath = File(Platform.resolvedExecutable).parent.path;
      String targetFileName =
          Platform.isWindows ? "openlib.exe" : "openlib.AppImage";
      String targetFilePath = "$installDirPath/$targetFileName";
      // Launch the new executable
      await Process.start(targetFilePath, [], mode: ProcessStartMode.detached);
      return true;
    } else if (Platform.isMacOS) {
      await OpenFile.open(filePath, type: "application/x-apple-diskimage");
      return true;
    } else if (Platform.isIOS) {
      await OpenFile.open(filePath);
      return true;
    }
    return false;
  }

  // Install APK on Android with multiple fallback methods
  Future<bool> _installApkWithFallbacks(String filePath, BuildContext context,
      {ReleaseInfo? release}) async {
    // Track errors from each method for user display
    List<String> attemptedMethods = [];
    List<String> errorMessages = [];

    // Check and request install permission first
    final hasPermission = await _checkAndRequestInstallPermission(context);
    if (!hasPermission) {
      _logger.warning("Install permission denied", tag: "UpdateChecker");
      if (context.mounted) {
        _showInstallErrorDialog(context, filePath,
            "Permission to install apps was denied. You can still install manually.",
            release: release);
      }
      return false;
    }

    // Warn about debug builds
    if (kDebugMode && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Debug Build Detected: Update may fail with 'App not installed' due to signature mismatch. Uninstall this app first.",
          ),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 10),
        ),
      );
    }

    // Method 1: Try open_file (Most standard method)
    attemptedMethods.add("Open File");
    try {
      _logger.info("Attempting installation with open_file",
          tag: "UpdateChecker");
      final result = await OpenFile.open(filePath,
          type: "application/vnd.android.package-archive");
      if (result.type == ResultType.done) {
        _logger.info("open_file installation initiated", tag: "UpdateChecker");
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                  "Opening installer... If nothing happens, the install failed."),
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: "Manual Install",
                onPressed: () {
                  if (context.mounted) {
                    _showInstallFallbackDialog(
                        context,
                        filePath,
                        attemptedMethods,
                        ["May have failed silently"],
                        release);
                  }
                },
              ),
            ),
          );
        }
        return true;
      }
      final errorMsg =
          "Result type: ${result.type.name}, message: ${result.message}";
      errorMessages.add(errorMsg);
      _logger.warning("open_file failed",
          tag: "UpdateChecker", metadata: {"result": result.type.name});
    } catch (e) {
      final errorMsg = e.toString();
      errorMessages.add(errorMsg);
      _logger.warning("open_file failed",
          tag: "UpdateChecker", metadata: {"error": e.toString()});
    }

    // Method 2: Try apk_sideload
    attemptedMethods.add("APK Sideload");
    try {
      _logger.info("Attempting installation with apk_sideload",
          tag: "UpdateChecker");
      await InstallApk().installApk(filePath);
      _logger.info("apk_sideload installation initiated", tag: "UpdateChecker");

      // Show user that installer was opened
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                "Opening installer... If nothing happens, the install failed."),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: "Manual Install",
              onPressed: () {
                if (context.mounted) {
                  _showInstallFallbackDialog(context, filePath,
                      attemptedMethods, ["May have failed silently"], release);
                }
              },
            ),
          ),
        );
      }
      return true;
    } on PlatformException catch (e) {
      final errorMsg = "PlatformException: ${e.message ?? "Unknown error"}";
      errorMessages.add(errorMsg);
      _logger.warning("apk_sideload failed",
          tag: "UpdateChecker", metadata: {"error": e.message});
    } catch (e) {
      final errorMsg = e.toString();
      errorMessages.add(errorMsg);
      _logger.warning("apk_sideload failed",
          tag: "UpdateChecker", metadata: {"error": e.toString()});
    }

    // Method 3: Try android_package_installer
    attemptedMethods.add("Package Installer");
    try {
      _logger.info("Attempting installation with android_package_installer",
          tag: "UpdateChecker");
      final statusCode = await AndroidPackageInstaller.installApk(
        apkFilePath: filePath,
      );
      if (statusCode != null) {
        final status = PackageInstallerStatus.byCode(statusCode);
        _logger.info("android_package_installer result",
            tag: "UpdateChecker",
            metadata: {"status": status.name, "code": statusCode});
        if (status == PackageInstallerStatus.success) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                    "Opening installer... If nothing happens, the install failed."),
                duration: const Duration(seconds: 5),
                action: SnackBarAction(
                  label: "Manual Install",
                  onPressed: () {
                    if (context.mounted) {
                      _showInstallFallbackDialog(
                          context,
                          filePath,
                          attemptedMethods,
                          ["May have failed silently"],
                          release);
                    }
                  },
                ),
              ),
            );
          }
          return true;
        } else {
          final errorMsg = "Status: ${status.name} (code: $statusCode)";
          errorMessages.add(errorMsg);
        }
      } else {
        errorMessages.add("Returned null status code");
      }
    } catch (e) {
      final errorMsg = e.toString();
      errorMessages.add(errorMsg);
      _logger.warning("android_package_installer failed",
          tag: "UpdateChecker", metadata: {"error": e.toString()});
    }

    // All automatic methods failed - show fallback dialog with error details
    _logger.error("All installation methods failed",
        tag: "UpdateChecker",
        metadata: {
          "attemptedMethods": attemptedMethods,
          "errors": errorMessages,
        });

    if (context.mounted) {
      await _showInstallFallbackDialog(
          context, filePath, attemptedMethods, errorMessages, release);
    }
    return false;
  }

  // Show fallback dialog with manual options when automatic installation fails
  Future<void> _showInstallFallbackDialog(BuildContext context, String filePath,
      [List<String>? attemptedMethods,
      List<String>? errorMessages,
      ReleaseInfo? release]) async {
    final fileName = filePath.split("/").last;
    final hasErrors = errorMessages != null && errorMessages.isNotEmpty;
    final hasMethods = attemptedMethods != null && attemptedMethods.isNotEmpty;

    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Installation Issue",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "The automatic installer couldn't open the APK. This can happen on some Android versions.\n\n"
                  "You can install manually using one of these options:",
                ),
                const SizedBox(height: 16),
                Text(
                  "File: $fileName",
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(dialogContext)
                        .colorScheme
                        .tertiary
                        .withValues(alpha: 0.7),
                  ),
                ),
                // Show attempted methods and errors for debugging
                if (hasMethods || hasErrors) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(dialogContext)
                          .colorScheme
                          .errorContainer
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(dialogContext)
                            .colorScheme
                            .error
                            .withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Installation Failed",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(dialogContext).colorScheme.error,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (hasMethods) ...[
                          Text(
                            "Methods tried:",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(dialogContext)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          ...attemptedMethods.map((method) => Text(
                                "• $method",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(dialogContext)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              )),
                        ],
                        if (hasErrors) ...[
                          const SizedBox(height: 8),
                          Text(
                            "Errors encountered:",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(dialogContext).colorScheme.error,
                            ),
                          ),
                          const SizedBox(height: 4),
                          ...errorMessages.asMap().entries.map((entry) {
                            final index = entry.key;
                            final error = entry.value;
                            final methodName =
                                hasMethods && index < attemptedMethods.length
                                    ? attemptedMethods[index]
                                    : "Method ${index + 1}";
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: SelectableText(
                                "$methodName: $error",
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: "monospace",
                                  color:
                                      Theme.of(dialogContext).colorScheme.error,
                                ),
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                "Cancel",
                style: TextStyle(
                  color: Theme.of(dialogContext)
                      .colorScheme
                      .tertiary
                      .withValues(alpha: 0.7),
                ),
              ),
            ),
            if (release != null)
              TextButton(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  final url = getDownloadUrlForPlatform(release);
                  final targetUrl = url ?? release.htmlUrl;
                  final uri = Uri.parse(targetUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                child: Text(
                  "Download via Browser",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(dialogContext).colorScheme.secondary,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // Show error dialog with fallback options
  Future<void> _showInstallErrorDialog(
      BuildContext context, String filePath, String errorMessage,
      {ReleaseInfo? release}) async {
    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red, size: 28),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Installation Error",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Text(errorMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                "OK",
                style: TextStyle(
                  color: Theme.of(dialogContext).colorScheme.secondary,
                ),
              ),
            ),
            if (File(filePath).existsSync())
              TextButton(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  await _showInstallFallbackDialog(
                      context, filePath, null, null, release);
                },
                child: Text(
                  "Try Manual Install",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(dialogContext).colorScheme.secondary,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return "$bytes B";
    if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB";
    return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
  }

  // Show update download dialog with progress
  Future<void> _showUpdateDownloadDialog(
    BuildContext context,
    ReleaseInfo release,
  ) async {
    String? downloadedFilePath;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return _UpdateDownloadDialog(
          release: release,
          updateChecker: this,
          onComplete: (filePath) {
            downloadedFilePath = filePath;
            Navigator.of(dialogContext).pop();
          },
          onCancel: () {
            Navigator.of(dialogContext).pop();
          },
        );
      },
    );

    // Open the downloaded file if successful
    if (downloadedFilePath != null && context.mounted) {
      try {
        await openUpdateFile(downloadedFilePath!, context, release: release);
      } catch (e) {
        // Show error to user
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Failed to install update: $e"),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  // Get user preference for prerelease updates
  Future<bool> getIncludePrereleases() async {
    try {
      final value = await _database.getPreference("includePrereleaseUpdates");
      return value == 1;
    } catch (e) {
      return false;
    }
  }

  // Set user preference for prerelease updates
  Future<void> setIncludePrereleases(bool value) async {
    await _database.savePreference("includePrereleaseUpdates", value);
  }

  /// The update sheet for [release]: what changed, then download and
  /// install in place (or install right away when it is downloaded).
  Future<void> showUpdateDialog(
      BuildContext context, ReleaseInfo release) async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return _showDesktopUpdateDialog(context, release);
    }
    final current = await currentBuild();
    final notes = await fetchChangeLog(after: current, upTo: release.build);
    final prepared = await preparedUpdate(release);
    if (!context.mounted) return;
    final url = getDownloadUrlForPlatform(release);
    await showUpdateSheet(
      context,
      label: release.label,
      currentLabel: current.label,
      changes: notes.isNotEmpty ? notes : release.body,
      pageUrl: release.htmlUrl,
      sizeBytes: url == null ? null : release.assetSizes[url],
      preparedPath: prepared,
      download: (onProgress, cancel) => downloadUpdate(
          release: release, onProgress: onProgress, cancelToken: cancel),
      install: (path) => openUpdateFile(path, context, release: release),
      onLater: () => snooze(release),
    );
  }

  Future<void> _showDesktopUpdateDialog(
      BuildContext context, ReleaseInfo release) async {
    final downloadUrl = getDownloadUrlForPlatform(release);
    if (downloadUrl != null) {
      return _showUpdateDownloadDialog(context, release);
    }
    final uri = Uri.parse(release.htmlUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// At startup: a newer build is downloaded on its own over Wi-Fi, then
  /// offered for install; on mobile data (or with auto-download off) the
  /// sheet offers the download. Not again for a day after "Later".
  Future<void> checkAndShowUpdateDialog(BuildContext context) async {
    try {
      await cleanUpDownloads();
      final includePrereleases = await getIncludePrereleases();
      final result =
          await checkForUpdates(includePrereleases: includePrereleases);
      final release = result.latestRelease;
      if (!result.updateAvailable || release == null) return;
      if (await _snoozed(release)) return;
      if (Platform.isAndroid &&
          await getAutoDownload() &&
          !await _metered()) {
        await prepareInBackground(release);
      }
      if (context.mounted) await showUpdateDialog(context, release);
    } catch (e) {
      _logger.error("Failed to check for updates",
          tag: "UpdateChecker", error: e);
      // Silently fail - don't show error to user for update checks
    }
  }
}

// Widget for displaying download progress dialog
class _UpdateDownloadDialog extends StatefulWidget {
  final ReleaseInfo release;
  final UpdateCheckerService updateChecker;
  final Function(String? filePath) onComplete;
  final VoidCallback onCancel;

  const _UpdateDownloadDialog({
    required this.release,
    required this.updateChecker,
    required this.onComplete,
    required this.onCancel,
  });

  @override
  State<_UpdateDownloadDialog> createState() => _UpdateDownloadDialogState();
}

class _UpdateDownloadDialogState extends State<_UpdateDownloadDialog> {
  double _progress = 0.0;
  int _downloadedBytes = 0;
  int _totalBytes = 0;
  bool _isDownloading = true;
  bool _downloadComplete = false;
  String? _errorMessage;
  CancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  Future<void> _startDownload() async {
    _cancelToken = CancelToken();

    try {
      final filePath = await widget.updateChecker.downloadUpdate(
        release: widget.release,
        onProgress: (progress, downloaded, total) {
          if (mounted) {
            setState(() {
              _progress = progress;
              _downloadedBytes = downloaded;
              _totalBytes = total;
            });
          }
        },
        cancelToken: _cancelToken,
      );

      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadComplete = filePath != null;
        });

        if (filePath != null) {
          // Small delay to show completion state
          await Future.delayed(const Duration(milliseconds: 500));
          widget.onComplete(filePath);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _cancelDownload() {
    _cancelToken?.cancel();
    widget.onCancel();
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return "$bytes B";
    if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB";
    return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _downloadComplete
                ? Icons.check_circle
                : _errorMessage != null
                    ? Icons.error
                    : Icons.download,
            color: _downloadComplete
                ? Colors.green
                : _errorMessage != null
                    ? Colors.red
                    : Theme.of(context).colorScheme.secondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _downloadComplete
                  ? "Download Complete"
                  : _errorMessage != null
                      ? "Download Failed"
                      : "Downloading Update",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _downloadComplete
                    ? Colors.green
                    : _errorMessage != null
                        ? Colors.red
                        : Theme.of(context).colorScheme.secondary,
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Version ${widget.release.version}",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.tertiary,
            ),
          ),
          const SizedBox(height: 16),
          if (_errorMessage != null) ...[
            Text(
              _errorMessage!,
              style: const TextStyle(
                color: Colors.red,
                fontSize: 13,
              ),
            ),
          ] else if (_downloadComplete) ...[
            const Row(
              children: [
                Icon(Icons.check, color: Colors.green, size: 20),
                SizedBox(width: 8),
                Text(
                  "Opening installer...",
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ] else ...[
            LinearProgressIndicator(
              value: _progress,
              backgroundColor:
                  Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.secondary,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "${(_progress * 100).toStringAsFixed(0)}%",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                ),
                Text(
                  _totalBytes > 0
                      ? "${_formatBytes(_downloadedBytes)} / ${_formatBytes(_totalBytes)}"
                      : "Connecting...",
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context)
                        .colorScheme
                        .tertiary
                        .withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        if (_isDownloading)
          TextButton(
            onPressed: _cancelDownload,
            child: Text(
              "Cancel",
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .tertiary
                    .withValues(alpha: 0.7),
              ),
            ),
          ),
        if (_errorMessage != null)
          TextButton(
            onPressed: widget.onCancel,
            child: Text(
              "Close",
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .tertiary
                    .withValues(alpha: 0.7),
              ),
            ),
          ),
        if (_errorMessage != null)
          TextButton(
            onPressed: () {
              setState(() {
                _errorMessage = null;
                _isDownloading = true;
                _progress = 0.0;
                _downloadedBytes = 0;
                _totalBytes = 0;
              });
              _startDownload();
            },
            child: Text(
              "Retry",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
          ),
      ],
    );
  }
}
