// A book's genre and collections, in a sheet: from a long press in the
// library and from the book's own page.

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/library_organization.dart';
import 'package:openlib/state/state.dart';
import 'package:openlib/ui/components/hide_cover_controls.dart';
import 'package:openlib/ui/components/library_tiles.dart';

void showBookTagEditor(
  BuildContext context, {
  required String bookId,
  required String title,
  BookGenre? genre,
}) {
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
        child: _BookTagEditor(bookId: bookId, title: title, genre: genre),
      );
    },
  );
}

/// Bottom sheet to manage one book's tags: toggle existing tags, create
/// new ones inline, and see the book's current set at a glance.
class _BookTagEditor extends ConsumerStatefulWidget {
  const _BookTagEditor(
      {required this.bookId, required this.title, this.genre});

  final String bookId;
  final String title;
  final BookGenre? genre;

  @override
  ConsumerState<_BookTagEditor> createState() => _BookTagEditorState();
}

class _BookTagEditorState extends ConsumerState<_BookTagEditor> {
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
