// A book's cover in the web library: the small one kept in this browser,
// made from the book's own when it was added here, fetched from the
// account, or - when no device has put one there yet - read out of the
// book's file on the account without fetching the book. Drawn at the size
// it is shown (a full cover decoded for every tile is tens of megabytes
// each).

// Dart imports:
import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:openlib/services/cover_thumbs.dart';
import 'package:openlib/services/epub_remote_cover.dart';
import 'package:openlib/services/local_book_import.dart'
    show isLocalImagePath, localImageFilePath;
import 'package:openlib/services/storage/app_files.dart';
import 'package:openlib/services/sync/sync_engine.dart';
import 'package:openlib/services/sync/sync_service.dart';
import 'package:openlib/web/web_library.dart';

/// Covers already read (their bytes; the decoded pictures are Flutter's
/// image cache's business), and the reads under way.
class WebCovers {
  static const _kept = 400;
  static final LinkedHashMap<String, Uint8List?> _bytes = LinkedHashMap();
  static final Map<String, Future<Uint8List?>> _reading = {};
  static int _fetching = 0;
  static final List<Completer<void>> _waiting = [];

  /// Tests answer for the account, or for the whole lookup.
  @visibleForTesting
  static Future<Uint8List?> Function(String md5)? fetchOverride;
  @visibleForTesting
  static Future<Uint8List?> Function(WebBook book)? readOverride;

  /// Tests answer for the cover inside a book's file (full size), and
  /// hear what is kept for the other devices.
  @visibleForTesting
  static Future<RemoteEpubCard?> Function(RemoteBook book)? fileOverride;
  @visibleForTesting
  static Future<void> Function(RemoteBook book, Uint8List? jpeg)? keepOverride;

  static String _key(WebBook book) =>
      '${book.key}|${book.remote?.hasCover == true}|${book.local?.thumbnail ?? ''}';

  /// The cover if it was read before (no waiting, no flicker).
  static Uint8List? known(WebBook book) => _bytes[_key(book)];
  static bool isKnown(WebBook book) => _bytes.containsKey(_key(book));

  static Future<Uint8List?> of(WebBook book) {
    final key = _key(book);
    if (_bytes.containsKey(key)) return Future.value(_bytes[key]);
    return _reading[key] ??= (readOverride ?? _read)(book).then((bytes) {
      _reading.remove(key);
      _bytes[key] = bytes;
      while (_bytes.length > _kept) {
        _bytes.remove(_bytes.keys.first);
      }
      return bytes;
    });
  }

  static Future<Uint8List?> _read(WebBook book) async {
    try {
      final md5 = book.md5;
      if (md5 != null) {
        final kept = await CoverThumbs.read(md5);
        if (kept != null) return kept;
      }
      // Added here by an earlier version: the full cover, made small once.
      final thumb = book.local?.thumbnail ?? '';
      if (isLocalImagePath(thumb)) {
        final full =
            await AppFiles.instance.readBytes(localImageFilePath(thumb));
        if (full != null) {
          final small = CoverThumbs.isThumb(thumb)
              ? full
              : await CoverThumbs.jpeg(full) ?? full;
          if (md5 != null && !CoverThumbs.isThumb(thumb)) {
            await CoverThumbs.write(md5, small);
          }
          return small;
        }
      }
      final remote = book.remote;
      if (md5 != null && remote != null && remote.hasCover) {
        final got = await _gated(
            () => (fetchOverride ?? SyncService.instance.cover)(md5));
        if (got != null) {
          await CoverThumbs.write(md5, got);
          return got;
        }
      }
      // No device has put a small cover yet: the picture is read out of
      // the book's file on the account (that part of the file only), and
      // kept for the other devices.
      if (md5 != null && remote != null && remote.hasFile) {
        return await _gated(() => _fromFile(remote));
      }
    } catch (_) {}
    return null;
  }

  static Future<Uint8List?> _fromFile(RemoteBook remote) async {
    final card =
        await (fileOverride ?? SyncService.instance.cardFromFile)(remote);
    if (card == null) return null;
    final cover = card.cover;
    final small = cover == null ? null : await CoverThumbs.jpeg(cover.bytes);
    if (small != null) await CoverThumbs.write(remote.md5, small);
    final keep = keepOverride;
    unawaited(keep != null
        ? keep(remote, small)
        : SyncService.instance.putCard(remote, small,
            publisher: card.publisher, description: card.description));
    return small;
  }

  /// A few at a time: a long library does not ask for every cover at once.
  static Future<T> _gated<T>(Future<T> Function() work) async {
    while (_fetching >= 4) {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    }
    _fetching++;
    try {
      return await work();
    } finally {
      _fetching--;
      if (_waiting.isNotEmpty) _waiting.removeAt(0).complete();
    }
  }

  @visibleForTesting
  static void forget() {
    _bytes.clear();
    _reading.clear();
  }
}

class WebCover extends StatefulWidget {
  const WebCover({super.key, required this.book, this.radius = 10});

  final WebBook book;
  final double radius;

  @override
  State<WebCover> createState() => _WebCoverState();
}

class _WebCoverState extends State<WebCover> {
  Uint8List? _bytes;
  bool _settled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(WebCover old) {
    super.didUpdateWidget(old);
    if (WebCovers._key(old.book) != WebCovers._key(widget.book)) _load();
  }

  void _load() {
    final book = widget.book;
    if (WebCovers.isKnown(book)) {
      _bytes = WebCovers.known(book);
      _settled = true;
      return;
    }
    _settled = false;
    unawaited(WebCovers.of(book).then((bytes) {
      if (!mounted || WebCovers._key(widget.book) != WebCovers._key(book)) {
        return;
      }
      setState(() {
        _bytes = bytes;
        _settled = true;
      });
    }));
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: LayoutBuilder(builder: (context, box) {
        final placeholder = _Placeholder(
            title: widget.book.title, quiet: !_settled, radius: widget.radius);
        if (bytes == null) return placeholder;
        final width = box.maxWidth.isFinite ? box.maxWidth : 200.0;
        final pixels = (width * MediaQuery.devicePixelRatioOf(context)).round();
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          // Decoded no larger than shown (in steps, so a resize does not
          // decode again at every width).
          cacheWidth: ((pixels / 120).ceil() * 120).clamp(120, coverThumbWidth),
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => placeholder,
        );
      }),
    );
  }
}

/// A book without a picture: its title on a quiet colour of its own.
class _Placeholder extends StatelessWidget {
  const _Placeholder(
      {required this.title, required this.quiet, required this.radius});

  final String title;
  final bool quiet;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hue = (title.hashCode % 360).toDouble();
    final color = quiet
        ? scheme.tertiaryContainer
        : HSLColor.fromAHSL(1, hue, 0.28, dark ? 0.24 : 0.86).toColor();
    return Container(
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: scheme.outlineVariant.withAlpha(120)),
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      child: quiet
          ? null
          : Text(title,
              textAlign: TextAlign.center,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface.withAlpha(190))),
    );
  }
}
