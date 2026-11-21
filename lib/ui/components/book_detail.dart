// A library book's page: its cover, how far it was read, the button that
// opens it where it was left, and what else can be done with it. Shown
// as a page of its own on a phone and as the pane beside the shelf on an
// unfolded or wide screen - the same parts in the same order.

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/database.dart';
import 'package:openlib/services/hidden_covers.dart';
import 'package:openlib/services/library_organization.dart';
import 'package:openlib/services/share_book.dart';
import 'package:openlib/state/state.dart';
import 'package:openlib/ui/book_navigation.dart';
import 'package:openlib/ui/components/book_info_widget.dart' show openInSiteUrl;
import 'package:openlib/ui/components/book_tag_editor.dart';
import 'package:openlib/ui/components/delete_dialog_widget.dart';
import 'package:openlib/ui/components/glossary_sheet.dart';
import 'package:openlib/ui/components/library_tiles.dart';
import 'package:openlib/ui/components/motion.dart';
import 'package:openlib/ui/components/priority_translation_card.dart';
import 'package:openlib/ui/components/snack_bar_widget.dart';

/// When each book was marked finished, by file name; read again whenever
/// the library is.
final completionDatesProvider =
    FutureProvider<Map<String, DateTime>>((ref) async {
  await ref.watch(libraryBooksProvider.future);
  return MyLibraryDb.instance
      .getCompletionDates()
      .catchError((_) => <String, DateTime>{});
});

/// "62% read", "Finished", "Not started yet".
String readingLabel(AppLocalizations l10n, LibraryBook book) {
  switch (book.status) {
    case ReadingStatus.completed:
      return l10n.statusCompleted;
    case ReadingStatus.unread:
      return l10n.webNotStarted;
    case ReadingStatus.inProgress:
      final percent = book.percent;
      return percent == null
          ? l10n.statusInProgress
          : l10n.webPercentRead(percent);
  }
}

/// "Read today", "Read 3 days ago", a date further back.
String? lastReadLabel(AppLocalizations l10n, DateTime? at, String localeTag,
    {DateTime? now}) {
  if (at == null) return null;
  final today = now ?? DateTime.now();
  final days = DateTime(today.year, today.month, today.day)
      .difference(DateTime(at.year, at.month, at.day))
      .inDays;
  if (days <= 0) return l10n.bookReadToday;
  if (days == 1) return l10n.bookReadYesterday;
  if (days < 30) return l10n.bookReadDaysAgo(days);
  return DateFormat.yMMMd(localeTag).format(at);
}

String _size(int bytes) {
  if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
  return '${(bytes / 1024).ceil()} KB';
}

class BookDetail extends ConsumerStatefulWidget {
  const BookDetail({
    super.key,
    required this.bookId,
    this.heroTag,
    this.leading,
    this.onGone,
    this.pane = false,
  });

  final String bookId;

  /// The cover's tag where the book was tapped (it flies from there, and
  /// on to the reader's opening picture).
  final Object? heroTag;

  /// At the top's start: the way back.
  final Widget? leading;

  /// The book is no longer in the library (it was deleted here).
  final VoidCallback? onGone;

  /// Beside the shelf, not a page of its own: a smaller cover.
  final bool pane;

  @override
  ConsumerState<BookDetail> createState() => _BookDetailState();
}

class _BookDetailState extends ConsumerState<BookDetail> {
  bool _more = false;

  Object get _heroTag => widget.heroTag ?? 'bookDetailCover:${widget.bookId}';

  Future<void> _setFinished(LibraryBook book, bool finished) async {
    final db = MyLibraryDb.instance;
    final file = book.book.getFileName();
    if (!finished) {
      // Read to the last page, it would count as finished again at once:
      // how far it was read goes too.
      final f = double.tryParse(await db.getSyncState('frac:$file') ?? '');
      if ((f ?? 0) >= BookReading.finishedFraction) {
        await db.setSyncState('frac:$file', null);
      }
    }
    await db.setCompleted(file, finished);
  }

