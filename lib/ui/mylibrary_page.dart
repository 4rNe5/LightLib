// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:openlib/l10n/app_localizations.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

// Project imports:
import 'package:file_picker/file_picker.dart';
import 'package:openlib/services/files.dart' show syncLibraryWithDisk;
import 'package:openlib/services/local_book_import.dart';
import 'package:openlib/services/translation/book_translation_service.dart';
import 'package:openlib/services/translation/series_glossary.dart';
import 'package:openlib/services/library_organization.dart';
import 'package:openlib/services/platform_utils.dart';
import 'package:openlib/state/state.dart';
import 'package:openlib/ui/components/active_downloads_widget.dart';
import 'package:openlib/ui/components/error_widget.dart';
import 'package:openlib/ui/components/glossary_sheet.dart';
import 'package:openlib/ui/components/hide_cover_controls.dart';
import 'package:openlib/services/reading_recap.dart';
import 'package:openlib/ui/components/library_recap.dart';
import 'package:openlib/ui/components/library_tiles.dart';
import 'package:openlib/ui/components/series_name_dialog.dart';
import 'package:openlib/ui/mybook_page.dart';
import 'package:openlib/ui/study_page.dart';

class MyLibraryPage extends ConsumerStatefulWidget {
  const MyLibraryPage({super.key});

  @override
  ConsumerState<MyLibraryPage> createState() => _MyLibraryPageState();
}

class _MyLibraryPageState extends ConsumerState<MyLibraryPage> {
  bool _isRefreshing = false;

  /// The books being chosen (long press starts it), by id.
  final Set<String> _selected = {};
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  bool _hasTriggeredRefresh = false;

  static const _sortPrefKey = 'librarySortMode';

