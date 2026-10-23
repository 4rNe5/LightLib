// The sheet that answers "Add to my library": the download is under way,
// or why it could not start. Same shape as the app's other sheets
// (rounded, drag handle, surface tones).

// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/ui/components/library_tiles.dart'
    show modernSurfaceTheme;

Future<void> showDownloadOutcomeSheet(
  BuildContext context, {
  required bool success,
  required String title,
  required String message,
  String? bookTitle,
  String? badge,
}) {
  return showModalBottomSheet<void>(
    context: context,
    // Sized to its content, scrolling on a small screen or large text.
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor:
        modernSurfaceTheme(Theme.of(context)).colorScheme.surfaceContainerLow,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (sheetContext) => Theme(
      data: modernSurfaceTheme(Theme.of(sheetContext)),
      child: DownloadOutcomeSheet(
        success: success,
        title: title,
        message: message,
        bookTitle: bookTitle,
        badge: badge,
      ),
    ),
  );
}

class DownloadOutcomeSheet extends StatelessWidget {
  const DownloadOutcomeSheet({
    super.key,
    required this.success,
    required this.title,
    required this.message,
    this.bookTitle,
    this.badge,
  });

  final bool success;
  final String title;
  final String message;
  final String? bookTitle;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tone = success ? scheme.primary : scheme.error;
    return SingleChildScrollView(
      key: ValueKey(success ? 'downloadStartedSheet' : 'downloadFailedSheet'),
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.6, end: 1),
              duration: const Duration(milliseconds: 360),
              curve: Curves.easeOutBack,
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: tone.withAlpha(30),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  success
                      ? Icons.download_done_rounded
                      : Icons.error_outline_rounded,
                  size: 32,
                  color: tone,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (bookTitle != null && bookTitle!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              bookTitle!,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
            ),
          ],
          if (badge != null) ...[
            const SizedBox(height: 10),
            Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: scheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bolt_rounded,
                        size: 14, color: scheme.onTertiaryContainer),
                    const SizedBox(width: 4),
                    Text(badge!,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: scheme.onTertiaryContainer)),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withAlpha(140),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              message,
              textAlign: success ? TextAlign.center : TextAlign.start,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(
            key: const ValueKey('downloadOutcomeOk'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(success ? l10n.ok : l10n.close),
          ),
        ],
      ),
    );
  }
}
