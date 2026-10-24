// The book's glossary in the reader: the names and terms every
// translation writes the same way, each editable (its Korean form, kind
// and gender) or removable, and the whole made again on request.

// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/translation/book_glossary.dart';
import 'package:openlib/services/translation/glossary_service.dart';
import 'package:openlib/ui/components/library_tiles.dart'
    show modernSurfaceTheme;

Future<void> showGlossarySheet(
  BuildContext context, {
  required String bookFile,
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
          onRemake: onRemake,
          scrollController: controller,
        ),
      ),
    ),
  );
}

class GlossarySheet extends StatelessWidget {
  const GlossarySheet({
    super.key,
    required this.bookFile,
    this.onRemake,
    this.scrollController,
    this.service,
  });

  final String bookFile;
  final Future<void> Function()? onRemake;
  final ScrollController? scrollController;
  final GlossaryService? service;

  GlossaryService get _service => service ?? GlossaryService.instance;

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
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListenableBuilder(
      listenable: _service,
      builder: (context, _) {
        final making = _service.isMaking(bookFile);
        final glossary = _service.cached(bookFile) ?? BookGlossary.empty;
        final entries = glossary.entries
            .where((e) => e.target.isNotEmpty)
            .toList()
          ..sort((a, b) {
            final k = a.kind.index.compareTo(b.kind.index);
            return k != 0 ? k : a.source.compareTo(b.source);
          });
        return ListView(
          key: const ValueKey('glossarySheet'),
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(l10n.glossaryTitle,
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
                          _Chip(kindLabel(l10n, e.kind)),
                          if (e.kind == GlossaryKind.person &&
                              e.gender != GlossaryGender.unknown) ...[
                            const SizedBox(width: 4),
                            _Chip(genderLabel(l10n, e.gender)),
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
    final edited = await showDialog<GlossaryEntry?>(
      context: context,
      builder: (_) => _EditDialog(entry: entry),
    );
    if (edited == null) return;
    if (edited.target.trim().isEmpty) {
      await _service.removeEntry(bookFile, entry.source);
    } else {
      await _service.updateEntry(bookFile, edited);
    }
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

class _EditDialog extends StatefulWidget {
  const _EditDialog({required this.entry});
  final GlossaryEntry entry;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final TextEditingController _target =
      TextEditingController(text: widget.entry.target);
  late GlossaryKind _kind = widget.entry.kind;
  late GlossaryGender _gender = widget.entry.gender;

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
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('glossaryDelete'),
          onPressed: () =>
              Navigator.of(context).pop(e.copyWith(target: '')),
          child: Text(l10n.delete),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('glossarySave'),
          onPressed: () => Navigator.of(context).pop(e.copyWith(
            target: _target.text.trim(),
            kind: _kind,
            gender: _kind == GlossaryKind.person
                ? _gender
                : GlossaryGender.unknown,
          )),
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
