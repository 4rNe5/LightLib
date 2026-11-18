// The reader's Japanese word tools: kuromoji's IPADIC dictionary (about
// 18 MB), downloaded once when a study feature is first used and served
// to the reader page at /reader/dict/. Every file is checked against its
// published size and SHA-256 (kuromoji 0.1.2 on npm).

// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// Project imports:
import 'package:openlib/services/logger.dart';

@immutable
class ToolFile {
  const ToolFile(this.name, this.size, this.sha256);
  final String name;
  final int size;
  final String sha256;
}

/// kuromoji 0.1.2's dict/ (Apache-2.0; IPADIC by NAIST).
const kuromojiFiles = [
  ToolFile('base.dat.gz', 3956825,
      '0803327762e1c93ca731e4319ab8343340f2806bb84941207782cde9d2d5a8eb'),
  ToolFile('cc.dat.gz', 1692067,
      '02b7631be0d4de3a1a75cd9f9cc51536e4f94c9e6b389b813e06ba0f6e7de765'),
  ToolFile('check.dat.gz', 3111633,
      '193ae0035fff6fe812b58d9ee730e7a7d7ee601d918481ce51075c58114f6cc9'),
  ToolFile('tid.dat.gz', 1605820,
      'd43d831cb6fb0f0a411739cd287a6d5e998e121a8daca614df14a81a0dcac586'),
  ToolFile('tid_map.dat.gz', 1485576,
      '33efd5ffd87a70f669add093fa39dee44341d58f940844ef107c8fd98bb795b2'),
  ToolFile('tid_pos.dat.gz', 5916009,
      '60dbfc99a6ab993f30c5dab648bec6ad7f9aaefa5c14e1843837d95e509f8895'),
  ToolFile('unk.dat.gz', 10512,
      'f7f991cdeb9bfd3e9c0e4577cc50ee0815a11c508cccd444a9d3ab3c81521100'),
  ToolFile('unk_char.dat.gz', 306,
      '9a8e86fd9aff32d323fbb59f5a7006f05927a11f8173c90712cc56293aeb3225'),
  ToolFile('unk_compat.dat.gz', 338,
      '50f60aa29bc2e86c2903ab8c825bb6fa604d2b294d96941c1d3924259791899d'),
  ToolFile('unk_invoke.dat.gz', 1140,
      '6b210889548457c3006913afd12c8b525562255f2709e404604be9614a25e94c'),
  ToolFile('unk_map.dat.gz', 1190,
      '6df12460e5477230bb6fd9641def918b699fc0a8868016b6c9f794488630509b'),
  ToolFile('unk_pos.dat.gz', 10540,
      '5b183a29f281acc7e0542beca47b83f7985047c0a2d27e78a66f32276be5ad11'),
];

/// Where the files come from, tried in order.
const kuromojiMirrors = [
  'https://cdn.jsdelivr.net/npm/kuromoji@0.1.2/dict/',
  'https://unpkg.com/kuromoji@0.1.2/dict/',
];

final int kuromojiBytes = kuromojiFiles.fold(0, (a, f) => a + f.size);

enum ToolsPhase { missing, downloading, ready, failed }

class JapaneseTools extends ChangeNotifier {
  JapaneseTools({
    this.directory,
    this.dio,
    this.files = kuromojiFiles,
    this.mirrors = kuromojiMirrors,
  });

  static final JapaneseTools instance = JapaneseTools();

  /// Where the files are kept (replaceable in tests).
  Future<Directory> Function()? directory;
  Dio? dio;
  final List<ToolFile> files;
  final List<String> mirrors;
  int get totalBytes => files.fold(0, (a, f) => a + f.size);

  final AppLogger _logger = AppLogger();
  ToolsPhase _phase = ToolsPhase.missing;
  int _received = 0;
  String? error;
  bool _checked = false;

  ToolsPhase get phase => _phase;
  double get progress => totalBytes == 0 ? 0 : _received / totalBytes;

  Future<Directory> _dir() async {
    final dir = directory != null
        ? await directory!()
        : Directory(p.join(
            (await getApplicationSupportDirectory()).path, 'study', 'kuromoji'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Whether every file is there at its size (checked once a session;
  /// hashes were checked when they were downloaded).
  Future<bool> installed() async {
    // The web build has no word tools yet (the dictionary is files).
    if (kIsWeb) return false;
    if (_phase == ToolsPhase.ready) return true;
    if (_phase == ToolsPhase.downloading) return false;
    if (_checked && _phase != ToolsPhase.ready) return false;
    _checked = true;
    try {
      final dir = await _dir();
      for (final f in files) {
        final file = File(p.join(dir.path, f.name));
        if (!await file.exists() || await file.length() != f.size) {
          return false;
        }
      }
      _phase = ToolsPhase.ready;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// A dictionary file's bytes for the reader page, or null.
  Future<Uint8List?> read(String name) async {
    if (!files.any((f) => f.name == name)) return null;
    try {
      final file = File(p.join((await _dir()).path, name));
      return await file.exists() ? await file.readAsBytes() : null;
    } catch (_) {
      return null;
    }
  }

  Future<bool>? _download;

  /// Downloads what is missing; true when everything is in place.
  Future<bool> download() => _download ??= _run().whenComplete(() {
        _download = null;
      });

  Future<bool> _run() async {
    if (kIsWeb) {
      error = 'unsupported on the web';
      return false;
    }
    final client = dio ??
        Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(minutes: 2),
          responseType: ResponseType.bytes,
        ));
    _phase = ToolsPhase.downloading;
    error = null;
    _received = 0;
    notifyListeners();
    try {
      final dir = await _dir();
      for (final f in files) {
        final target = File(p.join(dir.path, f.name));
        if (await target.exists() && await target.length() == f.size) {
          _received += f.size;
          continue;
        }
        Uint8List? bytes;
        Object? last;
        for (final mirror in mirrors) {
          try {
            final r = await client.get<List<int>>('$mirror${f.name}',
                options: Options(responseType: ResponseType.bytes));
            final data = Uint8List.fromList(r.data ?? const []);
            if (data.length == f.size &&
                sha256.convert(data).toString() == f.sha256) {
              bytes = data;
              break;
            }
            last = 'checksum mismatch for ${f.name}';
          } catch (e) {
            last = e;
          }
        }
        if (bytes == null) throw Exception('${f.name}: $last');
        final part = File('${target.path}.part');
        await part.writeAsBytes(bytes, flush: true);
        await part.rename(target.path);
        _received += f.size;
        notifyListeners();
      }
      _phase = ToolsPhase.ready;
      _logger.info('Japanese tools downloaded', tag: 'Study');
      notifyListeners();
      return true;
    } catch (e) {
      _phase = ToolsPhase.failed;
      error = '$e';
      _logger.warning('Japanese tools not downloaded', tag: 'Study', error: e);
      notifyListeners();
      return false;
    }
  }

  /// Removes the files (settings).
  Future<void> remove() async {
    try {
      final dir = await _dir();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
    _phase = ToolsPhase.missing;
    _checked = false;
    notifyListeners();
  }

  @visibleForTesting
  void debugReset() {
    _phase = ToolsPhase.missing;
    _checked = false;
    _received = 0;
    error = null;
  }
}
