// The Search tab: one field, the filters behind its button (a sheet), and
// what helps fill it in - recent searches, titles from BOOK☆WALKER and
// Google (in Japanese), and for a Korean title the Japanese one it was
// published under. Suggestions only fill the field: the results come from
// the libraries, so they are always books that can be downloaded.

// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/bookwalker.dart';
import 'package:openlib/services/google_suggest_api.dart';
import 'package:openlib/services/original_title.dart';
import 'package:openlib/services/search_history.dart';
import 'package:openlib/state/state.dart'
    show enableFiltersState, searchQueryProvider;
import 'package:openlib/ui/components/active_downloads_widget.dart';
import 'package:openlib/ui/components/page_title_widget.dart';
import 'package:openlib/ui/components/search_filter_sheet.dart';
import 'package:openlib/ui/results_page.dart';
import 'components/snack_bar_widget.dart';

/// Google's suggestions for what is typed.
final searchSuggestionProvider = StateProvider<List<String>>((ref) => []);

/// BOOK☆WALKER's titles for what is typed.
final storeSuggestionProvider =
    StateProvider<List<BookWalkerBook>>((ref) => []);
final suggestionsLoadingProvider = StateProvider<bool>((ref) => false);

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({
    super.key,
    this.suggestApi,
    this.store,
    this.originalTitles,
  });

  /// Replaceable in tests (no network there).
  final GoogleSuggestApi? suggestApi;
  final Future<List<BookWalkerBook>> Function(String word)? store;
  final OriginalTitles? originalTitles;

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  Timer? _debounce;
  late final TextEditingController _controller;
  late final GoogleSuggestApi _google = widget.suggestApi ?? GoogleSuggestApi();
  late final Future<List<BookWalkerBook>> Function(String) _store =
      widget.store ?? BookWalker.instance.suggest;
  late final OriginalTitles _originals =
      widget.originalTitles ?? OriginalTitles.instance;

  /// The Japanese titles found for the Korean text typed: null before
  /// asking, empty when none.
  List<String>? _original;
  String _originalFor = '';
  bool _originalLoading = false;
  bool _originalNoEngine = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(searchQueryProvider));
    ref.listenManual(searchQueryProvider, (previous, next) {
      if (_controller.text != next) {
        _controller.text = next;
        _controller.selection =
            TextSelection.fromPosition(TextPosition(offset: next.length));
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _fetchSuggestions(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      ref.read(searchSuggestionProvider.notifier).state = [];
      ref.read(storeSuggestionProvider.notifier).state = [];
      ref.read(suggestionsLoadingProvider.notifier).state = false;
      return;
    }
    ref.read(suggestionsLoadingProvider.notifier).state = true;
    // A Korean title already looked up shows its Japanese titles again.
    if (hasHangul(q) && q != _originalFor) {
      final kept = await _originals.known(q);
      if (mounted && ref.read(searchQueryProvider).trim() == q) {
        setState(() {
          _originalFor = q;
          _original = kept;
          _originalNoEngine = false;
        });
      }
    }
    final results = await Future.wait([
      _google.fetchSuggestions(q, language: hasHangul(q) ? 'ko' : 'ja'),
      _store(q).catchError((_) => <BookWalkerBook>[]),
    ]);
    if (!mounted || ref.read(searchQueryProvider).trim() != q) return;
    ref.read(searchSuggestionProvider.notifier).state =
        results[0] as List<String>;
    ref.read(storeSuggestionProvider.notifier).state =
        (results[1] as List<BookWalkerBook>).take(6).toList();
    ref.read(suggestionsLoadingProvider.notifier).state = false;
  }

  void _onChanged(String value) {
    ref.read(searchQueryProvider.notifier).state = value;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      _fetchSuggestions(value);
    });
    setState(() {});
  }

  void _fill(String query) {
    ref.read(searchQueryProvider.notifier).state = query;
    _fetchSuggestions(query);
  }

  void _searchFor(String query) {
    ref.read(searchQueryProvider.notifier).state = query;
    _submit();
  }

  void _clear() {
    ref.read(searchQueryProvider.notifier).state = '';
    ref.read(searchSuggestionProvider.notifier).state = [];
    ref.read(storeSuggestionProvider.notifier).state = [];
    ref.read(suggestionsLoadingProvider.notifier).state = false;
    setState(() {});
  }

  void _submit() {
    final query = ref.read(searchQueryProvider);
    if (query.trim().isEmpty) {
      showSnackBar(
          context: context,
          message: AppLocalizations.of(context).searchEmptyField);
      return;
    }
    recordSearch(ref, query.trim());
    ref.read(searchSuggestionProvider.notifier).state = [];
    ref.read(storeSuggestionProvider.notifier).state = [];
    ref.read(enableFiltersState.notifier).state = true;
    FocusScope.of(context).unfocus();
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => ResultPage(searchQuery: query.trim())));
  }

  Future<void> _findOriginal(String korean) async {
    setState(() {
      _originalLoading = true;
      _originalFor = korean;
      _originalNoEngine = false;
    });
    List<String>? titles;
    try {
      titles = await _originals.lookup(korean);
    } catch (_) {
      titles = const [];
    }
    if (!mounted) return;
    setState(() {
      _originalLoading = false;
      _originalNoEngine = titles == null;
      _original = titles ?? const [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final typed = ref.watch(searchQueryProvider);
    final google = ref.watch(searchSuggestionProvider);
    final store = ref.watch(storeSuggestionProvider);
    final loading = ref.watch(suggestionsLoadingProvider);
    final history =
        ref.watch(searchHistoryProvider).valueOrNull ?? const <String>[];
    final historyMatches = matchingHistory(history, typed);
    final filters = SearchFilters.of(ref);
    final q = typed.trim();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 24),
      children: [
        const ActiveDownloadsWidget(),
        LargeTitle(l10n.navSearch, padding: const EdgeInsets.fromLTRB(4, 0, 0, 12)),
        _SearchBox(
          controller: _controller,
          hint: l10n.searchHint,
          loading: loading,
          activeFilters: filters.active,
          onChanged: _onChanged,
          onSubmitted: (_) => _submit(),
          onClear: _clear,
          onFilters: () => showSearchFilterSheet(context),
        ),
        _FilterSummary(filters: filters),
        if (q.isEmpty) ...[
          if (history.isNotEmpty)
            _RecentSearches(history: history, onSearch: _searchFor, onFill: _fill),
        ] else ...[
          if (hasHangul(q))
            _OriginalTitleRow(
              korean: q,
              titles: _originalFor == q ? _original : null,
              loading: _originalLoading && _originalFor == q,
              noEngine: _originalNoEngine && _originalFor == q,
              onFind: () => _findOriginal(q),
              onSearch: _searchFor,
            ),
          _Suggestions(
            history: historyMatches,
            store: store,
            google: [
              for (final s in google)
                if (!historyMatches.contains(s) && s != q) s,
            ].take(6).toList(),
            onSearch: _searchFor,
            onFill: _fill,
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// The field
// ---------------------------------------------------------------------------

class _SearchBox extends StatelessWidget {
  const _SearchBox({
    required this.controller,
    required this.hint,
    required this.loading,
    required this.activeFilters,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
    required this.onFilters,
  });

  final TextEditingController controller;
  final String hint;
  final bool loading;
  final int activeFilters;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final VoidCallback onFilters;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 4),
        child: Row(children: [
          loading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: scheme.secondary))
              : Icon(Icons.search, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              key: const ValueKey('searchField'),
              controller: controller,
              textInputAction: TextInputAction.search,
              cursorColor: scheme.secondary,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(
                    color: scheme.onSurfaceVariant.withAlpha(170),
                    fontWeight: FontWeight.w500),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onChanged: onChanged,
              onSubmitted: onSubmitted,
            ),
          ),
          if (controller.text.isNotEmpty)
            IconButton(
              key: const ValueKey('searchClear'),
              tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
              icon: const Icon(Icons.close, size: 20),
              onPressed: () {
                controller.clear();
                onClear();
              },
            ),
          IconButton(
            key: const ValueKey('searchFilters'),
            tooltip: l10n.searchFilters,
            onPressed: onFilters,
            icon: Badge(
              isLabelVisible: activeFilters > 0,
              backgroundColor: scheme.secondary,
              label: Text('$activeFilters'),
              child: const Icon(Icons.tune),
            ),
          ),
        ]),
      ),
    );
  }
}