  @override
  void initState() {
    super.initState();
    _restoreSortMode();
    // Reading days may have changed since the recap was last built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(readingRecapProvider);
    });
    // A book that just finished downloading joins the translation queue.
    ref.listenManual(myLibraryProvider, (_, __) {
      BookTranslationService.instance.scanSoon();
    });
    // On desktop, listen for scroll to bottom to trigger refresh
    if (PlatformUtils.isDesktop) {
      _scrollController.addListener(_onScroll);
    }
  }

  /// Loads the persisted sort mode; unknown values fall back to the default.
  Future<void> _restoreSortMode() async {
    try {
      final stored = await dataBase.getPreference(_sortPrefKey);
      if (stored is String) {
        ref.read(librarySortModeProvider.notifier).state =
            LibrarySortMode.fromKey(stored);
      }
    } catch (_) {
      // Not saved yet: default is already in place.
    }
  }

  Future<void> _persistSortMode(LibrarySortMode mode) async {
    ref.read(librarySortModeProvider.notifier).state = mode;
    await dataBase.savePreference(_sortPrefKey, mode.key);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Trigger refresh when scrolled to bottom on desktop
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 50) {
      if (!_hasTriggeredRefresh && !_isRefreshing) {
        _hasTriggeredRefresh = true;
        _refreshLibrary();
      }
    } else {
      _hasTriggeredRefresh = false;
    }
  }

  Future<void> _refreshLibrary() async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
    });

    try {
      // Sync library with disk (remove missing files, add new ones)
      await syncLibraryWithDisk();
      BookTranslationService.instance.scanSoon();
      // Invalidate the provider to force UI refresh
      ref.invalidate(myLibraryProvider);
      ref.invalidate(libraryBooksProvider);
      ref.invalidate(libraryTagsProvider);
      await Future.delayed(const Duration(milliseconds: 300));
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  bool _importing = false;

  /// Picks EPUB/PDF files from the device and adds them to the library.
  Future<void> _importLocalBooks() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles(
        dialogTitle: l10n.importBooks,
        type: FileType.custom,
        allowedExtensions: importableBookExtensions,
      );
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.importBooksFailed)));
      return;
    }
    final paths = picked.map((f) => f.path).whereType<String>().toList();
    if (paths.isEmpty) return;

    setState(() => _importing = true);
    try {
      final results = await LocalBookImporter().importAll(paths);
      await FilePicker.clearTemporaryFiles().catchError((_) => false);
      ref.invalidate(myLibraryProvider);
      ref.invalidate(libraryBooksProvider);
      ref.invalidate(libraryTagsProvider);
      // New books join the background translation queue.
      BookTranslationService.instance.scanSoon();
      int count(LocalImportOutcome o) =>
          results.where((r) => r.outcome == o).length;
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.importBooksResult(
          count(LocalImportOutcome.imported),
          count(LocalImportOutcome.alreadyInLibrary),
          count(LocalImportOutcome.failed),
        )),
      ));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Widget _buildImportButton(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton.filledTonal(
      key: const ValueKey('importLocalBooks'),
      tooltip: AppLocalizations.of(context).importBooks,
      onPressed: _importing ? null : _importLocalBooks,
      icon: _importing
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: scheme.onSecondaryContainer),
            )
          : const Icon(Icons.add),
    );
  }

  /// Large title with the book count, then import / sort / sync.
  Widget _buildHeader(BuildContext context, int count) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final sortMode = ref.watch(librarySortModeProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 0, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.navMyLibrary,
                  style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5),
                ),
                Text(
                  l10n.libraryBookCount(count),
                  style:
                      TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('libraryWordBook'),
            tooltip: l10n.studyWordBook,
            icon: const Icon(Icons.style_outlined),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const StudyPage())),
          ),
          _buildImportButton(context),
          PopupMenuButton<LibrarySortMode>(
            tooltip: l10n.sortLibrary,
            icon: const Icon(Icons.swap_vert),
            initialValue: sortMode,
            onSelected: _persistSortMode,
            itemBuilder: (BuildContext context) => [
              for (final mode in LibrarySortMode.values)
                CheckedPopupMenuItem(
                  value: mode,
                  checked: mode == sortMode,
                  child: Text(mode.label),
                ),
            ],
          ),
          if (PlatformUtils.isDesktop)
            IconButton(
              onPressed: _isRefreshing ? null : _refreshLibrary,
              tooltip: "Sync library with storage folder",
              icon: _isRefreshing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
            ),
        ],
      ),
    );
  }

  /// Metadata search box: filters the library by title, author,
  /// publisher or the info line (year, language) as you type.
  Widget _buildSearchField(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: _searchController,
      cursorColor: scheme.primary,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        hintText: AppLocalizations.of(context).searchLibraryHint,
        hintStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
        prefixIcon: const Icon(Icons.search, size: 20),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      style: const TextStyle(fontSize: 14),
      onChanged: (value) =>
          ref.read(librarySearchQueryProvider.notifier).state = value,
    );
  }

  /// The horizontal filter row: genres in the library, reading status,
  /// then collections.
  Widget _buildFilterChips(BuildContext context, List<LibraryBook> books) {
    final l10n = AppLocalizations.of(context);
    final tagFilter = ref.watch(libraryTagFilterProvider);
    final statusFilter = ref.watch(libraryStatusFilterProvider);
    final genreFilter = ref.watch(libraryGenreFilterProvider);
    final allTags =
        ref.watch(libraryTagsProvider).valueOrNull ?? const <String>{};
    final genres = {for (final b in books) b.genre}.whereType<BookGenre>();
    final presentGenres = [
      for (final g in BookGenre.values)
        if (genres.contains(g)) g
    ];

    Widget chip({
      required String label,
      required bool selected,
      required ValueChanged<bool> onSelected,
      IconData? icon,
      Key? key,
    }) =>
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: FilterChip(
            key: key,
            label: Text(label, style: const TextStyle(fontSize: 12)),
            avatar: icon == null
                ? null
                : Icon(icon,
                    size: 15, color: Theme.of(context).colorScheme.primary),
            selected: selected,
            showCheckmark: false,
            shape: const StadiumBorder(),
            onSelected: onSelected,
          ),
        );

    Widget statusChip(String label, ReadingStatus value) => chip(
          label: label,
          selected: statusFilter == value,
          onSelected: (_) => ref
              .read(libraryStatusFilterProvider.notifier)
              .state = statusFilter == value ? null : value,
        );

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final genre in presentGenres)
            chip(
              key: ValueKey('genreFilter-${genre.key}'),
              label: genreLabel(l10n, genre),
              icon: genreIcon(genre),
              selected: genreFilter == genre,
              onSelected: (_) => ref
                  .read(libraryGenreFilterProvider.notifier)
                  .state = genreFilter == genre ? null : genre,
            ),
          statusChip(l10n.statusUnread, ReadingStatus.unread),
          statusChip(l10n.statusInProgress, ReadingStatus.inProgress),
          statusChip(l10n.statusCompleted, ReadingStatus.completed),
          for (final tag in allTags)
            chip(
              label: tag,
              icon: Icons.label_outline,
              selected: tagFilter.contains(tag),
              onSelected: (selected) {
                final next = Set<String>.of(tagFilter);
                selected ? next.add(tag) : next.remove(tag);
                ref.read(libraryTagFilterProvider.notifier).state = next;
              },
            ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text, {String? trailing}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
      child: Row(
        children: [
          Text(text,
              style:
                  const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Text(trailing,
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }

  void _openBook(LibraryBook book) {
    Navigator.push(context, MaterialPageRoute(builder: (BuildContext context) {
      return BookPage(id: book.id);
    })).then((_) {
      // Reading moved the position, maybe finished the book, and added
      // a reading day: refresh statuses, the bento and the recap.
      if (mounted) ref.invalidate(libraryBooksProvider);
    });
  }

  void _toggleSelected(LibraryBook book) {
    // (A message still showing would lie over the bar of the chosen
    // books.)
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    setState(() {
      if (!_selected.remove(book.id)) _selected.add(book.id);
    });
  }

  /// A tile of [book]: opened by a tap, chosen by a long press - and,
  /// while books are being chosen, by a tap.
  Widget _tile(LibraryBook book) => LibraryGridTile(
        key: ValueKey('libraryBook-${book.id}'),
        book: book,
        selected: _selected.isEmpty ? null : _selected.contains(book.id),
        onTap: () =>
            _selected.isEmpty ? _openBook(book) : _toggleSelected(book),
        onLongPress: () => _toggleSelected(book),
      );

  /// Puts the chosen books in a series the reader names (or in one that
  /// exists, by its name).
  Future<void> _groupSelected(List<LibraryBook> all) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final chosen = [
      for (final b in all)
        if (_selected.contains(b.id)) b,
    ];
    if (chosen.isEmpty) return;
    final theirs = {for (final b in chosen) b.series}.whereType<String>();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => SeriesNameDialog(
        // The series they are in already, or what their titles say.
        initial: theirs.length == 1
            ? theirs.first
            : suggestedSeriesName(chosen.map((b) => b.title)),
        existing: [for (final s in librarySeries(all)) s.name],
      ),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    await dataBase.setSeries(chosen.map((b) => b.id), name.trim());
    setState(_selected.clear);
    ref.invalidate(libraryBooksProvider);
    messenger.showSnackBar(SnackBar(
        content: Text(l10n.seriesGrouped(chosen.length, name.trim()))));
    // What the volumes' glossaries settled is now the series'.
    unawaited(shareWithinSeries([for (final b in chosen) b.book.getFileName()])
        .catchError((_) => 0));
  }

  Future<void> _ungroupSelected(List<LibraryBook> all) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final chosen = [
      for (final b in all)
        if (_selected.contains(b.id) && b.series != null) b.id,
    ];
    if (chosen.isEmpty) return;
    await dataBase.setSeries(chosen, null);
    if (!mounted) return;
    setState(_selected.clear);
    ref.invalidate(libraryBooksProvider);
    messenger.showSnackBar(
        SnackBar(content: Text(l10n.seriesUngrouped(chosen.length))));
  }

  /// What can be done with the chosen books, over the foot of the list.
  Widget _buildSelectionBar(BuildContext context, List<LibraryBook> all) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final chosen = [
      for (final b in all)
        if (_selected.contains(b.id)) b,
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Material(
          key: const ValueKey('librarySelectionBar'),
          elevation: 6,
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  key: const ValueKey('librarySelectionClose'),
                  tooltip: l10n.close,
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(_selected.clear),
                ),
                Text(l10n.librarySelected(chosen.length),
                    maxLines: 1,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                // (The actions keep to the room there is: a long label
                // is cut short, never the row.)
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (chosen.length == 1)
                        IconButton(
                          key: const ValueKey('librarySelectionTags'),
                          visualDensity: VisualDensity.compact,
                          tooltip: l10n.librarySelectionTags,
                          icon: const Icon(Icons.label_outline),
                          onPressed: () {
                            final book = chosen.single;
                            setState(_selected.clear);
                            _openTagEditor(book);
                          },
                        ),
                      if (chosen.any((b) => b.series != null))
                        IconButton(
                          key: const ValueKey('seriesUngroup'),
                          visualDensity: VisualDensity.compact,
                          tooltip: l10n.seriesUngroup,
                          icon: const Icon(Icons.layers_clear_outlined),
                          onPressed: () => _ungroupSelected(all),
                        ),
                      Flexible(
                        // (No icon: a button with one does not let its
                        // label give way.)
                        child: FilledButton.tonal(
                          key: const ValueKey('seriesGroup'),
                          onPressed: () => _groupSelected(all),
                          child: Text(l10n.seriesGroup,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// A series the reader made: its name, and its volumes in one row, in
  /// order.
  Widget _buildSeriesRow(BuildContext context, LibrarySeries series) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    const tileWidth = 92.0;
    return Container(
      key: ValueKey('librarySeries-${series.name}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 0, 6),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 12, bottom: 10),
            child: Row(
              children: [
                Icon(Icons.collections_bookmark_outlined,
                    size: 16, color: scheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(series.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                Text(l10n.seriesVolumes(series.volumes.length),
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
                // The series' glossary (its volumes share one): a word
                // set right there is translated again in every volume.
                IconButton(
                  key: ValueKey('seriesGlossary-${series.name}'),
                  tooltip: l10n.glossaryTitle,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 32),
                  iconSize: 18,
                  icon: const Icon(Icons.menu_book_outlined),
                  onPressed: () => showGlossarySheet(
                    context,
                    bookFile: series.volumes.first.book.getFileName(),
                    series: [
                      for (final v in series.volumes) v.book.getFileName(),
                    ],
                    seriesName: series.name,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: tileWidth * 1.5 + LibraryGridTile.captionHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: 12),
              itemCount: series.volumes.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) =>
                  SizedBox(width: tileWidth, child: _tile(series.volumes[i])),
            ),
          ),
        ],
      ),
    );
  }

  /// Cover grid: as many columns as fit (at least three on phones), each
  /// tile a 2:3 cover plus its caption.
  Widget _buildGrid(List<LibraryBook> books) {
    return SliverLayoutBuilder(builder: (context, constraints) {
      const spacing = 14.0;
      final width = constraints.crossAxisExtent;
      final columns = (width / 150).floor().clamp(3, 8);
      final tileWidth = (width - spacing * (columns - 1)) / columns;
      return SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: spacing,
          mainAxisSpacing: 18,
          mainAxisExtent: tileWidth * 1.5 + LibraryGridTile.captionHeight,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => _tile(books[index]),
          childCount: books.length,
        ),
      );
    });
  }

  void _openTagEditor(LibraryBook item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      backgroundColor:
          modernSurfaceTheme(Theme.of(context)).colorScheme.surfaceContainerLow,
      builder: (BuildContext sheetContext) {
        return Theme(
          data: modernSurfaceTheme(Theme.of(sheetContext)),
          child: _TagEditorSheet(
              bookId: item.id, title: item.title, genre: item.genre),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => Theme(
        data: modernSurfaceTheme(Theme.of(context)),
        child: Builder(builder: _buildLibrary),
      );

  Widget _buildLibrary(BuildContext context) {
    final libraryBooks = ref.watch(libraryBooksProvider);
    return libraryBooks.when(
      data: (data) {
        final organized = ref.watch(organizedLibraryProvider);
        final anyFilterActive =
            ref.watch(libraryTagFilterProvider).isNotEmpty ||
                ref.watch(libraryStatusFilterProvider) != null ||
                ref.watch(libraryGenreFilterProvider) != null ||
                ref.watch(librarySearchQueryProvider).trim().isNotEmpty;
        // The series the reader made, each in a row of its own; the grid
        // under them has the books that are in none. While something is
        // being looked for, every book that matches is in the grid.
        final series = anyFilterActive
            ? const <LibrarySeries>[]
            : librarySeries(organized);
        final loose = series.isEmpty
            ? organized
            : [
                for (final b in organized)
                  if (b.series == null || b.series!.isEmpty) b,
              ];
        _selected.removeWhere((id) => !data.any((b) => b.id == id));
        if (data.isNotEmpty) {
          final l10n = AppLocalizations.of(context);
          return PopScope(
            // Back leaves the choosing first.
            canPop: _selected.isEmpty,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) setState(_selected.clear);
            },
            child: Stack(children: [
              RefreshIndicator(
                onRefresh: () => _refreshLibrary(),
                child: CustomScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: <Widget>[
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          const ActiveDownloadsWidget(),
                          _buildHeader(context, data.length),
                          _buildSearchField(context),
                          const SizedBox(height: 8),
                          if (data.length > 1 || anyFilterActive)
                            _buildFilterChips(context, data),
                          if (!anyFilterActive) ...[
                            const SizedBox(height: 10),
                            LibraryBentoPanel(
                              key: const ValueKey('libraryBento'),
                              books: data,
                              onOpen: _openBook,
                              onLongPress: _openTagEditor,
                            ),
                            const LibraryRecapSection(),
                          ],
                          if (series.isNotEmpty) ...[
                            _sectionTitle(context, l10n.seriesSection,
                                trailing: '${series.length}'),
                            for (final s in series) _buildSeriesRow(context, s),
                          ],
                          if (loose.isNotEmpty || series.isEmpty)
                            _sectionTitle(
                              context,
                              l10n.libraryAllBooks,
                              trailing: '${loose.length}',
                            ),
                        ]),
                      ),
                    ),
                    if (organized.isEmpty && anyFilterActive)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Center(
                            child: Text(
                              l10n.libraryNoMatches,
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 13),
                            ),
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        // (Room for the bar of the chosen books.)
                        padding: EdgeInsets.fromLTRB(
                            16, 0, 16, _selected.isEmpty ? 24 : 96),
                        sliver: _buildGrid(loose),
                      ),
                    // Add scroll-to-refresh hint for desktop
                    if (PlatformUtils.isDesktop)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Center(
                            child: _isRefreshing
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .secondary,
                                    ),
                                  )
                                : Text(
                                    "Scroll down to sync library",
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: 12,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (_selected.isNotEmpty)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: _buildSelectionBar(context, data),
                ),
            ]),
          );
        } else {
          return RefreshIndicator(
            onRefresh: () => _refreshLibrary(),
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height * 0.7,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Add refresh button for desktop when library is empty
                    if (PlatformUtils.isDesktop)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Center(
                          child: IconButton(
                            onPressed: _isRefreshing ? null : _refreshLibrary,
                            icon: _isRefreshing
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .secondary,
                                    ),
                                  )
                                : Icon(
                                    Icons.refresh,
                                    color:
                                        Theme.of(context).colorScheme.secondary,
                                  ),
                          ),
                        ),
                      ),
                    SizedBox(
                      width: 200,
                      child: SvgPicture.asset(
                        'assets/empty_mylib.svg',
                        width: 200,
                      ),
                    ),
                    const SizedBox(
                      height: 30,
                    ),
                    Text(
                      AppLocalizations.of(context).libraryEmpty,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                        AppLocalizations.of(context).libraryEmptyHint,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: FilledButton.icon(
                        key: const ValueKey('importLocalBooksEmpty'),
                        onPressed: _importing ? null : _importLocalBooks,
                        icon: const Icon(Icons.file_open_outlined),
                        label: Text(AppLocalizations.of(context).importBooks),
                      ),
                    )
                  ],
                ),
              ),
            ),
          );
        }
      },
      error: (error, _) {
        return CustomErrorWidget(error: error, stackTrace: StackTrace.empty);
      },
      loading: () {
        return Center(
            child: SizedBox(
          width: 25,
          height: 25,
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.secondary,
          ),
        ));
      },
    );
  }
}

