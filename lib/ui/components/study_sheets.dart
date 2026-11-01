// The reader's study sheets: study settings, a word's meaning in its
// sentence, a sentence explained, and a book's difficulty.

// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/study/book_difficulty.dart';
import 'package:openlib/services/study/japanese_tools.dart';
import 'package:openlib/services/study/study_assistant.dart';
import 'package:openlib/services/study/study_data.dart';
import 'package:openlib/services/study/study_settings.dart';
import 'package:openlib/services/study/study_store.dart';

String _mb(int bytes) => '${(bytes / (1024 * 1024)).round()} MB';

/// A small rounded label (N3, 名詞).
class StudyBadge extends StatelessWidget {
  const StudyBadge(this.label, {super.key, this.strong = false});
  final String label;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: strong ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: strong
                  ? scheme.onPrimaryContainer
                  : scheme.onSurfaceVariant)),
    );
  }
}

Widget _sectionTitle(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(text,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700)),
    );

// ---------------------------------------------------------------------------
// Study settings
// ---------------------------------------------------------------------------

Future<void> showStudySettingsSheet(
  BuildContext context, {
  required bool japanese,
  required bool translating,
  VoidCallback? onDifficulty,
  VoidCallback? onWordBook,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => StudySettingsSheet(
        japanese: japanese,
        translating: translating,
        onDifficulty: onDifficulty,
        onWordBook: onWordBook,
      ),
    );

class StudySettingsSheet extends StatelessWidget {
  const StudySettingsSheet({
    super.key,
    required this.japanese,
    required this.translating,
    this.onDifficulty,
    this.onWordBook,
  });

  final bool japanese;
  final bool translating;
  final VoidCallback? onDifficulty;
  final VoidCallback? onWordBook;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = StudySettings.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([settings, JapaneseTools.instance]),
      builder: (context, _) {
        final s = settings.value;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.studyTitle,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              _sectionTitle(context, l10n.studyTranslationLayout),
              SegmentedButton<TranslationLayout>(
                key: const ValueKey('studyLayout'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                      value: TranslationLayout.replace,
                      label: Text(l10n.studyLayoutReplace)),
                  ButtonSegment(
                      value: TranslationLayout.below,
                      label: Text(l10n.studyLayoutBelow)),
                  ButtonSegment(
                      value: TranslationLayout.hidden,
                      label: Text(l10n.studyLayoutHidden)),
                ],
                selected: {s.layout},
                onSelectionChanged: (v) =>
                    settings.update(s.copyWith(layout: v.first)),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(l10n.studyLayoutHint,
                    style: Theme.of(context).textTheme.bodySmall),
              ),
              if (japanese) ...[
                _sectionTitle(context, l10n.studyFurigana),
                SegmentedButton<FuriganaMode>(
                  key: const ValueKey('studyFurigana'),
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                        value: FuriganaMode.off,
                        label: Text(l10n.studyFuriganaOff)),
                    ButtonSegment(
                        value: FuriganaMode.hard,
                        label: Text(l10n.studyFuriganaHard)),
                    ButtonSegment(
                        value: FuriganaMode.all,
                        label: Text(l10n.studyFuriganaAll)),
                  ],
                  selected: {s.furigana},
                  onSelectionChanged: (v) =>
                      settings.update(s.copyWith(furigana: v.first)),
                ),
                _sectionTitle(context, l10n.studyLevel),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final level in const [5, 4, 3, 2, 1])
                      ChoiceChip(
                        key: ValueKey('studyLevel$level'),
                        label: Text('N$level'),
                        selected: s.level == level,
                        onSelected: (_) =>
                            settings.update(s.copyWith(level: level)),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  key: const ValueKey('studyWordTap'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.studyWordTap),
                  subtitle: Text(l10n.studyWordTapHint),
                  value: s.wordTap,
                  onChanged: (v) => settings.update(s.copyWith(wordTap: v)),
                ),
                const _ToolsRow(),
              ],
              const SizedBox(height: 8),
              Text(l10n.studySelectHint,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              if (japanese && onDifficulty != null)
                ListTile(
                  key: const ValueKey('studyDifficulty'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.insights_outlined),
                  title: Text(l10n.studyDifficulty),
                  onTap: () {
                    Navigator.pop(context);
                    onDifficulty!();
                  },
                ),
              if (onWordBook != null)
                ListTile(
                  key: const ValueKey('studyWordBook'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.style_outlined),
                  title: Text(l10n.studyWordBook),
                  onTap: () {
                    Navigator.pop(context);
                    onWordBook!();
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The word tools: download, progress, ready.
class _ToolsRow extends StatefulWidget {
  const _ToolsRow();

  @override
  State<_ToolsRow> createState() => _ToolsRowState();
}

class _ToolsRowState extends State<_ToolsRow> {
  @override
  void initState() {
    super.initState();
    unawaited(JapaneseTools.instance.installed());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tools = JapaneseTools.instance;
    final Widget trailing;
    final String status;
    switch (tools.phase) {
      case ToolsPhase.ready:
        status = l10n.studyToolsReady;
        trailing = const Icon(Icons.check_circle_outline);
      case ToolsPhase.downloading:
        status = l10n.studyToolsDownloading((tools.progress * 100).round());
        trailing = SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
                strokeWidth: 2.4, value: tools.progress.clamp(0.02, 1.0)));
      case ToolsPhase.failed:
      case ToolsPhase.missing:
        status = tools.phase == ToolsPhase.failed
            ? l10n.studyToolsFailed
            : l10n.studyToolsWhy;
        trailing = FilledButton.tonal(
          key: const ValueKey('studyToolsDownload'),
          onPressed: tools.download,
          child: Text(l10n.studyToolsDownload(_mb(kuromojiBytes))),
        );
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(l10n.studyTools),
      subtitle: Text(status),
      trailing: trailing,
      isThreeLine: tools.phase == ToolsPhase.missing,
    );
  }
}

// ---------------------------------------------------------------------------
// A word
// ---------------------------------------------------------------------------

/// The word, its reading and level, its kanji read the Korean way (for a
/// Korean reader), its meaning in the sentence, and the word book.
Future<void> showWordSheet(
  BuildContext context, {
  required WordQuery query,
  required StudyAssistant? assistant,
  required String book,
  required String targetCode,
  void Function(String sentence)? onExplain,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => WordSheet(
        query: query,
        assistant: assistant,
        book: book,
        targetCode: targetCode,
        onExplain: onExplain,
      ),
    );

class WordSheet extends StatefulWidget {
  const WordSheet({
    super.key,
    required this.query,
    required this.assistant,
    required this.book,
    required this.targetCode,
    this.onExplain,
  });

  final WordQuery query;
  final StudyAssistant? assistant;
  final String book;
  final String targetCode;
  final void Function(String sentence)? onExplain;

  @override
  State<WordSheet> createState() => _WordSheetState();
}

class _WordSheetState extends State<WordSheet> {
  Future<WordMeaning?>? _meaning;
  WordMeaning? _known;

  @override
  void initState() {
    super.initState();
    _ask();
  }

  void _ask() {
    final a = widget.assistant;
    if (a == null) return;
    _known = a.knownMeaning(widget.query);
    final q = widget.query;
    _meaning = a.meaning(q).catchError((_) => null).then((m) {
      // Added before the meaning came: the card gets it now.
      final card = StudyStore.instance.card(q.base, q.reading);
      if (m != null && card != null && card.meaning.isEmpty) {
        unawaited(StudyStore.instance
            .add(word: q.base, reading: q.reading, meaning: m.meaning));
      }
      return m;
    });
  }

  Future<void> _add(WordMeaning? m) async {
    final q = widget.query;
    final store = StudyStore.instance;
    if (store.has(q.base, q.reading)) {
      await store.remove(StudyCard.idFor(q.base, q.reading));
    } else {
      await store.add(
        word: q.base,
        reading: q.reading,
        meaning: m?.meaning ?? '',
        sentence: q.sentence,
        book: widget.book,
        level: q.level,
      );
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final q = widget.query;
    final theme = Theme.of(context);
    final hanja = widget.targetCode.startsWith('ko')
        ? StudyData.instance.hanjaOf(q.base)
        : const <(String, String)>[];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: FutureBuilder<WordMeaning?>(
        future: _meaning,
        initialData: _known,
        builder: (context, snap) {
          final m = snap.data;
          final waiting =
              snap.connectionState == ConnectionState.waiting && m == null;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: 10,
                runSpacing: 4,
                children: [
                  Text(q.base,
                      key: const ValueKey('studyWord'),
                      style: theme.textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  if (q.reading.isNotEmpty && q.reading != q.base)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(q.reading,
                          style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: [
                StudyBadge(q.level > 0 ? jlptLabel(q.level) : l10n.studyNotOnList,
                    strong: q.level > 0),
                if (q.pos.isNotEmpty) StudyBadge(q.pos),
                if (q.surface.isNotEmpty && q.surface != q.base)
                  StudyBadge(q.surface),
              ]),
              if (hanja.isNotEmpty) ...[
                _sectionTitle(context, l10n.studyKanji),
                Wrap(spacing: 14, runSpacing: 4, children: [
                  for (final (c, ko) in hanja)
                    Text.rich(TextSpan(children: [
                      TextSpan(
                          text: c,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w600)),
                      TextSpan(
                          text: ' $ko',
                          style: TextStyle(
                              fontSize: 15,
                              color: theme.colorScheme.onSurfaceVariant)),
                    ])),
                ]),
              ],
              _sectionTitle(context, l10n.studyMeaning),
              if (widget.assistant == null)
                Text(l10n.studyNoEngine)
              else if (waiting)
                Row(children: [
                  const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 10),
                  Text(l10n.studyLookingUp),
                ])
              else if (m == null)
                Row(children: [
                  Expanded(child: Text(l10n.studyNoAnswer)),
                  TextButton(
                      onPressed: () => setState(_ask),
                      child: Text(l10n.retry)),
                ])
              else ...[
                Text(m.meaning,
                    key: const ValueKey('studyMeaning'),
                    style: theme.textTheme.titleMedium),
                if (m.other.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('${l10n.studyOtherMeanings}: ${m.other.join(', ')}',
                      style: theme.textTheme.bodyMedium),
                ],
                if (m.note.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(m.note,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ],
              if (q.sentence.isNotEmpty) ...[
                _sectionTitle(context, l10n.studySentence),
                _HighlightedSentence(q.sentence, q.surface.isNotEmpty ? q.surface : q.base),
              ],
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: ListenableBuilder(
                    listenable: StudyStore.instance,
                    builder: (context, _) {
                      final added =
                          StudyStore.instance.has(q.base, q.reading);
                      return FilledButton.icon(
                        key: const ValueKey('studyAdd'),
                        onPressed: () => _add(m),
                        icon: Icon(added ? Icons.check : Icons.add),
                        label: Text(
                            added ? l10n.studyWordAdded : l10n.studyAddWord),
                      );
                    },
                  ),
                ),
                if (widget.onExplain != null && q.sentence.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('studyExplain'),
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onExplain!(q.sentence);
                      },
                      icon: const Icon(Icons.menu_book_outlined),
                      label: Text(l10n.studyExplain),
                    ),
                  ),
                ],
              ]),
            ],
          );
        },
      ),
    );
  }
}