/// The filters in force, as small chips under the field; a tap opens
/// the sheet.
class _FilterSummary extends StatelessWidget {
  const _FilterSummary({required this.filters});
  final SearchFilters filters;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labels = FilterLabels(l10n);
    final f = filters;
    final items = <String>[
      if (f.language != 'All') labels.language(f.language),
      if (f.fileType != 'All') labels.fileType(f.fileType),
      if (f.sort != 'Most Relevant') labels.sort(f.sort),
      if (f.type != 'All') labels.type(f.type),
      if (f.year != 'All') labels.year(f.year),
      if (f.author.isNotEmpty) '${l10n.author}: ${f.author}',
      if (f.publisher.isNotEmpty) '${l10n.publisher}: ${f.publisher}',
    ];
    if (items.isEmpty) return const SizedBox(height: 8);
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      key: const ValueKey('filterSummary'),
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(top: 10, left: 4),
        children: [
          for (final label in items)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => showSearchFilterSheet(context),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer.withAlpha(150),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSecondaryContainer)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Suggestions
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 18, 0, 4),
        child: Row(children: [
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    super.key,
    required this.text,
    required this.onTap,
    this.leading,
    this.subtitle,
    this.trailing,
  });

  final String text;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(children: [
          SizedBox(
              width: 34,
              child: Center(
                  child: leading ??
                      Icon(Icons.search, size: 18, color: scheme.onSurfaceVariant))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ]),
      ),
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({
    required this.history,
    required this.store,
    required this.google,
    required this.onSearch,
    required this.onFill,
  });

  final List<String> history;
  final List<BookWalkerBook> store;
  final List<String> google;
  final ValueChanged<String> onSearch;
  final ValueChanged<String> onFill;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    Widget fillButton(String q) => IconButton(
          tooltip: l10n.searchHistoryFill,
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.north_west, size: 16, color: scheme.onSurfaceVariant),
          onPressed: () => onFill(q),
        );
    return Column(
      key: const ValueKey('searchSuggestions'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (history.isNotEmpty) const SizedBox(height: 10),
        for (final past in history)
          _SuggestionRow(
            key: ValueKey('historyMatch-$past'),
            text: past,
            leading:
                Icon(Icons.history, size: 18, color: scheme.onSurfaceVariant),
            trailing: fillButton(past),
            onTap: () => onSearch(past),
          ),
        if (store.isNotEmpty) _SectionLabel(l10n.searchStoreTitles),
        for (final book in store)
          _SuggestionRow(
            key: ValueKey('store-${book.title}'),
            text: book.searchQuery,
            subtitle: [
              if (book.author != null && book.author!.isNotEmpty) book.author!,
              if (book.title != book.searchQuery) book.title,
            ].join(' · '),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              // Small and short-lived: the memory cache is enough.
              child: Image.network(
                book.cover,
                width: 30,
                height: 42,
                cacheWidth: 90,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.menu_book_outlined, size: 18),
              ),
            ),
            trailing: fillButton(book.searchQuery),
            onTap: () => onSearch(book.searchQuery),
          ),
        if (google.isNotEmpty) _SectionLabel(l10n.searchSuggestions),
        for (final s in google)
          _SuggestionRow(
            key: ValueKey('suggestion-$s'),
            text: s,
            trailing: fillButton(s),
            onTap: () => onSearch(s),
          ),
      ],
    );
  }
}

