// The web build's home: the whole library - the books in this browser
// and the ones the account keeps - listed from titles, authors and small
// covers. A book's file is fetched when the book is opened.
//
// A wide window gets a side bar (what to show, the account, sync), a
// search box, sorting, a card to pick up the last book, hover and
// right-click on the tiles, and EPUBs dropped onto the window; a narrow
// one gets the same library under an app bar.

// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:file_picker/file_picker.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/local_book_import.dart';
import 'package:openlib/services/sync/library_sync_local.dart';
import 'package:openlib/services/sync/remote_library.dart';
import 'package:openlib/services/sync/sync_engine.dart';
import 'package:openlib/services/sync/sync_service.dart';
import 'package:openlib/web/browser.dart';
import 'package:openlib/web/web_book_dialog.dart';
import 'package:openlib/web/web_book_opening.dart';
import 'package:openlib/web/web_cover.dart';
import 'package:openlib/web/web_library.dart';
import 'package:openlib/web/web_settings_page.dart';

/// From this width the library is laid out for a desktop window.
const webWideLayout = 900.0;

class WebLibraryPage extends StatefulWidget {
  const WebLibraryPage({super.key, this.library, this.sync});

  /// Tests pass their own.
  final WebLibrary? library;
  final SyncService? sync;

  @override
  State<WebLibraryPage> createState() => _WebLibraryPageState();
}

class _WebLibraryPageState extends State<WebLibraryPage> {
  late final SyncService _sync = widget.sync ?? SyncService.instance;
  late final WebLibrary _library = widget.library ?? WebLibrary();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _pageFocus = FocusNode();
  WebFilter _filter = WebFilter.all;
  WebSort _sort = WebSort.recent;
  String _query = '';
  bool _searching = false;
  bool _adding = false;
  StreamSubscription<SyncReport>? _finished;
  VoidCallback? _stopDrops;

  @override
  void initState() {
    super.initState();
    _sync.onLocalChanges = _reload;
    _finished = _sync.finished.listen(_onSynced);
    _stopDrops = Browser.onFilesDropped((files) => unawaited(_addFiles([
          for (final f in files)
            if (f.name.toLowerCase().endsWith('.epub')) f,
        ])));
    HardwareKeyboard.instance.addHandler(_onKey);
    unawaited(_start());
  }

  Future<void> _start() async {
    // What the last visit listed shows at once; this visit's sync renews it.
    await RemoteLibraryStore.instance.load();
    await _library.reload();
  }

