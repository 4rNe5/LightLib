// Where translation model files live, and how they get there.

// Dart imports:
import 'dart:async';
import 'dart:io';
import 'dart:isolate';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/logger.dart';
import 'package:openlib/services/translation/translation_models.dart';

/// Preference holding the file name of the model the reader uses.
const selectedTranslationModelPref = 'translationModelFile';

/// Preference holding the target language code.
const translationTargetLanguagePref = 'translationTargetLanguage';

enum ModelDownloadPhase { downloading, verifying, failed }

@immutable
class ModelDownloadState {
  final ModelDownloadPhase phase;
  final int receivedBytes;
  final int totalBytes;
  final String? error;

  const ModelDownloadState({
    required this.phase,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.error,
  });

  double? get fraction =>
      totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0, 1) : null;
}

/// A model file present on the device.
@immutable
class InstalledModel {
  final String fileName;
  final String path;
  final int sizeBytes;
  final TranslationRuntime runtime;

  const InstalledModel({
    required this.fileName,
    required this.path,
    required this.sizeBytes,
    required this.runtime,
  });

  TranslationModelPreset? get preset => presetForFile(fileName);

  String get displayName => preset?.name ?? fileName;
}

/// Keeps model files in the app's private support directory (never in the
/// user's book folder, so library sync never sees them), downloads presets
/// with resume and checksum verification, and imports files the user has.
class TranslationModelStore extends ChangeNotifier {
  TranslationModelStore._();
  static final TranslationModelStore instance = TranslationModelStore._();

  /// Overridable in tests.
  @visibleForTesting
  Future<Directory> Function() directoryProvider = _defaultDirectory;

  final AppLogger _logger = AppLogger();
  final Map<String, ModelDownloadState> _downloads = {};
  final Map<String, CancelToken> _cancelTokens = {};

  Map<String, ModelDownloadState> get downloads => Map.unmodifiable(_downloads);

