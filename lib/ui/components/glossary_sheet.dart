// A glossary, in the reader and outside it (a book's page, a series' row
// in the library): the names and terms every translation writes the same
// way, each editable (its Korean form, kind and gender) or removable,
// and the whole made again on request.
//
// A word that was wrong is wrong in every paragraph translated with it,
// in every volume of a series that shares the glossary: setting it right
// here can have those paragraphs - of this book, or of the whole series
// - translated again at once, without a book being opened.

// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/translation/book_glossary.dart';
import 'package:openlib/services/translation/book_translation_service.dart';
import 'package:openlib/services/translation/glossary_service.dart';
import 'package:openlib/services/translation/series_glossary.dart'
    show seriesFiles;
import 'package:openlib/ui/components/library_tiles.dart'
    show modernSurfaceTheme;

/// The glossary of [bookFile] - or, with [series] (every volume's file),
/// of a series: what its volumes' glossaries have between them.
Future<void> showGlossarySheet(
  BuildContext context, {
  required String bookFile,
  List<String> series = const [],
  String? seriesName,
  Future<void> Function()? onRemake,
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
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, controller) => GlossarySheet(
          bookFile: bookFile,
          series: series,
          seriesName: seriesName,
          onRemake: onRemake,
          scrollController: controller,
        ),
      ),
    ),
  );
}

/// Which paragraphs with a word are translated again when it is set
/// right.
enum GlossaryRedo { none, book, series }

class GlossarySheet extends StatefulWidget {
  const GlossarySheet({
    super.key,
    required this.bookFile,
    this.series = const [],
    this.seriesName,
    this.onRemake,
    this.scrollController,
    this.service,
    this.redoWord,
    this.seriesOf,
  });

  /// The book; for a series, any of its volumes.
  final String bookFile;

  /// Every volume's file, when this is a series' glossary.
  final List<String> series;
  final String? seriesName;
  final Future<void> Function()? onRemake;
  final ScrollController? scrollController;
  final GlossaryService? service;

  /// Marks the paragraphs of the files that have the word and has them
  /// made again now; how many wait
  /// ([BookTranslationService.redoWord] unless given).
  final Future<int> Function(List<String> files, String source)? redoWord;

  /// The other volumes of a book's series ([seriesFiles] unless given).
  final Future<List<String>> Function(String bookFile)? seriesOf;

  static String kindLabel(AppLocalizations l10n, GlossaryKind kind) =>
      switch (kind) {
        GlossaryKind.person => l10n.glossaryKindPerson,
        GlossaryKind.place => l10n.glossaryKindPlace,
        GlossaryKind.term => l10n.glossaryKindTerm,
      };

  static String genderLabel(AppLocalizations l10n, GlossaryGender g) =>
      switch (g) {
        GlossaryGender.male => l10n.glossaryGenderMale,
        GlossaryGender.female => l10n.glossaryGenderFemale,
        GlossaryGender.unknown => l10n.glossaryGenderUnknown,
      };

  @override
  State<GlossarySheet> createState() => _GlossarySheetState();
}

class _GlossarySheetState extends State<GlossarySheet> {
  GlossaryService get _service => widget.service ?? GlossaryService.instance;
  final _translation = BookTranslationService.instance;
  String get bookFile => widget.bookFile;
  Future<void> Function()? get onRemake => widget.onRemake;
  ScrollController? get scrollController => widget.scrollController;

  /// The files this glossary is of: the book, or the series' volumes.
  late final List<String> _files =
      widget.series.isNotEmpty ? widget.series : [widget.bookFile];
  bool get _ofSeries => widget.series.isNotEmpty;

  /// The other volumes of the book's series (a book's sheet).
  List<String> _others = const [];

  @override
  void initState() {
    super.initState();
    // Outside the reader nothing has read the glossaries yet.
    for (final file in _files) {
      unawaited(_service.load(file).then((_) {
        if (mounted) setState(() {});
      }));
    }
    if (!_ofSeries) {
      unawaited((widget.seriesOf ?? seriesFiles)(bookFile).then((others) {
        if (mounted) setState(() => _others = others);
      }).catchError((_) {}));
    }
  }

