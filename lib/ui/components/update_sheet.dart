// The update sheet: a new build of the app, what changed since the one
// installed, and download + install in place. A build already downloaded
// in the background opens on "Install now".

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/ui/components/library_tiles.dart'
    show modernSurfaceTheme;

typedef UpdateProgress = void Function(
    double progress, int downloaded, int total);

Future<void> showUpdateSheet(
  BuildContext context, {
  required String label,
  required String currentLabel,
  required String changes,
  required String pageUrl,
  int? sizeBytes,
  String? preparedPath,
  required Future<String?> Function(UpdateProgress onProgress, CancelToken cancel)
      download,
  required Future<bool> Function(String path) install,
  required Future<void> Function() onLater,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor:
        modernSurfaceTheme(Theme.of(context)).colorScheme.surfaceContainerLow,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (sheetContext) => Theme(
      data: modernSurfaceTheme(Theme.of(sheetContext)),
      child: UpdateSheet(
        label: label,
        currentLabel: currentLabel,
        changes: changes,
        pageUrl: pageUrl,
        sizeBytes: sizeBytes,
        preparedPath: preparedPath,
        download: download,
        install: install,
        onLater: onLater,
      ),
    ),
  );
}

enum _Stage { available, downloading, ready, failed }

class UpdateSheet extends StatefulWidget {
  const UpdateSheet({
    super.key,
    required this.label,
    required this.currentLabel,
    required this.changes,
    required this.pageUrl,
    this.sizeBytes,
    this.preparedPath,
    required this.download,
    required this.install,
    required this.onLater,
  });

  final String label;
  final String currentLabel;
  final String changes;
  final String pageUrl;
  final int? sizeBytes;
  final String? preparedPath;
  final Future<String?> Function(UpdateProgress onProgress, CancelToken cancel)
      download;
  final Future<bool> Function(String path) install;
  final Future<void> Function() onLater;

  @override
  State<UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<UpdateSheet> {
  late _Stage _stage =
      widget.preparedPath != null ? _Stage.ready : _Stage.available;
  late String? _path = widget.preparedPath;
  double _progress = 0;
  int _downloaded = 0;
  int _total = 0;
  CancelToken? _cancel;
  bool _installing = false;

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }

  Future<void> _download() async {
    final cancel = _cancel = CancelToken();
    setState(() {
      _stage = _Stage.downloading;
      _progress = 0;
    });
    try {
      final path = await widget.download((p, d, t) {
        if (!mounted) return;
        setState(() {
          _progress = p;
          _downloaded = d;
          _total = t;
        });
      }, cancel);
      if (!mounted) return;
      if (path == null) {
        setState(() => _stage = _Stage.available);
        return;
      }
      setState(() {
        _path = path;
        _stage = _Stage.ready;
      });
      await _install();
    } catch (_) {
      if (mounted) setState(() => _stage = _Stage.failed);
    }
  }

  Future<void> _install() async {
    final path = _path;
    if (path == null || _installing) return;
    setState(() => _installing = true);
    try {
      await widget.install(path);
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  static String _size(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ready = _stage == _Stage.ready;
    final failed = _stage == _Stage.failed;
    final tone = failed ? scheme.error : scheme.primary;

    return SingleChildScrollView(
      key: const ValueKey('updateSheet'),
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.6, end: 1),
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeOutBack,
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: tone.withAlpha(30),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  failed
                      ? Icons.error_outline_rounded
                      : ready
                          ? Icons.install_mobile_rounded
                          : Icons.system_update_rounded,
                  size: 32,
                  color: tone,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            ready ? l10n.updateReadyTitle : l10n.updateAvailableTitle,
            textAlign: TextAlign.center,
            style:
                theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.currentLabel,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: scheme.onPrimaryContainer.withAlpha(190))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(Icons.arrow_forward_rounded,
                        size: 14, color: scheme.onPrimaryContainer),
                  ),
                  Text(widget.label,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: scheme.onPrimaryContainer)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(l10n.updateChangesTitle,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 240),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withAlpha(140),
              borderRadius: BorderRadius.circular(16),
            ),
            child: widget.changes.trim().isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(l10n.updateNoNotes,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  )
                : Markdown(
                    data: widget.changes,
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(14),
                    styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                      h3: theme.textTheme.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                      p: theme.textTheme.bodySmall?.copyWith(height: 1.45),
                      listBullet: theme.textTheme.bodySmall,
                    ),
                  ),
          ),
          const SizedBox(height: 18),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _stage == _Stage.downloading
                ? Column(
                    key: const ValueKey('updateProgress'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: _total > 0 ? _progress : null,
                          minHeight: 8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                              _total > 0
                                  ? '${(_progress * 100).toStringAsFixed(0)}%'
                                  : l10n.updateDownloading,
                              style: theme.textTheme.labelLarge
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          const Spacer(),
                          if (_total > 0)
                            Text('${_size(_downloaded)} / ${_size(_total)}',
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: () {
                          _cancel?.cancel();
                          setState(() => _stage = _Stage.available);
                        },
                        child: Text(l10n.cancel),
                      ),
                    ],
                  )
                : Column(
                    key: ValueKey(_stage),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (failed) ...[
                        Text(l10n.updateDownloadFailed,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: scheme.error)),
                        const SizedBox(height: 10),
                      ],
                      FilledButton.icon(
                        key: const ValueKey('updatePrimary'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _installing
                            ? null
                            : ready
                                ? _install
                                : _download,
                        icon: _installing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : Icon(ready
                                ? Icons.install_mobile_rounded
                                : Icons.download_rounded),
                        label: Text(ready
                            ? l10n.updateInstallNow
                            : failed
                                ? l10n.retry
                                : widget.sizeBytes == null
                                    ? l10n.updateDownloadInstall
                                    : l10n.updateDownloadInstallSize(
                                        _size(widget.sizeBytes!))),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () async {
                              await widget.onLater();
                              if (context.mounted) Navigator.of(context).pop();
                            },
                            child: Text(l10n.updateLater),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () => launchUrl(Uri.parse(widget.pageUrl),
                                mode: LaunchMode.externalApplication),
                            icon: const Icon(Icons.open_in_new_rounded, size: 16),
                            label: Text(l10n.updateViewOnGithub),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
