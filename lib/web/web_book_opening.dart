// Opening a book on the web: its cover, its name and how far the file is
// while it is fetched (the account keeps the file; this browser gets it
// when the book is opened), then the reader in its place.

// Dart imports:
import 'dart:async';
import 'dart:typed_data';

// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/files.dart' show webBookStorageDirectory;
import 'package:openlib/services/sync/sync_service.dart';
import 'package:openlib/ui/book_reader_page.dart';
import 'package:openlib/web/web_cover.dart';
import 'package:openlib/web/web_library.dart';

/// The picture shown while a book comes: cover, title, what is happening.
class WebBookOpening extends StatelessWidget {
  const WebBookOpening({
    super.key,
    required this.book,
    required this.label,
    this.progress,
    this.detail,
    this.error = false,
    this.onRetry,
    this.onClose,
  });

  final WebBook book;
  final String label;

  /// 0..1 while the file is fetched; null: no bar's length is known.
  final double? progress;

  /// "3.1 / 8.4 MB".
  final String? detail;
  final bool error;
  final VoidCallback? onRetry;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final muted = scheme.onSurface.withAlpha(150);
    final Uint8List? cover = WebCovers.known(book);
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The cover, out of focus, as the room's light: a few dozen
          // pixels of it stretched over the window (a blur filter would be
          // redone for every frame the bar below moves, on the thread the
          // book is being opened on).
          if (cover != null)
            RepaintBoundary(
              child: Image.memory(cover,
                  fit: BoxFit.cover,
                  cacheWidth: 20,
                  opacity: const AlwaysStoppedAnimation(0.42),
                  filterQuality: FilterQuality.high,
                  gaplessPlayback: true),
            ),
          ColoredBox(color: theme.scaffoldBackgroundColor.withAlpha(150)),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 188,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withAlpha(70),
                              blurRadius: 36,
                              offset: const Offset(0, 18)),
                        ],
                      ),
                      child: AspectRatio(
                        aspectRatio: 0.7,
                        child: WebCover(book: book, radius: 12),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(book.title,
                        key: const ValueKey('webOpeningTitle'),
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 20,
                            height: 1.3,
                            fontWeight: FontWeight.w700)),
                    if (book.author.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(book.author,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, color: muted)),
                    ],
                    const SizedBox(height: 26),
                    if (!error)
                      SizedBox(
                        width: 220,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            key: const ValueKey('webOpeningBar'),
                            value: progress,
                            minHeight: 4,
                            color: scheme.secondary,
                            backgroundColor: scheme.onSurface.withAlpha(28),
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                    Text(label,
                        key: const ValueKey('webOpeningLabel'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 14,
                            color: error ? scheme.error : muted,
                            fontWeight: FontWeight.w600)),
                    if (detail != null) ...[
                      const SizedBox(height: 4),
                      Text(detail!,
                          style: TextStyle(
                              fontSize: 12,
                              color: muted,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ])),
                    ],
                    if (error) ...[
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 10,
                        children: [
                          if (onRetry != null)
                            ElevatedButton(
                                key: const ValueKey('webOpeningRetry'),
                                onPressed: onRetry,
                                child: Text(l10n.webRetry)),
                          TextButton(
                              onPressed: onClose,
                              style: TextButton.styleFrom(
                                  foregroundColor: scheme.onSurface),
                              child: Text(l10n.webClose)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (onClose != null)
            Positioned(
              top: 12,
              left: 12,
              child: SafeArea(
                child: IconButton(
                  key: const ValueKey('webOpeningClose'),
                  tooltip: l10n.webClose,
                  onPressed: onClose,
                  icon: const Icon(Icons.arrow_back),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Fetches the book when this browser does not have it, then hands over
/// to the reader (which keeps the same picture up until the page shows).
class WebBookOpenPage extends StatefulWidget {
  const WebBookOpenPage({super.key, required this.book, this.sync});

  final WebBook book;

  /// Tests pass their own.
  final SyncService? sync;

  static Route<void> route(WebBook book) => PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => WebBookOpenPage(book: book),
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 160),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      );

  @override
  State<WebBookOpenPage> createState() => _WebBookOpenPageState();
}

class _WebBookOpenPageState extends State<WebBookOpenPage> {
  int _received = 0;
  int? _total;
  bool _fetching = false;
  bool _handedOver = false;
  String? _error;
  DateTime _painted = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    final book = widget.book;
    var fileName = book.local?.getFileName();
    if (fileName == null) {
      setState(() {
        _error = null;
        _fetching = true;
        _received = 0;
        _total = book.sizeBytes;
      });
      try {
        final added = await (widget.sync ?? SyncService.instance)
            .fetchBook(book.remote!, onProgress: _heard);
        if (added == null) throw StateError('not added');
        fileName = added.fileName;
      } catch (e) {
        if (mounted) {
          setState(() {
            _fetching = false;
            _error = '$e';
          });
        }
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _fetching = false;
      _handedOver = true;
    });
    final name = fileName;
    final navigator = Navigator.of(context);
    // The reader takes this page's place with the same picture up, so
    // nothing blinks between the two.
    unawaited(navigator.pushReplacement(PageRouteBuilder<void>(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (_, __, ___) => BookReaderPage(
        fileName: name,
        filePath: '$webBookStorageDirectory/$name',
        opening: (context) => WebBookOpening(
          book: book,
          label: AppLocalizations.of(context).webOpeningBook,
          // A full, still bar: anything moving over the book's page is
          // drawn on the thread the page opens the book on (a running bar
          // made a 3-second opening take 12).
          progress: 1,
          onClose: () => Navigator.of(context).maybePop(),
        ),
      ),
    )));
  }

  void _heard(int received, int? total) {
    _received = received;
    _total = total ?? _total;
    // A few times a second is plenty.
    final now = DateTime.now();
    if (!mounted || now.difference(_painted).inMilliseconds < 160) return;
    _painted = now;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final total = _total;
    final failed = _error != null;
    return WebBookOpening(
      book: widget.book,
      label: failed
          ? l10n.webLoadFailed
          : _fetching
              ? l10n.webDownloadingBook
              : l10n.webOpeningBook,
      progress: _handedOver
          ? 1
          : _fetching && total != null && total > 0
              ? (_received / total).clamp(0, 1).toDouble()
              : null,
      detail: _fetching && _received > 0
          ? total != null && total > 0
              ? '${formatBytes(_received)} / ${formatBytes(total)}'
              : formatBytes(_received)
          : null,
      error: failed,
      onRetry: failed ? () => unawaited(_open()) : null,
      onClose: () => Navigator.of(context).maybePop(),
    );
  }
}
