// Settings: sync with the owner's Supabase project (sign-in, run now,
// automatic runs, what the last run did). Shown in the app's settings and
// on the web.

// Flutter imports:
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/sync/sync_engine.dart';
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

  /// How many of the held-back books are named.
  static const _heldShown = 12;

  String _time(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.month}/${t.day} ${two(t.hour)}:${two(t.minute)}';
  }

  /// The books a run held back are deleted everywhere only after the
  /// reader says so again: it cannot be undone.
  Future<void> _deleteHeld(int count) async {
    final l10n = AppLocalizations.of(context);
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.syncHeldDelete),
        content: Text(l10n.syncHeldDeleteConfirm(count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const ValueKey('syncHeldDeleteSure'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (sure == true) await _sync.answerHeld(HeldDeletes.deleteThere);
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
            else if (user == null) ...[
              ElevatedButton.icon(
                key: const ValueKey('syncSignIn'),
                onPressed: _sync.ready ? _sync.signIn : null,
                icon: const Icon(Icons.login),
                label: Text(l10n.syncSignIn),
              ),
              // Why the last try did not sign in.
              if (_sync.lastError != null) ...[
                const SizedBox(height: 6),
                Text(l10n.syncFailed(_sync.lastError!),
                    style: small.copyWith(color: theme.colorScheme.error)),
              ],
            ] else ...[
              Text(l10n.syncSignedInAs(user.email ?? user.id)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    key: const ValueKey('syncNow'),
                    onPressed: _sync.running ? null : _sync.syncByHand,
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
              if (_sync.progress case final progress?) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  key: const ValueKey('syncProgress'),
                  value: progress.total > 0
                      ? progress.done / progress.total
                      : null,
                ),
                const SizedBox(height: 4),
                Text(syncProgressText(l10n, progress), style: small),
              ],
              SwitchListTile(
                key: const ValueKey('syncAuto'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.syncAuto),
                subtitle: Text(l10n.syncAutoHint, style: small),
                value: _sync.auto,
                onChanged: _sync.setAuto,
              ),
              SwitchListTile(
                key: const ValueKey('syncGeminiKey'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.syncGeminiKey),
                subtitle: Text(l10n.syncGeminiKeyHint, style: small),
                value: _sync.keySync,
                onChanged: _sync.setKeySync,
              ),
              // (Claude translates on devices only.)
              if (!kIsWeb)
                SwitchListTile(
                  key: const ValueKey('syncClaudeKey'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.syncClaudeKey),
                  subtitle: Text(l10n.syncClaudeKeyHint, style: small),
                  value: _sync.claudeKeySync,
                  onChanged: _sync.setClaudeKeySync,
                ),
              if (report != null && _sync.lastRun != null)
                Text(
                  l10n.syncLast(
                      _time(_sync.lastRun!), syncSummaryText(l10n, report)),
                  style: small,
                ),
              if (report != null && report.skippedForSpace > 0)
                Text(l10n.syncNoSpace(report.skippedForSpace), style: small),
              if (report != null && report.deletesHeld > 0) ...[
                Text(l10n.syncDeletesHeld(report.deletesHeld),
                    style: small.copyWith(color: theme.colorScheme.error)),
                // Which ones, so that the answer below is an informed one.
                for (final title in report.heldTitles.take(_heldShown))
                  Text('· $title',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: small),
                if (report.heldTitles.length > _heldShown)
                  Text('· …', style: small),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      key: const ValueKey('syncHeldFetch'),
                      onPressed: _sync.running
                          ? null
                          : () => _sync.answerHeld(HeldDeletes.fetchBack),
                      child: Text(l10n.syncHeldFetch),
                    ),
                    TextButton(
                      key: const ValueKey('syncHeldDelete'),
                      onPressed: _sync.running
                          ? null
                          : () => _deleteHeld(report.deletesHeld),
                      child: Text(l10n.syncHeldDelete,
                          style: TextStyle(color: theme.colorScheme.error)),
                    ),
                  ],
                ),
              ],
              if (report != null && report.unreadable.isNotEmpty)
                Text(syncUnreadableText(l10n, report)!,
                    key: const ValueKey('syncUnreadable'),
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