  static Future<Directory> _defaultDirectory() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'translation_models'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<List<InstalledModel>> installed() async {
    final dir = await directoryProvider();
    final models = <InstalledModel>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      final runtime = runtimeForFile(name);
      if (runtime == null) continue;
      models.add(InstalledModel(
        fileName: name,
        path: entity.path,
        sizeBytes: await entity.length(),
        runtime: runtime,
      ));
    }
    models.sort((a, b) => a.fileName.compareTo(b.fileName));
    return models;
  }

  /// The model the reader should load: the selected one when it is still
  /// installed, otherwise the first installed LiteRT-LM model, otherwise
  /// any installed model. Null when none is installed.
  Future<InstalledModel?> activeModel({MyLibraryDb? database}) async {
    final models = await installed();
    if (models.isEmpty) return null;
    final db = database ?? MyLibraryDb.instance;
    final selected = await db
        .getPreference(selectedTranslationModelPref)
        .catchError((_) => null);
    for (final model in models) {
      if (model.fileName == selected) return model;
    }
    return models.firstWhere((m) => m.runtime == TranslationRuntime.liteRtLm,
        orElse: () => models.first);
  }

  Future<void> select(String fileName, {MyLibraryDb? database}) async {
    await (database ?? MyLibraryDb.instance)
        .savePreference(selectedTranslationModelPref, fileName);
    notifyListeners();
  }

  bool isDownloading(String presetId) =>
      _downloads[presetId]?.phase == ModelDownloadPhase.downloading ||
      _downloads[presetId]?.phase == ModelDownloadPhase.verifying;

  /// Downloads [preset] into the model directory. A previous partial file
  /// is resumed with a Range request. The finished file must match the
  /// published size and SHA-256, or it is deleted and the download fails.
  Future<void> download(TranslationModelPreset preset, {Dio? dio}) async {
    if (isDownloading(preset.id)) return;
    final dir = await directoryProvider();
    final target = File(p.join(dir.path, preset.fileName));
    final part = File('${target.path}.part');
    final token = CancelToken();
    _cancelTokens[preset.id] = token;
    final client = dio ??
        Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(minutes: 2),
          followRedirects: true,
        ));

    void update(ModelDownloadState state) {
      _downloads[preset.id] = state;
      notifyListeners();
    }

    var received = await part.exists() ? await part.length() : 0;
    update(ModelDownloadState(
      phase: ModelDownloadPhase.downloading,
      receivedBytes: received,
      totalBytes: preset.sizeBytes,
    ));

    try {
      if (received < preset.sizeBytes) {
        final response = await client.get<ResponseBody>(
          preset.url,
          cancelToken: token,
          options: Options(
            responseType: ResponseType.stream,
            headers: {if (received > 0) 'Range': 'bytes=$received-'},
            validateStatus: (s) => s == 200 || s == 206,
          ),
        );
        // A 200 to a Range request means the server sent the whole file.
        final append = response.statusCode == 206 && received > 0;
        if (!append) received = 0;
        final sink =
            part.openWrite(mode: append ? FileMode.append : FileMode.write);
        var lastNotify = DateTime.now();
        try {
          await for (final chunk in response.data!.stream) {
            sink.add(chunk);
            received += chunk.length;
            final now = DateTime.now();
            if (now.difference(lastNotify).inMilliseconds > 250) {
              lastNotify = now;
              update(ModelDownloadState(
                phase: ModelDownloadPhase.downloading,
                receivedBytes: received,
                totalBytes: preset.sizeBytes,
              ));
            }
          }
        } finally {
          await sink.flush();
          await sink.close();
        }
      }

      update(ModelDownloadState(
        phase: ModelDownloadPhase.verifying,
        receivedBytes: received,
        totalBytes: preset.sizeBytes,
      ));
      final size = await part.length();
      if (size != preset.sizeBytes) {
        throw Exception('Size mismatch: $size of ${preset.sizeBytes} bytes');
      }
      final digest = await sha256OfFile(part.path);
      if (digest != preset.sha256) {
        await part.delete();
        throw Exception('Checksum mismatch; the partial file was removed');
      }
      if (await target.exists()) await target.delete();
      await part.rename(target.path);
      _downloads.remove(preset.id);
      _logger.info('Translation model downloaded',
          tag: 'TranslationModels', metadata: {'file': preset.fileName});
      notifyListeners();
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        _downloads.remove(preset.id);
        notifyListeners();
        return;
      }
      _logger.warning('Translation model download failed',
          tag: 'TranslationModels', error: e);
      update(ModelDownloadState(
        phase: ModelDownloadPhase.failed,
        receivedBytes: received,
        totalBytes: preset.sizeBytes,
        error: e.message ?? e.type.name,
      ));
    } catch (e) {
      _logger.warning('Translation model download failed',
          tag: 'TranslationModels', error: e);
      update(ModelDownloadState(
        phase: ModelDownloadPhase.failed,
        receivedBytes: received,
        totalBytes: preset.sizeBytes,
        error: e.toString(),
      ));
    } finally {
      _cancelTokens.remove(preset.id);
    }
  }

  /// Stops a running download. The partial file stays, so the next
  /// download resumes from it.
  void cancelDownload(String presetId) {
    _cancelTokens[presetId]?.cancel();
  }

  /// Copies a model file the user picked into the model directory.
  /// Returns the installed model, or throws when the file is not a
  /// `.litertlm` / `.gguf` model.
  Future<InstalledModel> importFile(String sourcePath) async {
    final name = p.basename(sourcePath);
    final runtime = runtimeForFile(name);
    if (runtime == null) {
      throw ArgumentError('Not a .litertlm or .gguf model file: $name');
    }
    final dir = await directoryProvider();
    final target = p.join(dir.path, name);
    final temp = File('$target.part');
    await File(sourcePath).copy(temp.path);
    final out = File(target);
    if (await out.exists()) await out.delete();
    await temp.rename(target);
    notifyListeners();
    return InstalledModel(
      fileName: name,
      path: target,
      sizeBytes: await out.length(),
      runtime: runtime,
    );
  }

  Future<void> delete(String fileName) async {
    final dir = await directoryProvider();
    for (final path in [
      p.join(dir.path, fileName),
      p.join(dir.path, '$fileName.part')
    ]) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    notifyListeners();
  }
}

/// SHA-256 of a file, computed off the UI isolate (a 2.6 GB model takes
/// a while to hash on a phone).
Future<String> sha256OfFile(String path) => Isolate.run(() async {
      final digest = await sha256.bind(File(path).openRead()).first;
      return digest.toString();
    });