/// For a Korean title: a button that asks the translation engine for the
/// Japanese title, then the titles it gave.
class _OriginalTitleRow extends StatelessWidget {
  const _OriginalTitleRow({
    required this.korean,
    required this.titles,
    required this.loading,
    required this.noEngine,
    required this.onFind,
    required this.onSearch,
  });

  final String korean;
  final List<String>? titles;
  final bool loading;
  final bool noEngine;
  final VoidCallback onFind;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final Widget body;
    if (loading) {
      body = Row(children: [
        SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: scheme.secondary)),
        const SizedBox(width: 10),
        Text(l10n.originalTitleSearching),
      ]);
    } else if (noEngine) {
      body = Text(l10n.originalTitleNoEngine,
          style: TextStyle(color: scheme.onSurfaceVariant));
    } else if (titles == null) {
      body = Align(
        alignment: Alignment.centerLeft,
        child: ActionChip(
          key: const ValueKey('findOriginalTitle'),
          avatar: const Icon(Icons.translate, size: 18),
          label: Text(l10n.findOriginalTitle),
          onPressed: onFind,
        ),
      );
    } else if (titles!.isEmpty) {
      body = Text(l10n.originalTitleNone,
          style: TextStyle(color: scheme.onSurfaceVariant));
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final t in titles!)
            _SuggestionRow(
              key: ValueKey('original-$t'),
              text: t,
              subtitle: korean,
              leading: Icon(Icons.translate, size: 18, color: scheme.secondary),
              onTap: () => onSearch(t),
            ),
        ],
      );
    }
    return Padding(
      key: const ValueKey('originalTitle'),
      padding: const EdgeInsets.only(top: 12),
      child: body,
    );
  }
}