  void _reload() => unawaited(_library.reload());

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    if (_sync.onLocalChanges == _reload) _sync.onLocalChanges = null;
    _finished?.cancel();
    _stopDrops?.call();
    if (widget.library == null) _library.dispose();
    _search.dispose();
    _searchFocus.dispose();
    _pageFocus.dispose();
    super.dispose();
  }

  /// A run ended: said only when it failed or moved books (the side bar
  /// keeps the rest).
  void _onSynced(SyncReport report) {
    if (!mounted) return;
    final moved = report.uploaded > 0 || report.removedHere > 0;
    if (!moved && report.errors.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    _say(report.errors.isEmpty
        ? '${l10n.syncDoneTitle} · ${syncSummaryText(l10n, report)}'
        : l10n.syncFailed(report.errors.first));
  }

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(text),
          behavior: SnackBarBehavior.floating,
          width: 420));
  }

  Future<void> _pick() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['epub'],
    );
    if (picked.isEmpty) return;
    await _addFiles([
      for (final f in picked) (name: f.name, bytes: await f.readAsBytes()),
    ]);
  }

  Future<void> _addFiles(List<DroppedFile> files) async {
    if (files.isEmpty || _adding || !mounted) return;
    setState(() => _adding = true);
    var added = 0;
    for (final f in files) {
      final result = await importBookBytes(f.name, f.bytes);
      if (result.outcome == LocalImportOutcome.imported) added++;
    }
    if (!mounted) return;
    setState(() => _adding = false);
    await _library.reload();
    if (!mounted) return;
    _say(AppLocalizations.of(context).webAdded(added));
    if (added > 0 && _sync.auto) unawaited(_sync.syncNow());
  }

  Future<void> _details(WebBook book) async {
    final action = await showWebBookDialog(context, book);
    if (!mounted || action == null) return;
    switch (action) {
      case WebBookAction.read:
        await _read(book);
      case WebBookAction.removeCopy:
        await _removeCopy(book);
      case WebBookAction.delete:
        await _delete(book);
    }
  }

  Future<void> _read(WebBook book) async {
    await Navigator.of(context).push(WebBookOpenPage.route(book));
    if (mounted) _reload();
  }

  Future<void> _removeCopy(WebBook book) async {
    final l10n = AppLocalizations.of(context);
    final md5 = book.md5;
    var done = false;
    try {
      done = md5 != null && _sync.signedIn && await _sync.dropLocalCopy(md5);
    } catch (_) {}
    await _library.reload();
    _say(done ? l10n.webRemoveCopyDone : l10n.webRemoveCopyNotYet);
  }

  Future<void> _delete(WebBook book) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.webDeleteEverywhere),
        content: Text(l10n.webDeleteEverywhereConfirm(book.title)),
        actions: [
          TextButton(
              style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.onSurface),
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.webCancel)),
          ElevatedButton(
              key: const ValueKey('webDeleteConfirm'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.webDelete)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final md5 = book.md5;
      if (md5 != null && _sync.signedIn && book.onAccount) {
        await _sync.deleteBook(md5);
      } else if (book.local case final local?) {
        await LibrarySyncLocal().removeBook(LocalBook(
          id: local.id,
          fileName: local.getFileName(),
          title: local.title,
          author: local.author,
          format: 'epub',
        ));
      }
    } catch (e) {
      _say(l10n.syncFailed('$e'));
    }
    await _library.reload();
    if (_sync.signedIn && _sync.auto) unawaited(_sync.syncNow());
  }

  Future<void> _settings() async {
    await showWebSettings(context);
    if (mounted) _reload();
  }

  void _menu(WebBook book, Offset at) {
    final l10n = AppLocalizations.of(context);
    final size = MediaQuery.sizeOf(context);
    final resume = book.started && !book.finished;
    unawaited(showMenu<WebBookAction>(
      context: context,
      position: RelativeRect.fromLTRB(
          at.dx, at.dy, size.width - at.dx, size.height - at.dy),
      items: [
        PopupMenuItem(
            value: WebBookAction.read,
            child: Text(resume ? l10n.webContinue : l10n.webRead)),
        if (book.downloaded && book.onAccount)
          PopupMenuItem(
              value: WebBookAction.removeCopy, child: Text(l10n.webRemoveCopy)),
        PopupMenuItem(
            value: WebBookAction.delete,
            child: Text(l10n.webDeleteEverywhere,
                style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ],
    ).then((action) {
      if (!mounted || action == null) return;
      unawaited(switch (action) {
        WebBookAction.read => _read(book),
        WebBookAction.removeCopy => _removeCopy(book),
        WebBookAction.delete => _delete(book),
      });
    }));
  }

  /// "/" or Ctrl/⌘+K: the search box; Esc there: cleared. Heard wherever
  /// the focus is, while the library is the page in front.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    final key = event.logicalKey;
    final typing = _searchFocus.hasFocus;
    final chord = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if ((key == LogicalKeyboardKey.slash && !typing) ||
        (key == LogicalKeyboardKey.keyK && chord)) {
      setState(() => _searching = true);
      // After this frame: on a phone the box is only now being built.
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _searchFocus.requestFocus());
      return true;
    }
    if (key == LogicalKeyboardKey.escape && typing) {
      _search.clear();
      setState(() {
        _query = '';
        _searching = false;
      });
      _searchFocus.unfocus();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _pageFocus,
      autofocus: true,
      child: ListenableBuilder(
        listenable: Listenable.merge([_library, _sync]),
        builder: (context, _) => LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= webWideLayout;
          return Stack(
            children: [
              Positioned.fill(
                  child: wide ? _desktop(context) : _phone(context)),
              Positioned.fill(child: _DropHint(listenable: Browser.dragging)),
            ],
          );
        }),
      ),
    );
  }

  // ----------------------------------------------------------------------
  // A desktop window
  // ----------------------------------------------------------------------

  Widget _desktop(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final all = _library.books;
    return Scaffold(
      body: Row(
        children: [
          Container(
            width: 252,
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF0B0B0B) : const Color(0xFFFAFAFA),
              border: Border(
                  right: BorderSide(
                      color: theme.colorScheme.outlineVariant.withAlpha(90))),
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(22, 22, 22, 18),
                    child: _Brand(),
                  ),
                  for (final f in WebFilter.values)
                    _SideItem(
                      key: ValueKey('webFilter:${f.name}'),
                      icon: _filterIcon(f),
                      label: _filterLabel(l10n, f),
                      count: all == null
                          ? null
                          : arrangeLibrary(all, filter: f).length,
                      selected: _filter == f,
                      onTap: () => setState(() => _filter = f),
                    ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                    child: _Account(sync: _sync),
                  ),
                  _SideItem(
                    key: const ValueKey('webSettings'),
                    icon: Icons.settings_outlined,
                    label: l10n.settingsTitle,
                    onTap: _settings,
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(36, 22, 36, 6),
                  child: Row(
                    children: [
                      Text(_filterLabel(l10n, _filter),
                          style: const TextStyle(
                              fontSize: 26, fontWeight: FontWeight.w800)),
                      const SizedBox(width: 12),
                      if (all != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(l10n.webBookCount(_shown(all).length),
                              style: TextStyle(
                                  fontSize: 13,
                                  color: theme.colorScheme.onSurface
                                      .withAlpha(130))),
                        ),
                      const Spacer(),
                      SizedBox(width: 300, child: _searchBox(l10n)),
                      const SizedBox(width: 6),
                      _sortButton(l10n),
                      const SizedBox(width: 10),
                      _addButton(l10n),
                    ],
                  ),
                ),
                Expanded(child: _books(context, wide: true)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------------
  // A phone
  // ----------------------------------------------------------------------

  Widget _phone(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: _searching
            ? _searchBox(l10n, autofocus: true)
            : const _Brand(compact: true),
        actions: [
          if (!_searching)
            IconButton(
              key: const ValueKey('webSearchOpen'),
              tooltip: l10n.webSearchHint,
              icon: const Icon(Icons.search),
              onPressed: () => setState(() => _searching = true),
            ),
          _sortButton(l10n),
          if (_sync.signedIn)
            IconButton(
              key: const ValueKey('webSync'),
              tooltip: l10n.syncNow,
              onPressed: _sync.running ? null : _sync.syncByHand,
              icon: _sync.running
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync),
            ),
          IconButton(
            key: const ValueKey('webSettings'),
            tooltip: l10n.settingsTitle,
            icon: const Icon(Icons.settings_outlined),
            onPressed: _settings,
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('webAddBooks'),
        backgroundColor: scheme.secondary,
        foregroundColor: Colors.white,
        onPressed: _adding ? null : _pick,
        icon: _adding
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.add),
        label: Text(l10n.webAddBooks,
            style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final f in WebFilter.values)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: _FilterPill(
                      key: ValueKey('webFilter:${f.name}'),
                      label: _filterLabel(l10n, f),
                      selected: _filter == f,
                      onTap: () => setState(() => _filter = f),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: _books(context, wide: false)),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------------
  // Shared pieces
  // ----------------------------------------------------------------------

  List<WebBook> _shown(List<WebBook> all) =>
      arrangeLibrary(all, filter: _filter, query: _query, sort: _sort);

  static IconData _filterIcon(WebFilter f) => switch (f) {
        WebFilter.all => Icons.auto_stories_outlined,
        WebFilter.reading => Icons.bookmark_border,
        WebFilter.downloaded => Icons.download_done_rounded,
        WebFilter.finished => Icons.check_circle_outline,
      };

  static String _filterLabel(AppLocalizations l10n, WebFilter f) => switch (f) {
        WebFilter.all => l10n.webFilterAll,
        WebFilter.reading => l10n.webFilterReading,
        WebFilter.downloaded => l10n.webFilterDownloaded,
        WebFilter.finished => l10n.webFilterFinished,
      };

  Widget _searchBox(AppLocalizations l10n, {bool autofocus = false}) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 40,
      child: TextField(
        key: const ValueKey('webSearch'),
        controller: _search,
        focusNode: _searchFocus,
        autofocus: autofocus,
        textInputAction: TextInputAction.search,
        onChanged: (text) => setState(() => _query = text),
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          isDense: true,
          hintText: l10n.webSearchHint,
          hintStyle:
              TextStyle(fontSize: 14, color: scheme.onSurface.withAlpha(110)),
          prefixIcon: Icon(Icons.search,
              size: 19, color: scheme.onSurface.withAlpha(140)),
          suffixIcon: _query.isEmpty && !_searching
              ? null
              : IconButton(
                  tooltip: l10n.webClose,
                  icon: const Icon(Icons.close, size: 17),
                  onPressed: () {
                    _search.clear();
                    setState(() {
                      _query = '';
                      _searching = false;
                    });
                  },
                ),
          filled: true,
          fillColor: scheme.onSurface.withAlpha(14),
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide(color: scheme.secondary, width: 1.4)),
        ),
      ),
    );
  }

  Widget _sortButton(AppLocalizations l10n) => PopupMenuButton<WebSort>(
        key: const ValueKey('webSort'),
        tooltip: l10n.webSort,
        icon: const Icon(Icons.sort),
        initialValue: _sort,
        onSelected: (sort) => setState(() => _sort = sort),
        itemBuilder: (_) => [
          for (final s in WebSort.values)
            PopupMenuItem(
              value: s,
              child: Text(switch (s) {
                WebSort.recent => l10n.webSortRecent,
                WebSort.title => l10n.webSortTitle,
                WebSort.author => l10n.webSortAuthor,
                WebSort.added => l10n.webSortAdded,
              }),
            ),
        ],
      );

  Widget _addButton(AppLocalizations l10n) => SizedBox(
        height: 40,
        child: ElevatedButton.icon(
          key: const ValueKey('webAddBooks'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          onPressed: _adding ? null : _pick,
          icon: _adding
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.add, size: 18),
          label: Text(l10n.webAddBooks,
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      );

  Widget _books(BuildContext context, {required bool wide}) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final all = _library.books;
    final side = wide ? 36.0 : 16.0;
    if (all == null) return _Skeleton(side: side, wide: wide);
    if (all.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_stories_outlined,
                  size: 44, color: scheme.onSurface.withAlpha(90)),
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Text(l10n.webLibraryEmpty,
                    key: const ValueKey('webLibraryEmpty'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        height: 1.5, color: scheme.onSurface.withAlpha(170))),
              ),
            ],
          ),
        ),
      );
    }
    final shown = _shown(all);
    final resume = _filter == WebFilter.all && _query.trim().isEmpty
        ? continueReading(all)
        : null;
    return CustomScrollView(
      key: const ValueKey('webLibraryScroll'),
      slivers: [
        if (resume != null)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(side, wide ? 14 : 6, side, 4),
            sliver: SliverToBoxAdapter(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: _ContinueCard(
                      book: resume,
                      onRead: () => _read(resume),
                      onDetails: () => _details(resume)),
                ),
              ),
            ),
          ),
        if (shown.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(l10n.webNoMatches,
                  style: TextStyle(color: scheme.onSurface.withAlpha(150))),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(side, 18, side, wide ? 48 : 104),
            sliver: SliverLayoutBuilder(builder: (context, constraints) {
              final gap = wide ? 26.0 : 14.0;
              final width = constraints.crossAxisExtent;
              final columns = ((width + gap) / ((wide ? 148 : 108) + gap))
                  .floor()
                  .clamp(2, 12);
              final tile = (width - gap * (columns - 1)) / columns;
              return SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: gap,
                  mainAxisSpacing: wide ? 28 : 18,
                  // The cover, then two lines of title and one of author.
                  mainAxisExtent: tile / 0.7 + 68,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _BookTile(
                    key: ValueKey('webBook:${shown[i].key}'),
                    book: shown[i],
                    onOpen: () => _details(shown[i]),
                    onMenu: (at) => _menu(shown[i], at),
                  ),
                  childCount: shown.length,
                ),
              );
            }),
          ),
      ],
    );
  }
}

