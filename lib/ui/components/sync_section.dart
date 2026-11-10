// Settings: sync with the owner's Supabase project (sign-in, run now,
// automatic runs, what the last run did). Shown in the app's settings and
// on the web.

// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/sync/sync_service.dart';

class SyncSection extends StatefulWidget {
  const SyncSection({super.key, this.service});

  /// Tests pass their own.
  final SyncService? service;

  @override
  State<SyncSection> createState() => _SyncSectionState();
}

class _SyncSectionState extends State<SyncSection> {
  SyncService get _sync => widget.service ?? SyncService.instance;

  String _time(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.month}/${t.day} ${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final small =
        TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant);
    return ListenableBuilder(
      listenable: _sync,
      builder: (context, _) {
        final user = _sync.user;
        final report = _sync.lastReport;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.syncTitle, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(l10n.syncHint, style: small),
            const SizedBox(height: 10),
            if (!_sync.ready && _sync.lastError != null)
              Text(l10n.syncUnavailable, style: small)
            else if (user == null)
              ElevatedButton.icon(
                key: const ValueKey('syncSignIn'),
                onPressed: _sync.ready ? _sync.signIn : null,
                icon: const Icon(Icons.login),
                label: Text(l10n.syncSignIn),
              )
            else ...[
              Text(l10n.syncSignedInAs(user.email ?? user.id)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    key: const ValueKey('syncNow'),
                    onPressed: _sync.running ? null : _sync.syncNow,
                    icon: _sync.running
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.sync),
                    label:
                        Text(_sync.running ? l10n.syncRunning : l10n.syncNow),
                  ),
                  TextButton(
                    onPressed: _sync.signOut,
                    child: Text(l10n.syncSignOut),
                  ),
                ],
              ),
              SwitchListTile(
                key: const ValueKey('syncAuto'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.syncAuto),
                subtitle: Text(l10n.syncAutoHint, style: small),
                value: _sync.auto,
                onChanged: _sync.setAuto,
              ),
              if (report != null && _sync.lastRun != null)
                Text(
                  l10n.syncLast(
                    _time(_sync.lastRun!),
                    report.uploaded,
                    report.downloaded,
                    report.positionsSent,
                    report.positionsReceived,
                    report.translationsSent,
                    report.translationsReceived,
                  ),
                  style: small,
                ),
              if (report != null && report.skippedForSpace > 0)
                Text(l10n.syncNoSpace(report.skippedForSpace), style: small),
              if (report != null && report.deletesHeld > 0)
                Text(l10n.syncDeletesHeld(report.deletesHeld),
                    style: small.copyWith(color: theme.colorScheme.error)),
              if (_sync.lastError != null)
                Text(l10n.syncFailed(_sync.lastError!),
                    style: small.copyWith(color: theme.colorScheme.error)),
            ],
          ],
        );
      },
    );
  }
}