/// Bottom sheet to manage one book's tags: toggle existing tags, create
/// new ones inline, and see the book's current set at a glance.
class _TagEditorSheet extends ConsumerStatefulWidget {
  const _TagEditorSheet(
      {required this.bookId, required this.title, this.genre});

  final String bookId;
  final String title;
  final BookGenre? genre;

  @override
  ConsumerState<_TagEditorSheet> createState() => _TagEditorSheetState();
}

class _TagEditorSheetState extends ConsumerState<_TagEditorSheet> {
  late Future<Set<String>> _bookTags;
  late BookGenre? _genre = widget.genre;

  @override
  void initState() {
    super.initState();
    _bookTags = dataBase.getTags(widget.bookId);
  }

  Future<void> _setGenre(BookGenre? genre) async {
    setState(() => _genre = genre);
    await dataBase.setGenre(widget.bookId, genre?.key);
    // The filter would hide the book whose genre just changed.
    final filter = ref.read(libraryGenreFilterProvider);
    if (filter != null && filter != genre) {
      final books = await dataBase.getGenresForAll();
      if (!books.values.contains(filter.key)) {
        ref.read(libraryGenreFilterProvider.notifier).state = null;
      }
    }
    ref.invalidate(libraryBooksProvider);
  }

  void _reload() {
    setState(() {
      _bookTags = dataBase.getTags(widget.bookId);
    });
    ref.invalidate(myLibraryProvider);
    ref.invalidate(libraryBooksProvider);
    ref.invalidate(libraryTagsProvider);
  }