/// A filter on a phone (plain text in a pill: a Material chip measured
/// its label before the page's Korean font had come, and cut it).
class _FilterPill extends StatelessWidget {
  const _FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.secondary.withAlpha(46)
          : scheme.onSurface.withAlpha(14),
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Center(
            child: Text(label,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: scheme.onSurface.withAlpha(selected ? 255 : 190))),
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 26 : 30,
          height: compact ? 26 : 30,
          decoration: BoxDecoration(
              color: scheme.secondary, borderRadius: BorderRadius.circular(9)),
          child: Icon(Icons.auto_stories,
              size: compact ? 15 : 17, color: Colors.white),
        ),
        const SizedBox(width: 10),
        Text('LightLib',
            style: TextStyle(
                fontSize: compact ? 19 : 20,
                letterSpacing: -0.2,
                fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _SideItem extends StatelessWidget {
  const _SideItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.count,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.onSurface : scheme.onSurface.withAlpha(175);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: selected ? scheme.onSurface.withAlpha(20) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(icon, size: 19, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14,
                          color: color,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w600)),
                ),
                if (count != null)
                  Text('$count',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: scheme.onSurface.withAlpha(120),
                          fontFeatures: const [FontFeature.tabularFigures()])),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The side bar's account: who is signed in, what sync is doing.
