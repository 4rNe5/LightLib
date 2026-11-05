// The search filters, in a sheet behind the search field's filter button:
// language, file type, sort, kind, year, author and publisher. Every
// change applies at once and is kept for the next search.

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/database.dart';
import 'package:openlib/state/state.dart';

/// The filters as the sheet and the search field's summary show them.
class SearchFilters {
  const SearchFilters({
    required this.language,
    required this.fileType,
    required this.sort,
    required this.type,
    required this.year,
    required this.author,
    required this.publisher,
  });

  final String language;
  final String fileType;
  final String sort;
  final String type;
  final String year;
  final String author;
  final String publisher;

  static SearchFilters of(WidgetRef ref) => SearchFilters(
        language: ref.watch(selectedLanguageState),
        fileType: ref.watch(selectedFileTypeState),
        sort: ref.watch(selectedSortState),
        type: ref.watch(selectedTypeState),
        year: ref.watch(selectedYearState),
        author: ref.watch(searchAuthorProvider),
        publisher: ref.watch(searchPublisherProvider),
      );

  /// Filters set away from "all" (a sort other than relevance counts).
  int get active => [
        language != 'All',
        fileType != 'All',
        sort != 'Most Relevant',
        type != 'All',
        year != 'All',
        author.isNotEmpty,
        publisher.isNotEmpty,
      ].where((x) => x).length;
}

/// Display names for the stored filter values (English keys, kept as
/// they are for the saved preferences and the providers).
class FilterLabels {
  FilterLabels(this.l10n);
  final AppLocalizations l10n;

  String language(String key) => switch (key) {
        'All' => l10n.filterAll,
        'Japanese' => l10n.languageJapanese,
        'Korean' => l10n.languageKorean,
        'English' => l10n.languageEnglish,
        'Chinese' => l10n.languageChinese,
        _ => key,
      };

  String fileType(String key) =>
      key == 'All' ? l10n.filterAll : key.toUpperCase();

  String sort(String key) => switch (key) {
        'Newest' => l10n.sortNewest,
        'Oldest' => l10n.sortOldest,
        'Largest' => l10n.sortLargest,
        'Smallest' => l10n.sortSmallest,
        _ => l10n.sortRelevant,
      };

  String type(String key) => switch (key) {
        'Any Books' => l10n.typeAnyBook,
        'Unknown Books' => l10n.typeUnknownBook,
        'Fiction Books' => l10n.typeFiction,
        'Non-fiction Books' => l10n.typeNonfiction,
        'Comic Books' => l10n.typeComic,
        'Magazine' => l10n.typeMagazine,
        'Standards Document' => l10n.typeStandards,
        'Journal Article' => l10n.typeArticle,
        _ => l10n.filterAll,
      };

  String year(String key) => key == 'All'
      ? l10n.filterAll
      : key == 'Before 1980'
          ? l10n.yearBefore1980
          : key;
}

/// The languages offered as chips; the rest are in "Other".
const quickLanguages = ['Japanese', 'Korean', 'English', 'Chinese', 'All'];

Future<void> showSearchFilterSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        maxChildSize: 0.95,
        builder: (context, scroll) => SearchFilterSheet(scroll: scroll),
      ),
    );

class SearchFilterSheet extends ConsumerStatefulWidget {
  const SearchFilterSheet({super.key, this.scroll});
  final ScrollController? scroll;

  @override
  ConsumerState<SearchFilterSheet> createState() => _SearchFilterSheetState();
}

class _SearchFilterSheetState extends ConsumerState<SearchFilterSheet> {
  late final TextEditingController _author =
      TextEditingController(text: ref.read(searchAuthorProvider));
  late final TextEditingController _publisher =
      TextEditingController(text: ref.read(searchPublisherProvider));

  @override
  void dispose() {
    _author.dispose();
    _publisher.dispose();
    super.dispose();
  }

  void _set(StateProvider<String> state, String pref, String value) {
    ref.read(state.notifier).state = value;
    MyLibraryDb.instance.savePreference(pref, value).catchError((_) {});
  }