class _HighlightedSentence extends StatelessWidget {
  const _HighlightedSentence(this.sentence, this.word);
  final String sentence;
  final String word;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge;
    final at = word.isEmpty ? -1 : sentence.indexOf(word);
    if (at < 0) return Text(sentence, style: style);
    return Text.rich(TextSpan(style: style, children: [
      TextSpan(text: sentence.substring(0, at)),
      TextSpan(
          text: word,
          style: TextStyle(
              fontWeight: FontWeight.w700,
              backgroundColor:
                  Theme.of(context).colorScheme.primaryContainer)),
      TextSpan(text: sentence.substring(at + word.length)),
    ]));
  }
}

// ---------------------------------------------------------------------------
// A sentence
// ---------------------------------------------------------------------------

Future<void> showExplanationSheet(
  BuildContext context, {
  required String sentence,
  required StudyAssistant? assistant,
  required String book,
  int level = 4,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.95,
        builder: (context, scroll) => ExplanationSheet(
          sentence: sentence,
          assistant: assistant,
          book: book,
          level: level,
          scroll: scroll,
        ),
      ),
    );

class ExplanationSheet extends StatefulWidget {
  const ExplanationSheet({
    super.key,
    required this.sentence,
    required this.assistant,
    required this.book,
    this.level = 4,
    this.scroll,
  });