  Future<void> _addTag(String rawTag) async {
    final tag = rawTag.trim();
    if (tag.isEmpty) return;
    await dataBase.addTag(widget.bookId, tag);
    _reload();
  }

  Future<void> _removeTag(String tag) async {
    await dataBase.removeTag(widget.bookId, tag);
    // Drop the tag from active filters if it just vanished everywhere.
    final remaining = await dataBase.getAllTags();
    if (!remaining.contains(tag)) {
      final filter = Set<String>.of(ref.read(libraryTagFilterProvider));
      filter.remove(tag);
      ref.read(libraryTagFilterProvider.notifier).state = filter;
    }
    _reload();
  }

  Future<void> _createTag() async {
    final controller = TextEditingController();
    final dialogL10n = AppLocalizations.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogL10n.newCollection),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: dialogL10n.collectionNameHint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(dialogL10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(dialogL10n.add),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await _addTag(name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allTags =
        ref.watch(libraryTagsProvider).valueOrNull ?? const <String>{};
    return FutureBuilder<Set<String>>(
      future: _bookTags,
      builder: (context, snapshot) {
        final bookTags = snapshot.data ?? const <String>{};
        final l10n = AppLocalizations.of(context);
        final labelStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600);
        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                HideCoverSwitch(bookId: widget.bookId),
                const SizedBox(height: 8),
                Text(l10n.bookGenre, style: labelStyle),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      key: const ValueKey('genreChoice-none'),
                      label: Text(l10n.genreNone,
                          style: const TextStyle(fontSize: 12)),
                      selected: _genre == null,
                      onSelected: (_) => _setGenre(null),
                    ),
                    for (final genre in BookGenre.values)
                      ChoiceChip(
                        key: ValueKey('genreChoice-${genre.key}'),
                        avatar: Icon(genreIcon(genre), size: 15),
                        label: Text(genreLabel(l10n, genre),
                            style: const TextStyle(fontSize: 12)),
                        selected: _genre == genre,
                        showCheckmark: false,
                        onSelected: (_) => _setGenre(genre),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(l10n.bookCollections, style: labelStyle),
                const SizedBox(height: 4),
                Text(
                  l10n.manageCollectionsHint,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in allTags)
                      FilterChip(
                        label: Text(tag, style: const TextStyle(fontSize: 12)),
                        selected: bookTags.contains(tag),
                        onSelected: (selected) =>
                            selected ? _addTag(tag) : _removeTag(tag),
                      ),
                    ActionChip(
                      label: Text(AppLocalizations.of(context).newCollection,
                          style: const TextStyle(fontSize: 12)),
                      avatar: const Icon(Icons.add, size: 15),
                      onPressed: _createTag,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