class _Account extends StatelessWidget {
  const _Account({required this.sync});
  final SyncService sync;

  String _time(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final muted =
        TextStyle(fontSize: 12, color: scheme.onSurface.withAlpha(140));
    if (!sync.ready) return const SizedBox(height: 8);
    final user = sync.user;
    final Widget body;
    if (user == null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.webSignInHint, style: muted.copyWith(height: 1.4)),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            key: const ValueKey('webSignIn'),
            style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
            onPressed: sync.signIn,
            icon: const Icon(Icons.login, size: 17),
            label: Text(l10n.syncSignIn,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      );
    } else {
      final progress = sync.progress;
      final last = sync.lastRun;
      final failed = sync.lastError;
      body = Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.email ?? user.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(
                  progress != null
                      ? syncProgressText(l10n, progress)
                      : failed != null
                          ? l10n.syncFailed(failed)
                          : last != null
                              ? l10n.webSyncedAt(_time(last))
                              : l10n.syncTitle,
                  key: const ValueKey('webSyncStatus'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: failed != null && progress == null
                      ? muted.copyWith(color: scheme.error)
                      : muted,
                ),
                if (progress != null) ...[
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      key: const ValueKey('webSyncProgress'),
                      minHeight: 3,
                      color: scheme.secondary,
                      backgroundColor: scheme.onSurface.withAlpha(24),
                      value: progress.total > 0
                          ? progress.done / progress.total
                          : null,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('webSync'),
            tooltip: l10n.syncNow,
            visualDensity: VisualDensity.compact,
            onPressed: sync.running ? null : sync.syncByHand,
            icon: sync.running
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync, size: 19),
          ),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      decoration: BoxDecoration(
        color: scheme.onSurface.withAlpha(12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: body,
    );
  }
}

/// The book read last, to go on with in one click.
class _ContinueCard extends StatefulWidget {
  const _ContinueCard(
      {required this.book, required this.onRead, required this.onDetails});
  final WebBook book;
  final VoidCallback onRead;
  final VoidCallback onDetails;

