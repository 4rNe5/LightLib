// The word book: what was studied (today, the streak, the last weeks),
// the cards to review, every word added while reading, and an export for
// Anki. Review shows a card's word, then its reading and meaning, and
// schedules it by the answer.

// Dart imports:
import 'dart:async';
import 'dart:io';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/study/study_data.dart';
import 'package:openlib/services/study/study_store.dart';
import 'package:openlib/ui/components/study_sheets.dart' show StudyBadge;

class StudyPage extends StatefulWidget {
  const StudyPage({super.key, this.store});
  final StudyStore? store;

  @override
  State<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends State<StudyPage> {
  StudyStore get _store => widget.store ?? StudyStore.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_store.load());
  }

  Future<void> _export() async {
    final l10n = AppLocalizations.of(context);
    final cards = _store.cards;
    if (cards.isEmpty) return;
    try {
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, 'LightLib-words.txt'));
      await file.writeAsString(ankiExport(cards));
      await SharePlus.instance.share(ShareParams(
          files: [XFile(file.path, mimeType: 'text/tab-separated-values')],
          subject: l10n.studyWordBook));
    } catch (_) {}
  }

  Future<void> _review() async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => ReviewPage(store: _store)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.studyWordBook),
        actions: [
          IconButton(
            key: const ValueKey('studyExport'),
            tooltip: l10n.studyExportAnki,
            icon: const Icon(Icons.ios_share),
            onPressed: _export,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _store,
        builder: (context, _) {
          final cards = _store.cards;
          final due = _store.due();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _StudyRecord(store: _store),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const ValueKey('studyReview'),
                onPressed: due.isEmpty ? null : _review,
                icon: const Icon(Icons.play_arrow),
                label: Text(due.isEmpty
                    ? l10n.studyNothingDue
                    : '${l10n.studyStartReview} · ${l10n.studyDue(due.length)}'),
              ),
              const SizedBox(height: 16),
              Text(l10n.studyTotalWords(cards.length),
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              if (cards.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(l10n.studyEmpty,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
              for (final c in cards)
                Dismissible(
                  key: ValueKey('card-${c.id}'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Icon(Icons.delete_outline,
                        color: Theme.of(context).colorScheme.onErrorContainer),
                  ),
                  onDismissed: (_) => _store.remove(c.id),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text.rich(TextSpan(children: [
                      TextSpan(
                          text: c.word,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w700)),
                      if (c.reading.isNotEmpty && c.reading != c.word)
                        TextSpan(text: '  ${c.reading}'),
                    ])),
                    subtitle: Text(
                        c.meaning.isNotEmpty ? c.meaning : c.sentence,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (c.level > 0) StudyBadge(jlptLabel(c.level)),
                        const SizedBox(height: 4),
                        Text(_dueLabel(l10n, c, _store.now()),
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

String _dueLabel(AppLocalizations l10n, StudyCard c, DateTime now) {
  if (c.isNew) return l10n.studyNew;
  if (c.isDue(now)) return l10n.studyDueNow;
  return _span(l10n, c.due.difference(now));
}

String _span(AppLocalizations l10n, Duration d) {
  if (d.inMinutes < 60 * 24) return l10n.studyMinutes(d.inMinutes.clamp(1, 1439));
  return l10n.studyDays((d.inHours / 24).round());
}

class _StudyRecord extends StatelessWidget {
  const _StudyRecord({required this.store});
  final StudyStore store;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final today = store.dayAt(store.now());
    final days = store.recent(28);
    final busiest = days.fold<int>(1, (m, d) {
      final v = d.$2.looked + d.$2.explained + d.$2.reviewed + d.$2.added;
      return v > m ? v : m;
    });
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest.withAlpha(120),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(l10n.studyToday,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              StudyBadge(l10n.studyStreak(store.streak), strong: true),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 14, runSpacing: 6, children: [
              Text(l10n.studyLookedUp(today.looked)),
              Text(l10n.studyExplainedCount(today.explained)),
              Text(l10n.studyReviewedCount(today.reviewed)),
              Text(l10n.studyCharsRead(today.chars)),
            ]),
            const SizedBox(height: 14),
            SizedBox(
              height: 36,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final (_, d) in days)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1.5),
                        child: Container(
                          height: 4 +
                              32 *
                                  ((d.looked + d.explained + d.reviewed + d.added) /
                                      busiest),
                          decoration: BoxDecoration(
                            color: d.active
                                ? scheme.primary
                                : scheme.outlineVariant.withAlpha(120),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Review
// ---------------------------------------------------------------------------

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key, this.store});
  final StudyStore? store;

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  StudyStore get _store => widget.store ?? StudyStore.instance;
  late List<StudyCard> _queue = _store.due();
  int _done = 0;
  bool _shown = false;

  Future<void> _answer(ReviewGrade grade) async {
    final card = _queue.first;
    final next = await _store.review(card.id, grade);
    if (!mounted) return;
    setState(() {
      _queue = _queue.sublist(1);
      _done++;
      _shown = false;
      // Still being learnt and due within the session: back in the queue.
      if (next != null &&
          next.learning &&
          next.due.difference(_store.now()) <= const Duration(minutes: 10)) {
        _queue.add(next);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final total = _done + _queue.length;
    return Scaffold(
      appBar: AppBar(
        title: Text('${l10n.studyStartReview}  $_done/$total'),
      ),
      body: _queue.isEmpty
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.celebration_outlined, size: 44),
                const SizedBox(height: 12),
                Text(l10n.studyReviewDone,
                    key: const ValueKey('studyReviewDone'),
                    style: theme.textTheme.titleMedium),
              ]),
            )
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _cardFace(context, _queue.first)),
                    if (!_shown)
                      FilledButton(
                        key: const ValueKey('studyShowAnswer'),
                        onPressed: () => setState(() => _shown = true),
                        child: Text(l10n.studyShowAnswer),
                      )
                    else
                      Row(children: [
                        for (final g in ReviewGrade.values)
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 3),
                              child: _gradeButton(context, _queue.first, g),
                            ),
                          ),
                      ]),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _gradeButton(BuildContext context, StudyCard card, ReviewGrade g) {
    final l10n = AppLocalizations.of(context);
    final now = _store.now();
    final next = schedule(card, g, now);
    final label = switch (g) {
      ReviewGrade.again => l10n.studyAgain,
      ReviewGrade.hard => l10n.studyHard,
      ReviewGrade.good => l10n.studyGood,
      ReviewGrade.easy => l10n.studyEasy,
    };
    return OutlinedButton(
      key: ValueKey('studyGrade-${g.name}'),
      style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 10)),
      onPressed: () => _answer(g),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(_span(l10n, next.due.difference(now)),
            style: const TextStyle(fontSize: 11)),
      ]),
    );
  }

  Widget _cardFace(BuildContext context, StudyCard c) {
    final theme = Theme.of(context);
    final at = c.sentence.indexOf(c.word);
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 24),
          Text(c.word,
              key: const ValueKey('studyCardWord'),
              textAlign: TextAlign.center,
              style: theme.textTheme.displaySmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          if (c.sentence.isNotEmpty) ...[
            const SizedBox(height: 18),
            at < 0
                ? Text(c.sentence,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge)
                : Text.rich(
                    TextSpan(style: theme.textTheme.bodyLarge, children: [
                      TextSpan(text: c.sentence.substring(0, at)),
                      TextSpan(
                          text: c.word,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: c.sentence.substring(at + c.word.length)),
                    ]),
                    textAlign: TextAlign.center),
          ],
          if (_shown) ...[
            const Divider(height: 40),
            if (c.reading.isNotEmpty && c.reading != c.word)
              Text(c.reading,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text(c.meaning,
                key: const ValueKey('studyCardMeaning'),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium),
            if (c.sentenceMeaning.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(c.sentenceMeaning,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium),
            ],
            if (c.book.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(c.book,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ],
        ],
      ),
    );
  }
}