// ---------------------------------------------------------------------------
// Recent searches
// ---------------------------------------------------------------------------

class _RecentSearches extends ConsumerStatefulWidget {
  const _RecentSearches({
    required this.history,
    required this.onSearch,
    required this.onFill,
  });

  final List<String> history;
  final ValueChanged<String> onSearch;
  final ValueChanged<String> onFill;

  @override
  ConsumerState<_RecentSearches> createState() => _RecentSearchesState();
}

class _RecentSearchesState extends ConsumerState<_RecentSearches> {
  static const _collapsed = 8;
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final items =
        _showAll ? widget.history : widget.history.take(_collapsed).toList();
    return Column(
      key: const ValueKey('recentSearches'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel(
          l10n.recentSearches,
          trailing: TextButton(
            key: const ValueKey('clearSearchHistory'),
            onPressed: () => clearSearches(ref),
            style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: scheme.onSurfaceVariant),
            child: Text(l10n.clearAll, style: const TextStyle(fontSize: 12)),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final query in items)
                _SuggestionRow(
                  key: ValueKey('history-$query'),
                  text: query,
                  leading: Icon(Icons.history,
                      size: 18, color: scheme.onSurfaceVariant),
                  trailing: IconButton(
                    tooltip: l10n.removeFromHistory,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.close,
                        size: 16, color: scheme.onSurfaceVariant),
                    onPressed: () => removeSearch(ref, query),
                  ),
                  onTap: () => widget.onSearch(query),
                ),
            ],
          ),
        ),
        if (widget.history.length > _collapsed)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _showAll = !_showAll),
              style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: scheme.onSurfaceVariant),
              icon: Icon(_showAll ? Icons.expand_less : Icons.expand_more,
                  size: 18),
              label: Text(_showAll ? l10n.showLess : l10n.showMore,
                  style: const TextStyle(fontSize: 12)),
            ),
          ),
      ],
    );
  }
}
