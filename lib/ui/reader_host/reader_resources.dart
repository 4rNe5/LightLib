// What the reader's page is served: the page itself, the book and font
// files, the word tools' dictionary - from one origin, so the page can
// fetch them.

// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// Project imports:
import 'package:openlib/services/storage/app_files.dart';
import 'package:openlib/services/study/japanese_tools.dart';

/// What the reader serves to the page, by path.
@immutable
class ReaderResource {
  const ReaderResource(this.contentType, this.bytes);
  final String contentType;
  final Uint8List bytes;
}

/// Serves the reader page, the book and font files to the web view from
/// one origin, so the page can fetch them (Android intercepts an https
/// origin, Apple platforms a custom scheme).
class ReaderResources {
  ReaderResources(
      {required this.bookPath, AssetBundle? bundle, JapaneseTools? tools})
      : _bundle = bundle ?? rootBundle,
        _tools = tools ?? JapaneseTools.instance;

  final String bookPath;
  final AssetBundle _bundle;
  final JapaneseTools _tools;
  final Map<String, File> _fonts = {};

  static const androidOrigin = 'https://appassets.androidplatform.net';
  static const appleScheme = 'lightlib';
  static const appleOrigin = '$appleScheme://reader';

  /// The page's origin; on the web the page is a file of the site itself.
  static String get origin => kIsWeb
      ? ''
      : Platform.isAndroid
          ? '$androidOrigin/reader'
          : appleOrigin;

  /// Makes [file] loadable at the returned URL.
  String addFont(File file) {
    final key = 'f${_fonts.length}${_extensionOf(file.path)}';
    _fonts[key] = file;
    return '$origin/fonts/$key';
  }

  static String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    return dot < 0 ? '' : path.substring(dot).toLowerCase();
  }

  static String _typeOf(String path) {
    switch (_extensionOf(path)) {
      case '.html':
        return 'text/html';
      case '.js':
        return 'text/javascript';
      case '.css':
        return 'text/css';
      case '.otf':
        return 'font/otf';
      case '.ttf':
        return 'font/ttf';
      case '.woff2':
        return 'font/woff2';
      default:
        return 'application/octet-stream';
    }
  }

  /// The resource at [uri], or null for anything else.
  Future<ReaderResource?> resolve(Uri uri) async {
    var path = uri.path;
    if (path.startsWith('/reader/')) path = path.substring('/reader'.length);
    if (path == '/' || path.isEmpty) path = '/index.html';
    try {
      if (path == '/book') {
        final bytes = await AppFiles.instance.readBytes(bookPath);
        return bytes == null
            ? null
            : ReaderResource('application/epub+zip', bytes);
      }
      if (path.startsWith('/fonts/')) {
        final file = _fonts[path.substring('/fonts/'.length)];
        if (file == null) return null;
        return ReaderResource(_typeOf(file.path), await file.readAsBytes());
      }
      if (path == '/index.html' || path == '/reader.js') {
        final data = await _bundle.load('assets/reader$path');
        return ReaderResource(_typeOf(path), data.buffer.asUint8List());
      }
      // The word tools' dictionary (downloaded) and the study lists.
      if (path.startsWith('/dict/')) {
        final bytes = await _tools.read(path.substring('/dict/'.length));
        return bytes == null
            ? null
            : ReaderResource('application/octet-stream', bytes);
      }
      if (path == '/study/jlpt.tsv') {
        final data = await _bundle.load('assets/study/jlpt.tsv');
        return ReaderResource(
            'text/tab-separated-values', data.buffer.asUint8List());
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}
