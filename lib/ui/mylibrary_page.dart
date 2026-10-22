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
import 'package:openlib/services/library_organization.dart';
import 'package:openlib/services/platform_utils.dart';
import 'package:openlib/state/state.dart';
import 'package:openlib/ui/components/active_downloads_widget.dart';
import 'package:openlib/ui/components/error_widget.dart';
import 'package:openlib/ui/components/library_tiles.dart';
import 'package:openlib/ui/mybook_page.dart';

class MyLibraryPage extends ConsumerStatefulWidget {
  const MyLibraryPage({super.key});

  @override
  ConsumerState<MyLibraryPage> createState() => _MyLibraryPageState();
}

class _MyLibraryPageState extends ConsumerState<MyLibraryPage> {
  bool _isRefreshing = false;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  bool _hasTriggeredRefresh = false;

  static const _sortPrefKey = 'librarySortMode';

  @override
  void initState() {
    super.initState();
    _restoreSortMode();
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
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Text(trailing,
                style:
                    TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }

  void _openBook(LibraryBook book) {
    Navigator.push(context,
        MaterialPageRoute(builder: (BuildContext context) {
      return BookPage(id: book.id);
    }));
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
          (context, index) {
            final book = books[index];
            return LibraryGridTile(
              key: ValueKey('libraryBook-${book.id}'),
              book: book,
              onTap: () => _openBook(book),
              onLongPress: () => _openTagEditor(book),
            );
          },
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
        if (data.isNotEmpty) {
          final l10n = AppLocalizations.of(context);
          return RefreshIndicator(
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
                      ],
                      _sectionTitle(
                        context,
                        l10n.libraryAllBooks,
                        trailing: '${organized.length}',
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
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    sliver: _buildGrid(organized),
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
                                  color:
                                      Theme.of(context).colorScheme.secondary,
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
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant),
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
                const SizedBox(height: 16),
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
