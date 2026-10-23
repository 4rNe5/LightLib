// Flutter imports:
import 'package:flutter/material.dart';
import 'package:openlib/l10n/app_localizations.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async'; // For Timer/Debounce

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/search_history.dart';
import 'package:openlib/ui/components/active_downloads_widget.dart';
import 'package:openlib/ui/components/page_title_widget.dart';
import 'package:openlib/ui/results_page.dart';
import 'components/snack_bar_widget.dart';
// Import the new API Service (adjust path as necessary)
import 'package:openlib/services/google_suggest_api.dart';

import 'package:openlib/state/state.dart'
    show
        searchAuthorProvider,
        searchPublisherProvider,
        searchQueryProvider,
        selectedTypeState,
        selectedSortState,
        selectedFileTypeState,
        selectedLanguageState,
        selectedYearState,
        typeValues,
        fileType,
        sortValues,
        languageValues,
        yearValues,
        enableFiltersState;

// ====================================================================
// Suggestion Providers (New)
// ====================================================================

// Provider to hold the list of suggestions
final searchSuggestionProvider = StateProvider<List<String>>((ref) => []);
// Provider to show/hide the loading indicator
final suggestionsLoadingProvider = StateProvider<bool>((ref) => false);

// ====================================================================
// SearchPage Implementation (Stateful Conversion for API & Debounce)
// ====================================================================

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  Timer? _debounce;
  late final TextEditingController _searchController;
  final TextEditingController _advancedController = TextEditingController();
  final GoogleSuggestApi _apiService =
      GoogleSuggestApi(); // Instantiate API service

  @override
  void initState() {
    super.initState();
    // Initialize controller with current state value
    _searchController =
        TextEditingController(text: ref.read(searchQueryProvider));

    // Listener to update the TextField when state changes (e.g., when a suggestion is tapped)
    ref.listenManual(searchQueryProvider, (previous, next) {
      if (_searchController.text != next) {
        _searchController.text = next;
        // Move cursor to the end
        _searchController.selection =
            TextSelection.fromPosition(TextPosition(offset: next.length));
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _advancedController.dispose();
    super.dispose();
  }

  // *** API LOGIC ***
  Future<void> _fetchSuggestions(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      ref.read(searchSuggestionProvider.notifier).state = [];
      return;
    }

    ref.read(suggestionsLoadingProvider.notifier).state = true;

    // Call the Google Suggest API function
    final realSuggestions = await _apiService.fetchSuggestions(cleanQuery);

    ref.read(searchSuggestionProvider.notifier).state = realSuggestions;
    ref.read(suggestionsLoadingProvider.notifier).state = false;
  }
  // *****************

  void _onSearchQueryChanged(String value) {
    // 1. Update the Riverpod state immediately
    ref.read(searchQueryProvider.notifier).state = value;

    // 2. Debounce the API call to limit requests while the user is typing
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _fetchSuggestions(value);
    });
  }

  /// Puts [query] in the field without searching (the arrow on a
  /// history row), so it can be edited first.
  void _fill(String query) {
    ref.read(searchQueryProvider.notifier).state = query;
    _fetchSuggestions(query);
  }

  void _searchFor(BuildContext context, String query) {
    ref.read(searchQueryProvider.notifier).state = query;
    ref.read(searchSuggestionProvider.notifier).state = [];
    onSubmit(context);
  }

  void onSubmit(BuildContext context) {
    final searchQuery = ref.read(searchQueryProvider);
    if (searchQuery.trim().isNotEmpty) {
      recordSearch(ref, searchQuery);
      // Clear suggestions list before navigating
      ref.read(searchSuggestionProvider.notifier).state = [];
      ref.read(enableFiltersState.notifier).state = true;
      Navigator.push(context,
          MaterialPageRoute(builder: (BuildContext context) {
        return ResultPage(searchQuery: searchQuery);
      }));
    } else {
      showSnackBar(context: context, message: 'Search field is empty');
    }
  }

  @override
  Widget build(BuildContext context) {
    // WidgetRef is available via ConsumerState
    final dropdownTypeValue = ref.watch(selectedTypeState);
    final dropdownSortValue = ref.watch(selectedSortState);
    final dropDownFileTypeValue = ref.watch(selectedFileTypeState);
    final dropdownLanguageValue = ref.watch(selectedLanguageState);
    final dropdownYearValue = ref.watch(selectedYearState);

    // Watch suggestion states
    final suggestions =
        ref.watch(searchSuggestionProvider); // The list of titles
    final isLoadingSuggestions =
        ref.watch(suggestionsLoadingProvider); // Loading state
    final typed = ref.watch(searchQueryProvider);
    final history =
        ref.watch(searchHistoryProvider).valueOrNull ?? const <String>[];
    final historyMatches = matchingHistory(history, typed);

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: Padding(
        padding: const EdgeInsets.only(left: 5, right: 5, top: 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            const ActiveDownloadsWidget(),
            Padding(
              padding: const EdgeInsets.fromLTRB(7, 0, 7, 0),
              child: LargeTitle(AppLocalizations.of(context).navSearch,
                  padding: EdgeInsets.zero),
            ),
            // Search Input Field
            Padding(
              padding: const EdgeInsets.only(left: 7, right: 7, top: 10),
              child: TextField(
                controller: _searchController, // <--- Added controller
                showCursor: true,
                cursorColor: Theme.of(context).colorScheme.secondary,
                decoration: InputDecoration(
                  enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey, width: 2),
                    borderRadius: BorderRadius.all(Radius.circular(50)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.tertiary,
                        width: 2),
                    borderRadius: const BorderRadius.all(Radius.circular(50)),
                  ),
                  suffixIcon: IconButton(
                    padding: const EdgeInsets.only(right: 5),
                    color: Theme.of(context).colorScheme.secondary,
                    icon:
                        isLoadingSuggestions // Show loading spinner if fetching suggestions
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.0,
                                  color:
                                      Theme.of(context).colorScheme.secondary,
                                ),
                              )
                            : const Icon(
                                Icons.search,
                                size: 23,
                              ),
                    onPressed: () => onSubmit(context), // <--- Simplified call
                  ),
                  filled: true,
                  hintStyle: const TextStyle(
                      color: Colors.grey, fontWeight: FontWeight.bold),
                  hintText: "Search",
                  // Remove explicit fillColor to use the theme default (Dark Grey in Dark Mode)
                ),
                onSubmitted: (String value) => onSubmit(context),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.tertiary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                onChanged:
                    _onSearchQueryChanged, // <--- Calls the debounced function
              ),
            ),

            // Recent searches while the field is empty.
            if (typed.trim().isEmpty && history.isNotEmpty)
              _RecentSearches(
                history: history,
                onSearch: (q) => _searchFor(context, q),
              ),

            // --- Suggestions List (NEW) ---
            if ((suggestions.isNotEmpty || historyMatches.isNotEmpty) &&
                typed.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 15, right: 15, top: 8),
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  elevation: 2,
                  clipBehavior: Clip.antiAlias,
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 250),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        // Earlier searches that match come first.
                        for (final past in historyMatches)
                          ListTile(
                            key: ValueKey('historyMatch-$past'),
                            dense: true,
                            leading: const Icon(Icons.history, size: 18),
                            title: Text(
                              past,
                              style: TextStyle(
                                  fontSize: 14,
                                  color:
                                      Theme.of(context).colorScheme.onSurface),
                            ),
                            trailing: IconButton(
                              tooltip: AppLocalizations.of(context)
                                  .searchHistoryFill,
                              icon: const Icon(Icons.north_west, size: 16),
                              onPressed: () => _fill(past),
                            ),
                            onTap: () => _searchFor(context, past),
                          ),
                        for (final suggestion in suggestions
                            .where((s) => !historyMatches.contains(s)))
                          Builder(builder: (context) {
                            return ListTile(
                              dense: true,
                              title: Text(
                                suggestion,
                                style: TextStyle(
                                    fontSize: 14,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface),
                              ),
                              leading: const Icon(Icons.book, size: 18),
                              onTap: () {
                                // 1. Update the state with the selected suggestion
                                ref.read(searchQueryProvider.notifier).state =
                                    suggestion;

                                // 2. Clear the suggestion list
                                ref
                                    .read(searchSuggestionProvider.notifier)
                                    .state = [];

                                // 3. Immediately perform search
                                onSubmit(context);
                              },
                            );
                          }),
                      ],
                    ),
                  ),
                ),
              ),
            // -----------------------------

            // --- Advanced Search Panel ---
            _AdvancedSearchPanel(controller: _advancedController),

            // Dropdown Filters (Unchanged)
            Padding(
              padding: const EdgeInsets.only(left: 7, right: 7, top: 19),
              child: SizedBox(
                width: 250,
                child: DropdownButtonFormField(
                  decoration: InputDecoration(
                    labelText: 'Type',
                    labelStyle: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    enabledBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey, width: 2),
                      borderRadius: BorderRadius.all(Radius.circular(50)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.tertiary,
                          width: 2),
                      borderRadius: const BorderRadius.all(Radius.circular(50)),
                    ),
                  ),
                  icon: const Icon(Icons.arrow_drop_down),
                  initialValue: dropdownTypeValue,
                  items: typeValues.keys
                      .toList()
                      .map<DropdownMenuItem<String>>((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(
                        value,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    );
                  }).toList(),
                  onChanged: (String? val) {
                    ref.read(selectedTypeState.notifier).state = val ?? '';
                    MyLibraryDb.instance
                        .savePreference('filterType', val ?? 'All');
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 7, right: 7, top: 19),
              child: SizedBox(
                width: 210,
                child: DropdownButtonFormField(
                  decoration: InputDecoration(
                    labelText: 'Sort by',
                    labelStyle: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    enabledBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey, width: 2),
                      borderRadius: BorderRadius.all(Radius.circular(50)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.tertiary,
                          width: 2),
                      borderRadius: const BorderRadius.all(Radius.circular(50)),
                    ),
                  ),
                  initialValue: dropdownSortValue,
                  items: sortValues.keys
                      .toList()
                      .map<DropdownMenuItem<String>>((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(
                        value,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    );
                  }).toList(),
                  onChanged: (String? val) {
                    ref.read(selectedSortState.notifier).state = val ?? '';
                    MyLibraryDb.instance
                        .savePreference('filterSort', val ?? 'Most Relevant');
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 7, right: 7, top: 19),
              child: SizedBox(
                width: 165,
                child: DropdownButtonFormField(
                  decoration: InputDecoration(
                    labelText: 'File type',
                    labelStyle: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    enabledBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey, width: 2),
                      borderRadius: BorderRadius.all(Radius.circular(50)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.tertiary,
                          width: 2),
                      borderRadius: const BorderRadius.all(Radius.circular(50)),
                    ),
                  ),
                  initialValue: dropDownFileTypeValue,
                  items: fileType.map<DropdownMenuItem<String>>((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(
                        value,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    );
                  }).toList(),
                  onChanged: (String? val) {
                    ref.read(selectedFileTypeState.notifier).state =
                        val ?? 'All';
                    MyLibraryDb.instance
                        .savePreference('filterFileType', val ?? 'All');
                  },
                ),
              ),
            ),
            // Language filter dropdown
            Padding(
              padding: const EdgeInsets.only(left: 7, right: 7, top: 19),
              child: SizedBox(
                width: 200,
                child: DropdownButtonFormField(
                  decoration: InputDecoration(
                    labelText: 'Language',
                    labelStyle: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    enabledBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey, width: 2),
                      borderRadius: BorderRadius.all(Radius.circular(50)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.tertiary,
                          width: 2),
                      borderRadius: const BorderRadius.all(Radius.circular(50)),
                    ),
                  ),
                  initialValue: dropdownLanguageValue,
                  items: languageValues.keys
                      .toList()
                      .map<DropdownMenuItem<String>>((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(
                        value,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    );
                  }).toList(),
                  onChanged: (String? val) {
                    ref.read(selectedLanguageState.notifier).state =
                        val ?? 'All';
                    MyLibraryDb.instance
                        .savePreference('filterLanguage', val ?? 'All');
                  },
                ),
              ),
            ),
            // Year filter dropdown
            Padding(
              padding: const EdgeInsets.only(left: 7, right: 7, top: 19),
              child: SizedBox(
                width: 180,
                child: DropdownButtonFormField(
                  decoration: InputDecoration(
                    labelText: 'Year Published',
                    labelStyle: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    enabledBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey, width: 2),
                      borderRadius: BorderRadius.all(Radius.circular(50)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.tertiary,
                          width: 2),
                      borderRadius: const BorderRadius.all(Radius.circular(50)),
                    ),
                  ),
                  initialValue: dropdownYearValue,
                  items:
                      yearValues.map<DropdownMenuItem<String>>((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(
                        value,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    );
                  }).toList(),
                  onChanged: (String? val) {
                    ref.read(selectedYearState.notifier).state = val ?? 'All';
                    MyLibraryDb.instance
                        .savePreference('filterYear', val ?? 'All');
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ====================================================================
// ADVANCED SEARCH PANEL
// Expandable metadata filters: author and publisher refine the plain
// text query into field-specific terms every provider understands.
// ====================================================================

class _AdvancedSearchPanel extends ConsumerStatefulWidget {
  const _AdvancedSearchPanel({required this.controller});

  /// The main search field's controller, kept for future synergy
  /// between the plain query and the metadata fields.
  final TextEditingController controller;

  @override
  ConsumerState<_AdvancedSearchPanel> createState() =>
      _AdvancedSearchPanelState();
}

class _AdvancedSearchPanelState extends ConsumerState<_AdvancedSearchPanel> {
  bool _expanded = false;
  late final TextEditingController _authorController;
  late final TextEditingController _publisherController;

  @override
  void initState() {
    super.initState();
    _authorController =
        TextEditingController(text: ref.read(searchAuthorProvider));
    _publisherController =
        TextEditingController(text: ref.read(searchPublisherProvider));
  }

  @override
  void dispose() {
    _authorController.dispose();
    _publisherController.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.secondary,
      ),
      enabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Colors.grey, width: 2),
        borderRadius: BorderRadius.all(Radius.circular(50)),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide:
            BorderSide(color: Theme.of(context).colorScheme.tertiary, width: 2),
        borderRadius: const BorderRadius.all(Radius.circular(50)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasActiveFields = ref.watch(searchAuthorProvider).isNotEmpty ||
        ref.watch(searchPublisherProvider).isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(left: 7, right: 7, top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Toggle row
          Row(
            children: [
              TextButton.icon(
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                label: Text(
                  AppLocalizations.of(context).advancedSearch,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
              ),
              if (hasActiveFields)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                    Icons.filter_alt,
                    size: 14,
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                ),
            ],
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: Column(
                children: [
                  TextField(
                    controller: _authorController,
                    decoration:
                        _decoration(AppLocalizations.of(context).author),
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold),
                    onChanged: (value) => ref
                        .read(searchAuthorProvider.notifier)
                        .state = value.trim(),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _publisherController,
                    decoration:
                        _decoration(AppLocalizations.of(context).publisher),
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold),
                    onChanged: (value) => ref
                        .read(searchPublisherProvider.notifier)
                        .state = value.trim(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ====================================================================
// RECENT SEARCHES
// Shown under the field while it is empty: the last searches as pills,
// newest first. Tap searches again, the x removes one.
// ====================================================================

class _RecentSearches extends ConsumerStatefulWidget {
  const _RecentSearches({required this.history, required this.onSearch});

  final List<String> history;
  final ValueChanged<String> onSearch;

  @override
  ConsumerState<_RecentSearches> createState() => _RecentSearchesState();
}

class _RecentSearchesState extends ConsumerState<_RecentSearches> {
  static const _collapsed = 10;
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final items =
        _showAll ? widget.history : widget.history.take(_collapsed).toList();

    return Padding(
      key: const ValueKey('recentSearches'),
      padding: const EdgeInsets.fromLTRB(12, 14, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.recentSearches,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton(
                key: const ValueKey('clearSearchHistory'),
                onPressed: () => clearSearches(ref),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: scheme.onSurfaceVariant,
                ),
                child:
                    Text(l10n.clearAll, style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final query in items)
                  _HistoryPill(
                    key: ValueKey('history-$query'),
                    query: query,
                    onTap: () => widget.onSearch(query),
                    onRemove: () => removeSearch(ref, query),
                    removeTooltip: l10n.removeFromHistory,
                  ),
              ],
            ),
          ),
          if (widget.history.length > _collapsed)
            TextButton.icon(
              onPressed: () => setState(() => _showAll = !_showAll),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: scheme.onSurfaceVariant,
              ),
              icon: Icon(_showAll ? Icons.expand_less : Icons.expand_more,
                  size: 18),
              label: Text(
                _showAll ? l10n.showLess : l10n.showMore,
                style: const TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class _HistoryPill extends StatelessWidget {
  const _HistoryPill({
    super.key,
    required this.query,
    required this.onTap,
    required this.onRemove,
    required this.removeTooltip,
  });

  final String query;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final String removeTooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: dark ? const Color(0xFF242424) : const Color(0xFFF1F1F3),
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(left: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  query,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              IconButton(
                tooltip: removeTooltip,
                visualDensity: VisualDensity.compact,
                iconSize: 15,
                color: scheme.onSurfaceVariant,
                onPressed: onRemove,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