  void _reset() {
    _set(selectedLanguageState, 'filterLanguage', 'Japanese');
    _set(selectedFileTypeState, 'filterFileType', 'Epub');
    _set(selectedSortState, 'filterSort', 'Most Relevant');
    _set(selectedTypeState, 'filterType', 'All');
    _set(selectedYearState, 'filterYear', 'All');
    _author.clear();
    _publisher.clear();
    ref.read(searchAuthorProvider.notifier).state = '';
    ref.read(searchPublisherProvider.notifier).state = '';
  }

  Widget _title(String text) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(text,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );

  Widget _chips(List<String> keys, String selected, String Function(String) label,
          void Function(String) onPick, {String prefix = ''}) =>
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final k in keys)
          ChoiceChip(
            key: ValueKey('$prefix$k'),
            label: Text(label(k)),
            selected: selected == k,
            showCheckmark: false,
            onSelected: (_) => onPick(k),
          ),
      ]);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labels = FilterLabels(l10n);
    final f = SearchFilters.of(ref);
    final otherLanguages = languageValues.keys
        .where((k) => !quickLanguages.contains(k))
        .toList();
    final otherSelected = !quickLanguages.contains(f.language);
    final scheme = Theme.of(context).colorScheme;
    InputDecoration field(String label) => InputDecoration(
          labelText: label,
          filled: true,
          fillColor: scheme.surfaceContainerHighest.withAlpha(140),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none),
          isDense: true,
        );

    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      children: [
        Row(children: [
          Expanded(
            child: Text(l10n.searchFilters,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          TextButton(
            key: const ValueKey('filterReset'),
            onPressed: _reset,
            child: Text(l10n.filterReset),
          ),
        ]),
        _title(l10n.filterLanguage),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final k in quickLanguages)
            ChoiceChip(
              key: ValueKey('lang-$k'),
              label: Text(labels.language(k)),
              selected: f.language == k,
              showCheckmark: false,
              onSelected: (_) =>
                  _set(selectedLanguageState, 'filterLanguage', k),
            ),
          PopupMenuButton<String>(
            tooltip: l10n.filterOther,
            onSelected: (k) => _set(selectedLanguageState, 'filterLanguage', k),
            itemBuilder: (_) => [
              for (final k in otherLanguages)
                PopupMenuItem(value: k, child: Text(k)),
            ],
            child: Chip(
              label: Text(otherSelected ? f.language : l10n.filterOther),
              backgroundColor: otherSelected ? scheme.secondaryContainer : null,
              avatar: const Icon(Icons.expand_more, size: 18),
            ),
          ),
        ]),
        _title(l10n.filterFormat),
        _chips(fileType, f.fileType, labels.fileType,
            (k) => _set(selectedFileTypeState, 'filterFileType', k),
            prefix: 'format-'),
        _title(l10n.filterSort),
        _chips(sortValues.keys.toList(), f.sort, labels.sort,
            (k) => _set(selectedSortState, 'filterSort', k),
            prefix: 'sort-'),
        _title(l10n.filterType),
        _chips(typeValues.keys.toList(), f.type, labels.type,
            (k) => _set(selectedTypeState, 'filterType', k),
            prefix: 'type-'),
        _title(l10n.filterYear),
        DropdownButtonFormField<String>(
          key: const ValueKey('filterYear'),
          initialValue: f.year,
          decoration: field(l10n.filterYear),
          items: [
            for (final y in yearValues)
              DropdownMenuItem(value: y, child: Text(labels.year(y))),
          ],
          onChanged: (y) =>
              _set(selectedYearState, 'filterYear', y ?? 'All'),
        ),
        _title(l10n.advancedSearch),
        TextField(
          key: const ValueKey('filterAuthor'),
          controller: _author,
          decoration: field(l10n.author),
          onChanged: (v) =>
              ref.read(searchAuthorProvider.notifier).state = v.trim(),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('filterPublisher'),
          controller: _publisher,
          decoration: field(l10n.publisher),
          onChanged: (v) =>
              ref.read(searchPublisherProvider.notifier).state = v.trim(),
        ),
        const SizedBox(height: 20),
        FilledButton(
          key: const ValueKey('filterDone'),
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.filterDone),
        ),
      ],
    );
  }
}