  /// What the files' glossaries have between them: a word once, as the
  /// reader set it where a volume has it so.
  List<GlossaryEntry> _entries() {
    final by = <String, GlossaryEntry>{};
    for (final file in _files) {
      for (final e in (_service.cached(file) ?? BookGlossary.empty).entries) {
        if (e.target.isEmpty) continue;
        final known = by[e.source];
        if (known == null || (e.edited && !known.edited)) by[e.source] = e;
      }
    }
    return by.values.toList()
      ..sort((a, b) {
        final k = a.kind.index.compareTo(b.kind.index);
        return k != 0 ? k : a.source.compareTo(b.source);
      });
  }

  /// How far the paragraphs asked to be made again are, for these books.
  Widget? _redoStatus(AppLocalizations l10n, ThemeData theme) {
    final mine = {..._files, ..._others};
    final waiting =
        _translation.redoFiles.where(mine.contains).toList(growable: false);
    if (waiting.isEmpty) return null;
    var done = 0, total = 0;
    for (final file in waiting) {
      final p = _translation.redoProgress[file];
      if (p == null) continue;
      done += p.done;
      total += p.total;
    }
    final scheme = theme.colorScheme;
    return Container(
      key: const ValueKey('glossaryRedoStatus'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.translate_rounded,
                  size: 16, color: scheme.onSecondaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    total > 0
                        ? l10n.glossaryRedoProgress(done, total)
                        : l10n.glossaryRedoWaiting,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSecondaryContainer)),
              ),
              TextButton(
                key: const ValueKey('glossaryRedoStop'),
                onPressed: _translation.cancelRedo,
                child: Text(l10n.translationNoticeStop),
              ),
            ],
          ),
          // (Only when it is known how far.)
          if (total > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                    value: done / total,
                    minHeight: 4,
                    color: scheme.secondary,
                    backgroundColor: scheme.onSecondaryContainer.withAlpha(30)),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([_service, _translation]),
      builder: (context, _) {
        final making = _files.any(_service.isMaking);
        final entries = _entries();
        final status = _redoStatus(l10n, theme);
        return ListView(
          key: const ValueKey('glossarySheet'),
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                      _ofSeries && widget.seriesName != null
                          ? l10n.glossarySeriesTitle(widget.seriesName!)
                          : l10n.glossaryTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ),
                if (onRemake != null)
                  TextButton.icon(
                    key: const ValueKey('glossaryRemake'),
                    onPressed: making ? null : () => onRemake!(),
                    icon: making
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.auto_awesome_rounded, size: 18),
                    label: Text(l10n.glossaryRemake),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(making ? l10n.glossaryMaking : l10n.glossaryHint,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 14),
            if (status != null) status,
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Text(making ? l10n.glossaryMaking : l10n.glossaryEmpty,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant)),
              ),
            for (final e in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    key: ValueKey('glossary-${e.source}'),
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _edit(context, e),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    e.reading == null
                                        ? e.source
                                        : '${e.source}  ${e.reading}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                        color: scheme.onSurfaceVariant)),
                                const SizedBox(height: 2),
                                Text(e.target,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w700)),
                                if (e.speech != null)
                                  Text(e.speech!,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                              color: scheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          _Chip(GlossarySheet.kindLabel(l10n, e.kind)),
                          if (e.kind == GlossaryKind.person &&
                              e.gender != GlossaryGender.unknown) ...[
                            const SizedBox(width: 4),
                            _Chip(GlossarySheet.genderLabel(l10n, e.gender)),
                          ],
                          if (e.edited) ...[
                            const SizedBox(width: 4),
                            Icon(Icons.edit_rounded,
                                size: 14, color: scheme.primary),
                          ],
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right_rounded,
                              color: scheme.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _edit(BuildContext context, GlossaryEntry entry) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final result = await showDialog<_Edited?>(
      context: context,
      builder: (_) => _EditDialog(
        entry: entry,
        scopes: [
          GlossaryRedo.none,
          if (!_ofSeries) GlossaryRedo.book,
          if (_ofSeries || _others.isNotEmpty) GlossaryRedo.series,
        ],
      ),
    );
    if (result == null) return;
    final edited = result.entry;
    // In every file here that has the word (a series' sheet: each volume;
    // what the reader sets in one volume also goes to the others by
    // itself where the series shares its glossaries).
    for (final file in _files) {
      final has = (_service.cached(file) ?? BookGlossary.empty)
          .entries
          .any((e) => e.source == entry.source);
      if (!has) continue;
      if (edited.target.trim().isEmpty) {
        await _service.removeEntry(file, entry.source);
      } else {
        await _service.updateEntry(file, edited);
      }
    }
    if (result.redo == GlossaryRedo.none) return;
    // The paragraphs with the word, translated again now: this book's,
    // or every volume's.
    final files = result.redo == GlossaryRedo.book
        ? [bookFile]
        : {..._files, ..._others}.toList();
    try {
      final waiting = await (widget.redoWord ??
          (files, source) =>
              _translation.redoWord(files: files, source: source))(
          files, entry.source);
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text(waiting > 0
                ? l10n.glossaryRedone(waiting)
                : l10n.glossaryRedoNothing)));
    } catch (_) {}
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: scheme.onPrimaryContainer)),
    );
  }
}