  final String sentence;
  final StudyAssistant? assistant;
  final String book;
  final int level;
  final ScrollController? scroll;

  @override
  State<ExplanationSheet> createState() => _ExplanationSheetState();
}

class _ExplanationSheetState extends State<ExplanationSheet> {
  Future<SentenceExplanation?>? _future;
  SentenceExplanation? _known;

  @override
  void initState() {
    super.initState();
    _ask();
  }

  void _ask() {
    final a = widget.assistant;
    if (a == null) return;
    _known = a.knownExplanation(widget.sentence, widget.level);
    _future = a
        .explain(widget.sentence, level: widget.level)
        .catchError((_) => null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return FutureBuilder<SentenceExplanation?>(
      future: _future,
      initialData: _known,
      builder: (context, snap) {
        final e = snap.data;
        final waiting =
            snap.connectionState == ConnectionState.waiting && e == null;
        return ListView(
          controller: widget.scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(widget.sentence,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600, height: 1.5)),
            if (widget.assistant == null)
              Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(l10n.studyNoEngine))
            else if (waiting)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Row(children: [
                  const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 10),
                  Text(l10n.studyExplaining),
                ]),
              )
            else if (e == null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Row(children: [
                  Expanded(child: Text(l10n.studyNoAnswer)),
                  TextButton(
                      onPressed: () => setState(_ask),
                      child: Text(l10n.retry)),
                ]),
              )
            else ...[
              if (e.translation.isNotEmpty) ...[
                _sectionTitle(context, l10n.studyTranslation),
                Text(e.translation,
                    key: const ValueKey('studyExplanationTranslation'),
                    style: theme.textTheme.bodyLarge),
              ],
              if (e.words.isNotEmpty) ...[
                _sectionTitle(context, l10n.studyWords),
                for (final w in e.words)
                  _ExplainedWordTile(
                      word: w, sentence: widget.sentence, book: widget.book),
              ],
              if (e.grammar.isNotEmpty) ...[
                _sectionTitle(context, l10n.studyGrammar),
                for (final g in e.grammar)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text.rich(TextSpan(children: [
                      TextSpan(
                          text: '${g.pattern}  ',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: g.explanation),
                    ])),
                  ),
              ],
              if (e.nuance.isNotEmpty) ...[
                _sectionTitle(context, l10n.studyNuance),
                Text(e.nuance),
              ],
            ],
          ],
        );
      },
    );
  }
}

