// The library's "Reading record" bento: finished-book checkpoints, the
// reading streak, four weeks of activity, this month, and the genre mix.

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/library_organization.dart';
import 'package:openlib/services/reading_recap.dart';
import 'package:openlib/ui/components/library_tiles.dart'
    show genreIcon, genreLabel;

/// Loads the recap and lays it out; nothing while loading or on error.
class LibraryRecapSection extends ConsumerWidget {
  const LibraryRecapSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recap = ref.watch(readingRecapProvider).valueOrNull;
    if (recap == null || recap.total == 0) return const SizedBox.shrink();
    return LibraryRecapBento(recap: recap);
  }
}

class LibraryRecapBento extends StatelessWidget {
  const LibraryRecapBento({super.key, required this.recap});

  final ReadingRecap recap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      key: const ValueKey('libraryRecap'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
          child: Text(l10n.recapTitle,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface)),
        ),
        LayoutBuilder(builder: (context, constraints) {
          const gap = 10.0;
          final unit = (constraints.maxWidth - 2 * gap) / 3;
          final rowHeight = (unit * 1.12).clamp(118.0, 156.0);
          Widget row(Widget wide, Widget narrow) => SizedBox(
                height: rowHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: unit * 2 + gap, child: wide),
                    const SizedBox(width: gap),
                    Expanded(child: narrow),
                  ],
                ),
              );
          return Column(
            children: [
              row(_MilestoneCard(recap: recap), _StreakCard(recap: recap)),
              const SizedBox(height: gap),
              row(_ActivityCard(recap: recap), _MonthCard(recap: recap)),
              if (recap.genres.isNotEmpty) ...[
                const SizedBox(height: gap),
                _GenreMixCard(recap: recap),
              ],
            ],
          );
        }),
      ],
    );
  }
}

/// Shared card shell.
class _Card extends StatelessWidget {
  const _Card({required this.child, this.color, this.cardKey});

  final Widget child;
  final Color? color;
  final Key? cardKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: cardKey,
      decoration: BoxDecoration(
        color: color ?? Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(12),
      child: child,
    );
  }
}

class _CardLabel extends StatelessWidget {
  const _CardLabel(this.icon, this.text, {this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(icon, size: 15, color: fg),
        const SizedBox(width: 5),
        Expanded(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w700, color: fg)),
        ),
      ],
    );
  }
}

/// A number that counts up once when shown (static with reduced motion).
class _CountUp extends StatelessWidget {
  const _CountUp(this.value, {required this.style, this.suffix = ''});

  final int value;
  final TextStyle style;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce || value == 0) return Text('$value$suffix', style: style);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text('${v.round()}$suffix', style: style),
    );
  }
}

/// Finished books and the next checkpoint, with a progress ring and the
/// checkpoints around the current one.
class _MilestoneCard extends StatelessWidget {
  const _MilestoneCard({required this.recap});

  final ReadingRecap recap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final m = recap.milestone;
    final progress = m.progress(recap.completed);
    final fg = scheme.onPrimaryContainer;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    // Four checkpoints around the next one.
    const shownCount = 4;
    final nextIndex = m.next == null
        ? readingMilestones.length
        : readingMilestones.indexOf(m.next!);
    final first =
        (nextIndex - 1).clamp(0, readingMilestones.length - shownCount);
    final shown = readingMilestones.sublist(first, first + shownCount);

    return _Card(
      cardKey: const ValueKey('recapMilestone'),
      color: scheme.primaryContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _CardLabel(
                          Icons.emoji_events_outlined, l10n.recapCheckpoints,
                          color: fg),
                      const Spacer(),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: _CountUp(recap.completed,
                            suffix: l10n.recapBooksUnit,
                            style: TextStyle(
                                fontSize: 26,
                                height: 1,
                                fontWeight: FontWeight.w800,
                                color: fg)),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        m.next == null
                            ? l10n.recapAllCheckpoints
                            : l10n.recapToNextCheckpoint(
                                m.remaining(recap.completed), m.next!),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(fontSize: 11, color: fg.withAlpha(210)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 50,
                  height: 50,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: reduce ? progress : 0, end: progress),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) => Stack(
                      fit: StackFit.expand,
                      children: [
                        CircularProgressIndicator(
                          value: v,
                          strokeWidth: 5,
                          strokeCap: StrokeCap.round,
                          backgroundColor: fg.withAlpha(40),
                          color: scheme.primary,
                        ),
                        Center(
                          child: Text('${(v * 100).round()}%',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: fg)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                for (var i = 0; i < shown.length; i++) ...[
                  if (i > 0)
                    Container(
                      width: 10,
                      height: 1.5,
                      color: recap.completed >= shown[i]
                          ? scheme.primary
                          : fg.withAlpha(60),
                    ),
                  _CheckpointDot(
                    count: shown[i],
                    reached: recap.completed >= shown[i],
                    isNext: shown[i] == m.next,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckpointDot extends StatelessWidget {
  const _CheckpointDot(
      {required this.count, required this.reached, required this.isNext});

  final int count;
  final bool reached;
  final bool isNext;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = scheme.onPrimaryContainer;
    return Container(
      key: ValueKey('checkpoint-$count${reached ? '-reached' : ''}'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: reached ? scheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: reached ? scheme.primary : fg.withAlpha(isNext ? 160 : 70),
            width: isNext ? 1.4 : 1),
      ),
      child: Text('$count',
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: reached ? scheme.onPrimary : fg.withAlpha(200))),
    );
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.recap});

  final ReadingRecap recap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final on = recap.currentStreak > 0;
    return _Card(
      cardKey: const ValueKey('recapStreak'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.local_fire_department_rounded,
              size: 22,
              color: on ? const Color(0xFFFF7A1A) : scheme.onSurfaceVariant),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: _CountUp(recap.currentStreak,
                suffix: l10n.recapDaysUnit,
                style: TextStyle(
                    fontSize: 24,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface)),
          ),
          const SizedBox(height: 3),
          Text(on ? l10n.recapStreak : l10n.recapStreakStart,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface)),
          Text(l10n.recapLongestStreak(recap.longestStreak),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// Four weeks of reading as two rows of fourteen days, oldest first.
class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.recap});