  @override
  State<_ContinueCard> createState() => _ContinueCardState();
}

class _ContinueCardState extends State<_ContinueCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final book = widget.book;
    final fraction = book.fraction;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        decoration: BoxDecoration(
          color: scheme.onSurface.withAlpha(_hover ? 20 : 12),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: const ValueKey('webContinue'),
            borderRadius: BorderRadius.circular(16),
            onTap: widget.onRead,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  SizedBox(
                    width: 62,
                    child: AspectRatio(
                        aspectRatio: 0.7,
                        child: WebCover(book: book, radius: 7)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(l10n.webContinue,
                            style: TextStyle(
                                fontSize: 11.5,
                                letterSpacing: 0.3,
                                fontWeight: FontWeight.w800,
                                color: scheme.secondary)),
                        const SizedBox(height: 4),
                        Text(book.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 9),
                        Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: (fraction ?? 0).clamp(0, 1),
                                  minHeight: 4,
                                  color: scheme.secondary,
                                  backgroundColor:
                                      scheme.onSurface.withAlpha(24),
                                ),
                              ),
                            ),
                            if (fraction != null && fraction > 0) ...[
                              const SizedBox(width: 10),
                              Text('${(fraction * 100).round()}%',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: scheme.onSurface.withAlpha(160))),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: l10n.webMore,
                    onPressed: widget.onDetails,
                    icon: const Icon(Icons.info_outline, size: 20),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BookTile extends StatefulWidget {
  const _BookTile({
    super.key,
    required this.book,
    required this.onOpen,
    required this.onMenu,
  });

  final WebBook book;
  final VoidCallback onOpen;
  final void Function(Offset at) onMenu;

  @override
  State<_BookTile> createState() => _BookTileState();
}

class _BookTileState extends State<_BookTile> {
  bool _hover = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final book = widget.book;
    final fraction = book.fraction ?? 0;
    final lifted = _hover || _focused;
    return FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      onShowHoverHighlight: (on) => setState(() => _hover = on),
      onShowFocusHighlight: (on) => setState(() => _focused = on),
      actions: {
        ActivateIntent:
            CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onOpen()),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onOpen,
        onSecondaryTapUp: (d) => widget.onMenu(d.globalPosition),
        onLongPressStart: (d) => widget.onMenu(d.globalPosition),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              transform: Matrix4.translationValues(0, lifted ? -4 : 0, 0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: _focused
                    ? Border.all(color: scheme.secondary, width: 2)
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(lifted ? 60 : 26),
                    blurRadius: lifted ? 22 : 8,
                    offset: Offset(0, lifted ? 12 : 3),
                  ),
                ],
              ),
              child: AspectRatio(
                aspectRatio: 0.7,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    WebCover(book: book),
                    if (!book.downloaded)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          key: const ValueKey('webBookCloud'),
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                              color: Colors.black.withAlpha(120),
                              shape: BoxShape.circle),
                          child: const Icon(Icons.cloud_outlined,
                              size: 13, color: Colors.white),
                        ),
                      ),
                    if (book.finished)
                      Positioned(
                        left: 6,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                              color: scheme.secondary, shape: BoxShape.circle),
                          child: const Icon(Icons.check,
                              size: 12, color: Colors.white),
                        ),
                      )
                    else if (fraction > 0)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(10)),
                          child: LinearProgressIndicator(
                            value: fraction.clamp(0, 1),
                            minHeight: 4,
                            color: scheme.secondary,
                            backgroundColor: Colors.black.withAlpha(90),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(book.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13.5, height: 1.3, fontWeight: FontWeight.w700)),
            if (book.author.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(book.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurface.withAlpha(140))),
              ),
          ],
        ),
      ),
    );
  }
}