class _ExplainedWordTile extends StatelessWidget {
  const _ExplainedWordTile(
      {required this.word, required this.sentence, required this.book});
  final ExplainedWord word;
  final String sentence;
  final String book;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final store = StudyStore.instance;
    final level = StudyData.instance.levelOf(word.word, word.reading);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final added = store.has(word.word, word.reading);
        return ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text.rich(TextSpan(children: [
            TextSpan(
                text: word.word,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            if (word.reading.isNotEmpty && word.reading != word.word)
              TextSpan(text: '  ${word.reading}'),
          ])),
          subtitle: Text(word.meaning),
          trailing: IconButton(
            tooltip: added ? l10n.studyWordAdded : l10n.studyAddWord,
            icon: Icon(added ? Icons.check : Icons.add),
            onPressed: () => added
                ? store.remove(StudyCard.idFor(word.word, word.reading))
                : store.add(
                    word: word.word,
                    reading: word.reading,
                    meaning: word.meaning,
                    sentence: sentence,
                    book: book,
                    level: level,
                  ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// A book's difficulty
// ---------------------------------------------------------------------------

Future<void> showDifficultySheet(
  BuildContext context, {
  required ValueListenable<double> progress,
  required Future<BookDifficulty?> result,
  required String book,
  Set<String> names = const {},
  void Function(List<BookWord> words)? onAdded,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (context, scroll) => DifficultySheet(
          progress: progress,
          result: result,
          book: book,
          names: names,
          onAdded: onAdded,
          scroll: scroll,
        ),
      ),
    );

class DifficultySheet extends StatelessWidget {
  const DifficultySheet({
    super.key,
    required this.progress,
    required this.result,
    required this.book,
    this.names = const {},
    this.onAdded,
    this.scroll,
  });

  /// Words added without a meaning, for the caller to look up.
  final void Function(List<BookWord> words)? onAdded;
  final ValueListenable<double> progress;
  final Future<BookDifficulty?> result;
  final String book;
  final Set<String> names;
  final ScrollController? scroll;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return FutureBuilder<BookDifficulty?>(
      future: result,
      builder: (context, snap) {
        final header = Text(l10n.studyDifficulty,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700));
        if (snap.connectionState != ConnectionState.done) {
          return ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              header,
              const SizedBox(height: 20),
              ValueListenableBuilder<double>(
                valueListenable: progress,
                builder: (context, p, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.studyAnalyzing((p * 100).round())),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: p <= 0 ? null : p),
                  ],
                ),
              ),
            ],
          );
        }
        final d = snap.data;
        if (d == null || d.tokens == 0) {
          return ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [header, const SizedBox(height: 16), Text(l10n.studyAnalysisFailed)],
          );
        }
        return ListenableBuilder(
          listenable: StudySettings.instance,
          builder: (context, _) {
            final level = StudySettings.instance.value.level;
            final hard = d.frequentHarder(level, names: names);
            final fresh = hard
                .where((w) => !StudyStore.instance.has(w.base, w.reading))
                .take(20)
                .toList();
            return ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                header,
                const SizedBox(height: 12),
                Text(
                    l10n.studyHarderShare(
                        (d.harderShare(level) * 100).round(), 'N$level'),
                    key: const ValueKey('studyHarderShare'),
                    style: theme.textTheme.titleMedium),
                _sectionTitle(context, l10n.studyLevelShare),
                for (final l in const [5, 4, 3, 2, 1, 0])
                  _LevelBar(
                    label: l == 0 ? l10n.studyNotOnList : 'N$l',
                    share: d.share(l),
                    unique: d.byLevel[l]?.unique ?? 0,
                    above: BookDifficulty.harder(l, level),
                  ),
                _sectionTitle(context, l10n.studyFrequentHard),
                if (fresh.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const ValueKey('studyAddAll'),
                      icon: const Icon(Icons.playlist_add),
                      label: Text(l10n.studyAddAll(fresh.length)),
                      onPressed: () async {
                        for (final w in fresh) {
                          await StudyStore.instance.add(
                            word: w.base,
                            reading: w.reading,
                            sentence: w.sentence,
                            book: book,
                            level: w.level,
                          );
                        }
                        onAdded?.call(fresh);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content:
                                  Text(l10n.studyAddedCount(fresh.length))));
                        }
                      },
                    ),
                  ),
                for (final w in hard)
                  ListenableBuilder(
                    listenable: StudyStore.instance,
                    builder: (context, _) {
                      final added = StudyStore.instance.has(w.base, w.reading);
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text.rich(TextSpan(children: [
                          TextSpan(
                              text: w.base,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700)),
                          if (w.reading.isNotEmpty && w.reading != w.base)
                            TextSpan(text: '  ${w.reading}'),
                        ])),
                        subtitle: Text(
                            '${w.level > 0 ? 'N${w.level}' : l10n.studyNotOnList} · ${l10n.studyTimes(w.count)}'),
                        trailing: IconButton(
                          icon: Icon(added ? Icons.check : Icons.add),
                          tooltip:
                              added ? l10n.studyWordAdded : l10n.studyAddWord,
                          onPressed: added
                              ? null
                              : () async {
                                  await StudyStore.instance.add(
                                    word: w.base,
                                    reading: w.reading,
                                    sentence: w.sentence,
                                    book: book,
                                    level: w.level,
                                  );
                                  onAdded?.call([w]);
                                },
                        ),
                      );
                    },
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _LevelBar extends StatelessWidget {
  const _LevelBar(
      {required this.label,
      required this.share,
      required this.unique,
      required this.above});
  final String label;
  final double share;
  final int unique;
  final bool above;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(
            width: 92,
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: share.clamp(0.0, 1.0),
              minHeight: 10,
              color: above ? scheme.tertiary : scheme.primary,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
        ),
        SizedBox(
          width: 86,
          child: Text('${(share * 100).toStringAsFixed(1)}% · $unique',
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontSize: 12, fontFeatures: [FontFeature.tabularFigures()])),
        ),
      ]),
    );
  }
}
