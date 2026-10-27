// On a library book's page: translate this book first, to the end, so it
// is ready to read later; its progress and why it waits, if it does.

// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:permission_handler/permission_handler.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/translation/book_translation_service.dart';
import 'package:openlib/services/translation/translation_engine.dart';
import 'package:openlib/ui/components/snack_bar_widget.dart';

class PriorityTranslationCard extends StatelessWidget {
  const PriorityTranslationCard({super.key, required this.fileName});

  /// The book's file in the library folder.
  final String fileName;

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
          final waiting = service.currentFile == fileName
              ? service.waitText(l10n)
              : null;
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
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 12),
          decoration: BoxDecoration(
            color: scheme.onSurface.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(14),
          ),
          child: body,
        );
      },
    );
  }
}