/// The library's shape while the first read is under way.
class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.side, required this.wide});
  final double side;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface.withAlpha(14);
    return GridView.builder(
      key: const ValueKey('webLibrarySkeleton'),
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(side, 18, side, 0),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: wide ? 198 : 132,
        crossAxisSpacing: wide ? 26 : 14,
        mainAxisSpacing: wide ? 28 : 18,
        childAspectRatio: 0.53,
      ),
      itemCount: wide ? 14 : 9,
      itemBuilder: (_, __) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 10),
          Container(height: 11, width: 110, color: color),
          const SizedBox(height: 7),
          Container(height: 9, width: 64, color: color),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

/// Files held over the window: where they will land.
class _DropHint extends StatelessWidget {
  const _DropHint({required this.listenable});
  final ValueListenable<bool> listenable;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<bool>(
      valueListenable: listenable,
      builder: (context, dragging, _) => IgnorePointer(
        child: AnimatedOpacity(
          opacity: dragging ? 1 : 0,
          duration: const Duration(milliseconds: 120),
          // A Material of its own: this sits above the page's.
          child: Material(
            color: Theme.of(context).scaffoldBackgroundColor.withAlpha(225),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: scheme.secondary, width: 2),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.file_download_outlined,
                          size: 42, color: scheme.secondary),
                      const SizedBox(height: 12),
                      Text(AppLocalizations.of(context).webDropHere,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
