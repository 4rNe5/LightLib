// The web build's home: the books kept in this browser (added here or
// synced from the phone), opened in the same reader as the app's.

// Dart imports:
import 'dart:async';
import 'dart:typed_data';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:file_picker/file_picker.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/database.dart';
import 'package:openlib/services/files.dart' show webBookStorageDirectory;
import 'package:openlib/services/local_book_import.dart';
import 'package:openlib/services/storage/app_files.dart';
import 'package:openlib/services/sync/library_sync_local.dart';
import 'package:openlib/services/sync/sync_engine.dart';
import 'package:openlib/services/sync/sync_service.dart';
import 'package:openlib/ui/book_reader_page.dart';
import 'package:openlib/web/web_settings_page.dart';

class WebLibraryPage extends StatefulWidget {
  const WebLibraryPage({super.key});

  @override
  State<WebLibraryPage> createState() => _WebLibraryPageState();
}

class _WebLibraryPageState extends State<WebLibraryPage> {
  final _db = MyLibraryDb.instance;
  final _sync = SyncService.instance;
  List<MyBook>? _books;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _sync.onLocalChanges = _reload;
    _reload();
  }

  @override
  void dispose() {
    if (_sync.onLocalChanges == _reload) _sync.onLocalChanges = null;
    super.dispose();
  }

  Future<void> _reload() async {
    final all = await _db.getAll();
    if (!mounted) return;
    setState(() => _books = [
          for (final b in all)
            if ((b.format ?? '').toLowerCase() == 'epub') b,
        ]);
  }

  Future<void> _add() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['epub'],
    );
    if (picked.isEmpty) return;
    setState(() => _adding = true);
    var added = 0;
    for (final f in picked) {
      final result = await importBookBytes(f.name, await f.readAsBytes());
      if (result.outcome == LocalImportOutcome.imported) added++;
    }
    if (!mounted) return;
    setState(() => _adding = false);
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).webAdded(added))));
    if (added > 0 && _sync.auto) unawaited(_sync.syncNow());
  }

  Future<void> _open(MyBook book) async {
    final fileName = book.getFileName();
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BookReaderPage(
        fileName: fileName,
        filePath: '$webBookStorageDirectory/$fileName',
      ),
    ));
    if (mounted) unawaited(_reload());
  }

  Future<void> _delete(MyBook book) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.webDeleteBook),
        content: Text(l10n.webDeleteConfirm(book.title)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.webCancel)),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.webDelete)),
        ],
      ),
    );
    if (ok != true) return;
    await LibrarySyncLocal().removeBook(LocalBook(
      id: book.id,
      fileName: book.getFileName(),
      title: book.title,
      author: book.author,
      format: 'epub',
    ));
    await _reload();
    if (_sync.auto) unawaited(_sync.syncNow());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final books = _books;
    return Scaffold(
      appBar: AppBar(
        title: const Text('LightLib'),
        actions: [
          ListenableBuilder(
            listenable: _sync,
            builder: (context, _) => !_sync.signedIn
                ? const SizedBox.shrink()
                : IconButton(
                    key: const ValueKey('webSync'),
                    tooltip: l10n.syncNow,
                    onPressed: _sync.running ? null : _sync.syncNow,
                    icon: _sync.running
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.sync),
                  ),
          ),
          IconButton(
            key: const ValueKey('webSettings'),
            tooltip: l10n.settingsTitle,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () async {
              await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const WebSettingsPage()));
              if (mounted) unawaited(_reload());
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('webAddBooks'),
        // The app's theme keeps its accent in secondary (primary is the
        // page colour).
        backgroundColor: Theme.of(context).colorScheme.secondary,
        foregroundColor: Colors.white,
        onPressed: _adding ? null : _add,
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
      body: books == null
          ? const Center(child: CircularProgressIndicator())
          : books.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child:
                        Text(l10n.webLibraryEmpty, textAlign: TextAlign.center),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 170,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.56,
                  ),
                  itemCount: books.length,
                  itemBuilder: (context, i) => _BookTile(
                    book: books[i],
                    onOpen: () => _open(books[i]),
                    onDelete: () => _delete(books[i]),
                  ),
                ),
    );
  }
}

class _BookTile extends StatelessWidget {
  const _BookTile(
      {required this.book, required this.onOpen, required this.onDelete});

  final MyBook book;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return InkWell(
      key: ValueKey('webBook:${book.id}'),
      onTap: onOpen,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: _Cover(book: book),
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: PopupMenuButton<String>(
                    tooltip: l10n.webDeleteBook,
                    icon: const Icon(Icons.more_vert, size: 20),
                    onSelected: (_) => onDelete(),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                          value: 'delete', child: Text(l10n.webDeleteBook)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(book.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          if ((book.author ?? '').isNotEmpty)
            Text(book.author!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.book});
  final MyBook book;

  Future<Uint8List?> _bytes() async {
    final thumb = book.thumbnail;
    if (thumb == null || thumb.isEmpty || thumb.startsWith('http')) {
      return null;
    }
    return AppFiles.instance.readBytes(thumb);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      child: Text(book.title,
          textAlign: TextAlign.center,
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: scheme.onSurfaceVariant)),
    );
    final thumb = book.thumbnail ?? '';
    if (thumb.startsWith('http')) {
      return Image.network(thumb,
          fit: BoxFit.cover,
          webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
          errorBuilder: (_, __, ___) => placeholder);
    }
    return FutureBuilder<Uint8List?>(
      future: _bytes(),
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null) return placeholder;
        return Image.memory(bytes,
            fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder);
      },
    );
  }
}
