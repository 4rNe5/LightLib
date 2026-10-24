// The app's update history: the GitHub releases of 4rNe5/LightLib, newest
// first, each build's changes, the installed one marked, and the update
// offered when a newer build exists.

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/app_release.dart';
import 'package:openlib/services/update_checker.dart';
import 'package:openlib/ui/components/library_tiles.dart'
    show modernSurfaceTheme;

class ReleaseHistoryPage extends StatefulWidget {
  const ReleaseHistoryPage({super.key, this.checker});

  final UpdateCheckerService? checker;

  @override
  State<ReleaseHistoryPage> createState() => _ReleaseHistoryPageState();
}

class _ReleaseHistoryPageState extends State<ReleaseHistoryPage> {
  late final UpdateCheckerService _checker =
      widget.checker ?? UpdateCheckerService();
  late Future<(AppBuild, List<ReleaseInfo>)> _load = _fetch();

  Future<(AppBuild, List<ReleaseInfo>)> _fetch({bool refresh = false}) async {
    final current = await UpdateCheckerService.currentBuild();
    final releases = await _checker.fetchReleases(refresh: refresh);
    return (current, releases.where((r) => r.build != null).toList());
  }

  Future<void> _refresh() async {
    final next = _fetch(refresh: true);
    setState(() => _load = next);
    await next.catchError((_) => (const AppBuild(0, 0, 0), <ReleaseInfo>[]));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Theme(
      data: modernSurfaceTheme(Theme.of(context)),
      child: Builder(builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return Scaffold(
          backgroundColor: scheme.surface,
          appBar: AppBar(
            title: Text(l10n.releaseHistoryTitle),
            backgroundColor: scheme.surface,
            actions: [
              IconButton(
                tooltip: l10n.updateViewOnGithub,
                icon: const Icon(Icons.open_in_new_rounded),
                onPressed: () => launchUrl(
                    Uri.parse(UpdateCheckerService.releasesPage),
                    mode: LaunchMode.externalApplication),
              ),
            ],
          ),
          body: FutureBuilder<(AppBuild, List<ReleaseInfo>)>(
            future: _load,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError || snap.data == null) {
                return _Message(
                  icon: Icons.cloud_off_rounded,
                  text: l10n.releaseHistoryFailed,
                  action: FilledButton.tonal(
                      onPressed: _refresh, child: Text(l10n.retry)),
                );
              }
              final (current, releases) = snap.data!;
              if (releases.isEmpty) {
                return _Message(
                    icon: Icons.history_rounded, text: l10n.updateNoNotes);
              }
              final newest = releases.first;
              final newer = newest.build! > current;
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount: releases.length + (newer ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (newer && i == 0) {
                      return _UpdateBanner(
                        release: newest,
                        onUpdate: () =>
                            _checker.showUpdateDialog(context, newest),
                      );
                    }
                    final r = releases[i - (newer ? 1 : 0)];
                    return _ReleaseCard(
                      release: r,
                      current: r.build == current,
                      latest: identical(r, newest),
                    );
                  },
                ),
              );
            },
          ),
        );
      }),
    );
  }
}

class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner({required this.release, required this.onUpdate});

  final ReleaseInfo release;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('releaseUpdateBanner'),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(Icons.system_update_rounded, color: scheme.onPrimaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.updateAvailableTitle,
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: scheme.onPrimaryContainer)),
                Text(release.label,
                    style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onPrimaryContainer.withAlpha(200))),
              ],
            ),
          ),
          FilledButton(onPressed: onUpdate, child: Text(l10n.updateAction)),
        ],
      ),
    );
  }
}

class _ReleaseCard extends StatelessWidget {
  const _ReleaseCard(
      {required this.release, required this.current, required this.latest});

  final ReleaseInfo release;
  final bool current;
  final bool latest;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final changes = releaseChanges(release.body);
    final date = DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag())
        .add_Hm()
        .format(release.publishedAt.toLocal());

    Widget badge(String text, Color bg, Color fg) => Container(
          margin: const EdgeInsets.only(left: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration:
              BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
          child: Text(text,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w800, color: fg)),
        );

    return Container(
      key: ValueKey('release-${release.tagName}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: current ? scheme.secondaryContainer : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(release.label,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
              if (latest)
                badge(l10n.releaseLatest, scheme.primary, scheme.onPrimary),
              if (current)
                badge(l10n.releaseInstalled, scheme.tertiaryContainer,
                    scheme.onTertiaryContainer),
            ],
          ),
          const SizedBox(height: 2),
          Text(date,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          if (changes.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final c in changes)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6, right: 8),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                            color: scheme.primary, shape: BoxShape.circle),
                      ),
                    ),
                    Expanded(
                      child: Text(c,
                          style:
                              theme.textTheme.bodyMedium?.copyWith(height: 1.4)),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant)),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
