// On a library book's page: translate this book first, to the end, so it
// is ready to read later; its progress and why it waits, if it does.

// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/translation/book_translation_service.dart';
import 'package:openlib/services/translation/translated_epub.dart';
import 'package:openlib/services/translation/translation_cache.dart';
import 'package:openlib/services/translation/translation_engine.dart';
import 'package:openlib/ui/components/snack_bar_widget.dart';

class PriorityTranslationCard extends StatelessWidget {
  const PriorityTranslationCard(
      {super.key, required this.fileName, this.title = ''});

  /// The book's file in the library folder.
  final String fileName;

  /// The book's title, for the exported copy's name.
  final String title;

  Future<void> _start(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final engine =
        await TranslationEngines.cacheModelId().catchError((_) => null);
    if (engine == null) {
      if (context.mounted) {
        showSnackBar(context: context, message: l10n.priorityTranslateNoModel);
      }
      return;
    }
    // The progress notification needs the permission (Android 13+);
    // without it the work still runs.
    if (Platform.isAndroid) {
      await Permission.notification
          .request()
          .catchError((_) => PermissionStatus.denied);
    }
    await BookTranslationService.instance.prioritize(fileName);
  }

  Future<void> _clear(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l10n.translationClearBook),
        content: Text(l10n.translationClearBookConfirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(MaterialLocalizations.of(c).cancelButtonLabel)),
          FilledButton(
              key: const ValueKey('translationClearBookConfirm'),
              onPressed: () => Navigator.pop(c, true),
              child: Text(MaterialLocalizations.of(c).okButtonLabel)),
        ],
      ),
    );
    if (ok != true) return;
    final service = BookTranslationService.instance;
    if (service.priorityFile == fileName) await service.cancelPriority();
    await TranslationCache.deleteForBook(fileName).catchError((_) {});
    service.forgetBook(fileName);
    if (context.mounted) {
      showSnackBar(context: context, message: l10n.translationClearBookDone);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final service = BookTranslationService.instance;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final progress = service.progress[fileName];
        final first = service.priorityFile == fileName;
        final done = progress?.state == BookTranslationState.done;
        final small = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);

        final Widget body;
        if (first) {
          final known = progress != null && progress.total > 0;
          final waiting =
              service.currentFile == fileName ? service.waitText(l10n) : null;
          body = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.translate_rounded,
                      size: 18, color: scheme.secondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(l10n.priorityTranslating,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                  TextButton(
                    key: const ValueKey('priorityTranslateStop'),
                    onPressed: service.cancelPriority,
                    child: Text(l10n.translationNoticeStop),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: known ? progress.fraction : null,
                  minHeight: 5,
                  color: scheme.secondary,
                  backgroundColor: scheme.onSurface.withValues(alpha: 0.12),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                known
                    ? l10n.priorityTranslateProgress(progress.done,
                        progress.total, (progress.fraction * 100).floor())
                    : l10n.priorityTranslatePreparing,
                key: const ValueKey('priorityTranslateProgress'),
                style: small,
              ),
              if (waiting != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(waiting,
                      key: const ValueKey('priorityTranslateWait'),
                      style: small),
                ),
            ],
          );
        } else if (done) {
          body = Row(
            children: [
              Icon(Icons.check_circle_rounded,
                  size: 18, color: scheme.secondary),
              const SizedBox(width: 8),
              Text(l10n.priorityTranslateDone,
                  key: const ValueKey('priorityTranslateDone'),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
            ],
          );
        } else {
          body = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FilledButton.tonalIcon(
                key: const ValueKey('priorityTranslate'),
                onPressed: () => _start(context),
                icon: const Icon(Icons.translate_rounded, size: 18),
                label: Text(l10n.priorityTranslate),
              ),
              const SizedBox(height: 6),
              Text(l10n.priorityTranslateHint, style: small),
            ],
          );
        }
        final card = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            body,
            Wrap(
              alignment: WrapAlignment.end,
              children: [
                _ExportButton(fileName: fileName, title: title),
                TextButton.icon(
                  key: const ValueKey('translationClearBook'),
                  onPressed: () => _clear(context),
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: Text(l10n.translationClearBook),
                ),
              ],
            ),
          ],
        );
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 12),
          decoration: BoxDecoration(
            color: scheme.onSurface.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(14),
          ),
          child: card,
        );
      },
    );
  }
}

/// Makes the translated copy and opens the share sheet with it (save to
/// files, send, open in another reading app).
class _ExportButton extends StatefulWidget {
  const _ExportButton({required this.fileName, required this.title});
  final String fileName;
  final String title;

  @override
  State<_ExportButton> createState() => _ExportButtonState();
}

class _ExportButtonState extends State<_ExportButton> {
  bool _busy = false;

  Future<void> _export() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final out = await exportTranslatedEpub(
          fileName: widget.fileName,
          title: widget.title.isEmpty
              ? p.basenameWithoutExtension(widget.fileName)
              : widget.title);
      if (!mounted) return;
      final file = out.file;
      if (file == null) {
        showSnackBar(
            context: context,
            message: out.total == 0
                ? l10n.translationExportFailed
                : l10n.translationExportNone);
        return;
      }
      showSnackBar(
          context: context,
          message: l10n.translationExportDone(out.translated, out.total));
      await SharePlus.instance.share(ShareParams(
          files: [XFile(file.path, mimeType: 'application/epub+zip')]));
    } catch (_) {
      if (mounted) {
        showSnackBar(context: context, message: l10n.translationExportFailed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => TextButton.icon(
        key: const ValueKey('translationExport'),
        onPressed: _busy ? null : _export,
        icon: _busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.ios_share, size: 18),
        label: Text(AppLocalizations.of(context).translationExport),
      );
}