/// What the reader set in the dialog.
class _Edited {
  const _Edited(this.entry, {this.redo = GlossaryRedo.none});
  final GlossaryEntry entry;

  /// Which paragraphs with the word are to be translated again.
  final GlossaryRedo redo;
}

class _EditDialog extends StatefulWidget {
  const _EditDialog({required this.entry, required this.scopes});
  final GlossaryEntry entry;

  /// What can be asked to be translated again here.
  final List<GlossaryRedo> scopes;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final TextEditingController _target =
      TextEditingController(text: widget.entry.target);
  late GlossaryKind _kind = widget.entry.kind;
  late GlossaryGender _gender = widget.entry.gender;
  GlossaryRedo _redo = GlossaryRedo.none;

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final e = widget.entry;
    return AlertDialog(
      title: Text(e.reading == null ? e.source : '${e.source} (${e.reading})'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('glossaryTarget'),
              controller: _target,
              autofocus: true,
              decoration: InputDecoration(labelText: l10n.glossaryKorean),
            ),
            const SizedBox(height: 14),
            SegmentedButton<GlossaryKind>(
              showSelectedIcon: false,
              segments: [
                for (final k in GlossaryKind.values)
                  ButtonSegment(
                      value: k, label: Text(GlossarySheet.kindLabel(l10n, k))),
              ],
              selected: {_kind},
              onSelectionChanged: (v) => setState(() => _kind = v.first),
            ),
            if (_kind == GlossaryKind.person) ...[
              const SizedBox(height: 10),
              SegmentedButton<GlossaryGender>(
                showSelectedIcon: false,
                segments: [
                  for (final g in GlossaryGender.values)
                    ButtonSegment(
                        value: g,
                        label: Text(GlossarySheet.genderLabel(l10n, g))),
                ],
                selected: {_gender},
                onSelectionChanged: (v) => setState(() => _gender = v.first),
              ),
            ],
            const SizedBox(height: 16),
            Text(l10n.glossaryRedoScope,
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            SegmentedButton<GlossaryRedo>(
              key: const ValueKey('glossaryRedoScope'),
              showSelectedIcon: false,
              segments: [
                for (final r in widget.scopes)
                  ButtonSegment(
                      value: r,
                      label: Text(
                          switch (r) {
                            GlossaryRedo.none => l10n.glossaryRedoNone,
                            GlossaryRedo.book => l10n.glossaryRedoBook,
                            GlossaryRedo.series => l10n.glossaryRedoSeries,
                          },
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis)),
              ],
              selected: {_redo},
              onSelectionChanged: (v) => setState(() => _redo = v.first),
            ),
            const SizedBox(height: 6),
            Text(l10n.glossaryRedoScopeHint,
                style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('glossaryDelete'),
          onPressed: () => Navigator.of(context)
              .pop(_Edited(e.copyWith(target: ''), redo: _redo)),
          child: Text(l10n.delete),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('glossarySave'),
          onPressed: () => Navigator.of(context).pop(_Edited(
              e.copyWith(
                target: _target.text.trim(),
                kind: _kind,
                gender: _kind == GlossaryKind.person
                    ? _gender
                    : GlossaryGender.unknown,
              ),
              redo: _redo)),
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