  Future<void> _share(LibraryBook book) async {
    final l10n = AppLocalizations.of(context);
    final b = book.book;
    final outcome = await shareBook(b.title, b.link, b.thumbnail ?? '',
        fileName: b.fileName, format: b.format);
    if (mounted && outcome == ShareOutcome.pathCopied) {
      showSnackBar(context: context, message: l10n.copiedBookPath);
    }
  }

  void _delete(LibraryBook book) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ShowDeleteDialog(
        id: book.id,
        format: book.book.format ?? '',
        fileName: book.book.fileName,
        onDelete: () => widget.onGone?.call(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Theme(
        data: modernSurfaceTheme(Theme.of(context)),
        child: Builder(builder: _build),
      );

  Widget _build(BuildContext context) {
    final books = ref.watch(libraryBooksProvider);
    final book = books.valueOrNull
        ?.where((b) => b.id == widget.bookId)
        .cast<LibraryBook?>()
        .firstWhere((_) => true, orElse: () => null);
    final scheme = Theme.of(context).colorScheme;
    if (book == null) {
      return Stack(
        children: [
          Center(
            child: books.isLoading
                ? SizedBox(
                    width: 25,
                    height: 25,
                    child: CircularProgressIndicator(color: scheme.primary))
                : const SizedBox.shrink(),
          ),
          if (widget.leading != null)
            Positioned(
                top: MediaQuery.paddingOf(context).top + 4,
                left: 4,
                child: widget.leading!),
        ],
      );
    }
    final l10n = AppLocalizations.of(context);
    final localeTag = Localizations.localeOf(context).toLanguageTag();
    final isEpub = (book.book.format ?? '').toLowerCase() == 'epub';
    final finishedAt = ref
        .watch(completionDatesProvider)
        .valueOrNull?[book.book.getFileName()];
    final accent = Theme.of(context).colorScheme.primary;
    final surface = scheme.surface;
    final coverWidth = widget.pane ? 132.0 : 156.0;
    // (Under the status bar, where the page reaches that far.)
    final top = MediaQuery.paddingOf(context).top;
    final headerHeight = coverWidth * 1.5 + (widget.pane ? 56 : 76) + top;

    final String action;
    switch (book.status) {
      case ReadingStatus.completed:
        action = l10n.bookReadAgain;
      case ReadingStatus.unread:
        action = l10n.webRead;
      case ReadingStatus.inProgress:
        final percent = book.percent;
        action = percent == null
            ? l10n.libraryContinueReading
            : l10n.bookContinueFrom(percent);
    }
    final finished = book.status == ReadingStatus.completed;
    final String? when = finished
        ? (finishedAt ?? book.readAt) == null
            ? null
            : l10n.bookFinishedOn(DateFormat.yMMMd(localeTag)
                .format((finishedAt ?? book.readAt)!))
        : book.status == ReadingStatus.inProgress
            ? lastReadLabel(l10n, book.readAt, localeTag)
            : null;
    final description = (book.book.description ?? '').trim();
    final hasDescription = description.length >= 3 && description != 'null';

    return CustomScrollView(
      key: ValueKey('bookDetail-${book.id}'),
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: headerHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // The cover's colours behind it, fading into the page.
                ClipRect(child: BookCoverBackdrop(book: book, opacity: 0.55)),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        surface.withValues(alpha: 0.25),
                        surface.withValues(alpha: 0.7),
                        surface,
                      ],
                      stops: const [0, 0.62, 1],
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(top: top),
                  child: Align(
                    alignment: const Alignment(0, 0.35),
                    child: SizedBox(
                      width: coverWidth,
                      child: Hero(
                        tag: _heroTag,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: const [
                              BoxShadow(
                                  color: Color(0x73000000),
                                  blurRadius: 28,
                                  offset: Offset(0, 14)),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: AspectRatio(
                                aspectRatio: 2 / 3,
                                child: BookCover(book: book)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: top + 4,
                  left: 4,
                  right: 4,
                  child: Row(
                    children: [
                      if (widget.leading != null) widget.leading!,
                      const Spacer(),
                      _menu(context, book, l10n),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Appear(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      book.title,
                      key: const ValueKey('bookDetailTitle'),
                      textAlign: TextAlign.center,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: widget.pane ? 18 : 20,
                          height: 1.3,
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurface),
                    ),
                    if (book.author.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        book.author,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13.5, color: scheme.onSurfaceVariant),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _Fact(
                            icon: Icons.menu_book_outlined,
                            label: [
                              (book.book.format ?? '').toUpperCase(),
                              if (book.fileSizeBytes != null)
                                _size(book.fileSizeBytes!),
                            ].where((s) => s.isNotEmpty).join(' · ')),
                        if (book.genre != null)
                          _Fact(
                              icon: genreIcon(book.genre!),
                              label: genreLabel(l10n, book.genre!)),
                        if ((book.series ?? '').isNotEmpty)
                          _Fact(
                              icon: Icons.collections_bookmark_outlined,
                              label: book.series!),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              // How far it was read.
              Appear(
                delay: const Duration(milliseconds: 60),
                child: Container(
                  key: const ValueKey('bookDetailReading'),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(
                              finished
                                  ? Icons.task_alt_rounded
                                  : Icons.auto_stories_outlined,
                              size: 18,
                              color: accent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              readingLabel(l10n, book),
                              key: const ValueKey('bookDetailReadingLabel'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: scheme.onSurface),
                            ),
                          ),
                          if (when != null)
                            Text(when,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurfaceVariant)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ProgressBar(
                          value: book.progress, height: 6, color: accent),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Appear(
                delay: const Duration(milliseconds: 110),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ReadButton(
                      key: const ValueKey('bookDetailRead'),
                      label: action,
                      icon: finished
                          ? Icons.replay_rounded
                          : Icons.play_arrow_rounded,
                      onTap: () =>
                          openBookReader(context, ref, book, heroTag: _heroTag),
                    ),
                    const SizedBox(height: 10),
                    // Side by side where both names fit, one under the
                    // other in a narrow pane.
                    LayoutBuilder(builder: (context, constraints) {
                      final finish = _SoftButton(
                        key: const ValueKey('bookDetailFinished'),
                        icon: finished
                            ? Icons.remove_done_rounded
                            : Icons.done_all_rounded,
                        label: finished
                            ? l10n.bookMarkUnfinished
                            : l10n.bookMarkFinished,
                        onTap: () => _setFinished(book, !finished),
                      );
                      if (!isEpub) return finish;
                      final glossary = _SoftButton(
                        // The glossary without opening the book: a word
                        // set right there has its paragraphs translated
                        // again, in this book or in the whole series.
                        key: const ValueKey('bookGlossary'),
                        icon: Icons.menu_book_outlined,
                        label: l10n.glossaryTitle,
                        onTap: () => showGlossarySheet(context,
                            bookFile: book.book.getFileName()),
                      );
                      if (constraints.maxWidth < 280) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            finish,
                            const SizedBox(height: 10),
                            glossary,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: finish),
                          const SizedBox(width: 10),
                          Expanded(child: glossary),
                        ],
                      );
                    }),
                  ],
                ),
              ),
              if (isEpub)
                Appear(
                  delay: const Duration(milliseconds: 160),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: PriorityTranslationCard(
                        fileName: book.book.getFileName(), title: book.title),
                  ),
                ),
              const SizedBox(height: 18),
              Appear(
                delay: const Duration(milliseconds: 200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l10n.bookAbout,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface)),
                    const SizedBox(height: 8),
                    if (!hasDescription)
                      Text(l10n.bookNoDescription,
                          style: TextStyle(
                              fontSize: 13, color: scheme.onSurfaceVariant))
                    else
                      AnimatedSize(
                        duration: AppMotion.reduced(context)
                            ? Duration.zero
                            : AppMotion.standard,
                        curve: AppMotion.enter,
                        alignment: Alignment.topCenter,
                        child: SelectionArea(
                          child: Text(
                            description,
                            maxLines: _more ? null : 5,
                            overflow: _more
                                ? TextOverflow.visible
                                : TextOverflow.fade,
                            style: TextStyle(
                                fontSize: 13.5,
                                height: 1.55,
                                color:
                                    scheme.onSurface.withValues(alpha: 0.82)),
                          ),
                        ),
                      ),
                    if (hasDescription && description.length > 160)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton(
                          style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              foregroundColor: accent),
                          onPressed: () => setState(() => _more = !_more),
                          child: Text(_more ? l10n.close : l10n.bookMore),
                        ),
                      ),
                    for (final line in [
                      book.book.publisher,
                      book.book.info,
                    ])
                      if ((line ?? '').trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(line!.trim(),
                              style: TextStyle(
                                  fontSize: 12,
                                  height: 1.4,
                                  color: scheme.onSurfaceVariant)),
                        ),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _menu(BuildContext context, LibraryBook book, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    // Where the book came from (asked for only when the menu's item is
    // tapped: which mirror is up is a question for the network).
    final hasSite = book.book.link.isNotEmpty ||
        RegExp(r'^[0-9a-f]{32}$', caseSensitive: false).hasMatch(book.id);
    final hidden = HiddenCovers.instance.isHidden(book.id);
    PopupMenuItem<VoidCallback> item(
            IconData icon, String label, VoidCallback run,
            {Key? key, Color? color}) =>
        PopupMenuItem<VoidCallback>(
          key: key,
          value: run,
          child: Row(
            children: [
              Icon(icon, size: 20, color: color ?? scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Flexible(
                  child: Text(label,
                      style: TextStyle(color: color ?? scheme.onSurface))),
            ],
          ),
        );
    return PopupMenuButton<VoidCallback>(
      key: const ValueKey('bookDetailMenu'),
      tooltip: l10n.bookMore,
      icon: const Icon(Icons.more_horiz_rounded),
      onSelected: (run) => run(),
      itemBuilder: (_) => [
        item(
            Icons.label_outline,
            l10n.librarySelectionTags,
            () => showBookTagEditor(context,
                bookId: book.id, title: book.title, genre: book.genre)),
        item(hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            hidden ? l10n.coverShow : l10n.coverHide, () async {
          await HiddenCovers.instance.setHidden(book.id, !hidden);
          ref.invalidate(libraryBooksProvider);
        }, key: const ValueKey('hideCoverButton')),
        item(Icons.ios_share_rounded, l10n.bookShare, () => _share(book)),
        if (hasSite)
          item(Icons.open_in_new_rounded, l10n.openInSite, () async {
            final base = await ref
                .read(annaArchiveBaseUrlProvider.future)
                .catchError((_) => null);
            final siteUrl = openInSiteUrl(
                link: book.book.link, md5: book.id, annaArchiveBaseUrl: base);
            if (siteUrl == null) return;
            final uri = Uri.parse(siteUrl);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          }),
        item(Icons.delete_outline_rounded, l10n.delete, () => _delete(book),
            key: const ValueKey('bookDetailDelete'), color: scheme.error),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: scheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

/// The one thing to do here: read. The tabs' capsule, as a button.
class _ReadButton extends StatelessWidget {
  const _ReadButton(
      {super.key, required this.label, required this.icon, this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // (The app's accent, as the tab bar draws it; the page's own scheme
    // is a softer pink.)
    const accent = Color(0xFFFF6B9D);
    return Semantics(
      button: true,
      label: label,
      child: Pressable(
        onTap: onTap,
        scale: 0.97,
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(27),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(accent, Colors.white, 0.06)!,
                Color.lerp(accent, Colors.black, 0.18)!,
              ],
            ),
            boxShadow: [
              BoxShadow(
                  color: accent.withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 6)),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 24),
              const SizedBox(width: 6),
              Flexible(
                child: ExcludeSemantics(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SoftButton extends StatelessWidget {
  const _SoftButton(
      {super.key, required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: label,
      child: Pressable(
        onTap: onTap,
        scale: 0.97,
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(23),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              Flexible(
                child: ExcludeSemantics(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