  final ReadingRecap recap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    const columns = 14;
    const spacing = 4.0;

    Color shade(int hits) {
      if (hits <= 0) return scheme.onSurface.withAlpha(22);
      if (hits < 3) return scheme.primary.withAlpha(90);
      if (hits < 10) return scheme.primary.withAlpha(165);
      return scheme.primary;
    }

    return _Card(
      cardKey: const ValueKey('recapActivity'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardLabel(Icons.calendar_month_outlined, l10n.recapLastFourWeeks),
          const Spacer(),
          LayoutBuilder(builder: (context, c) {
            final cell = ((c.maxWidth - spacing * (columns - 1)) / columns)
                .clamp(6.0, 18.0);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var r = 0; r < 2; r++)
                  Padding(
                    padding: EdgeInsets.only(bottom: r == 0 ? spacing : 0),
                    child: Row(
                      children: [
                        for (var i = 0; i < columns; i++)
                          Padding(
                            padding: EdgeInsets.only(
                                right: i == columns - 1 ? 0 : spacing),
                            child: Container(
                              width: cell,
                              height: cell,
                              decoration: BoxDecoration(
                                color: shade(recap.recentDays[r * columns + i]),
                                borderRadius: BorderRadius.circular(3),
                                border: r == 1 && i == columns - 1
                                    ? Border.all(
                                        color: scheme.onSurface.withAlpha(120))
                                    : null,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          }),
          const SizedBox(height: 8),
          Text(l10n.recapReadingDays(recap.recentReadingDays),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface)),
        ],
      ),
    );
  }
}

class _MonthCard extends StatelessWidget {
  const _MonthCard({required this.recap});

  final ReadingRecap recap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return _Card(
      cardKey: const ValueKey('recapMonth'),
      color: scheme.secondaryContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              l10n.recapMonthTitle(DateFormat.MMMM(
                      Localizations.localeOf(context).toLanguageTag())
                  .format(DateTime(2000, recap.month))),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSecondaryContainer)),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: _CountUp(recap.completedThisMonth,
                suffix: l10n.recapBooksUnit,
                style: TextStyle(
                    fontSize: 24,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSecondaryContainer)),
          ),
          const SizedBox(height: 3),
          Text(l10n.recapFinishedThisMonth,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSecondaryContainer)),
          Text(l10n.recapReadingDays(recap.readingDaysThisMonth),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 10.5,
                  color: scheme.onSecondaryContainer.withAlpha(190))),
        ],
      ),
    );
  }
}

/// Share of each genre as one stacked bar with a legend.
class _GenreMixCard extends StatelessWidget {
  const _GenreMixCard({required this.recap});

  final ReadingRecap recap;

  static const _palette = [
    Color(0xFFEF5D5D),
    Color(0xFF5B8DEF),
    Color(0xFFF2B33D),
    Color(0xFF45B58A),
    Color(0xFFA77BE8),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final top = recap.genres.take(4).toList();
    final rest = recap.genres.skip(4).fold<int>(0, (a, e) => a + e.value);
    final parts = <(String, IconData, int, Color)>[
      for (var i = 0; i < top.length; i++)
        (
          genreLabel(l10n, top[i].key),
          genreIcon(top[i].key),
          top[i].value,
          _palette[i]
        ),
      if (rest > 0)
        (l10n.genreOther, genreIcon(BookGenre.other), rest, _palette[4]),
    ];
    final sum = parts.fold<int>(0, (a, p) => a + p.$3);

    return _Card(
      cardKey: const ValueKey('recapGenres'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardLabel(Icons.donut_small_outlined, l10n.recapGenreMix),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 10,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final p in parts)
                    Expanded(flex: p.$3, child: ColoredBox(color: p.$4)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              for (final p in parts)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration:
                          BoxDecoration(color: p.$4, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 5),
                    Text('${p.$1} ${(p.$3 * 100 / sum).round()}%',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
