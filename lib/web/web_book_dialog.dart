// A book's card on the web: its cover beside what is known of it (who
// wrote it, how far it was read, what is translated), over the library
// out of focus, with the button that opens it.

// Dart imports:
import 'dart:ui' show ImageFilter;

// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/translation/translation_models.dart'
    show languageForCode;
import 'package:openlib/web/web_cover.dart';
import 'package:openlib/web/web_library.dart';

/// What the reader asked for on a book's card.
enum WebBookAction { read, removeCopy, delete }

Future<WebBookAction?> showWebBookDialog(BuildContext context, WebBook book) =>
    showGeneralDialog<WebBookAction>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withAlpha(70),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, _, __) => _BookDialog(book: book),
      transitionBuilder: (context, animation, _, child) {
        final t =
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return BackdropFilter(
          filter: ImageFilter.blur(
              sigmaX: 14 * animation.value, sigmaY: 14 * animation.value),
          child: FadeTransition(
            opacity: t,
            child: ScaleTransition(
                scale: Tween(begin: 0.96, end: 1.0).animate(t), child: child),
          ),
        );
      },
    );

class _BookDialog extends StatelessWidget {
  const _BookDialog({required this.book});
  final WebBook book;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 680;
    final card = dark ? const Color(0xFF161616) : Colors.white;
    return SafeArea(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(wide ? 32 : 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: wide ? 780 : 460, maxHeight: wide ? 520 : 720),
            child: Material(
              key: const ValueKey('webBookDialog'),
              color: card,
              elevation: 24,
              shadowColor: Colors.black.withAlpha(120),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
                side: BorderSide(
                    color: theme.colorScheme.outlineVariant.withAlpha(90)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Padding(
                    padding: EdgeInsets.all(wide ? 28 : 20),
                    child: wide ? _wide(context) : _narrow(context),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      key: const ValueKey('webBookClose'),
                      tooltip: AppLocalizations.of(context).webClose,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cover(double width) => Container(
        width: width,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withAlpha(60),
                blurRadius: 28,
                offset: const Offset(0, 14)),
          ],
        ),
        child: AspectRatio(
            aspectRatio: 0.7, child: WebCover(book: book, radius: 12)),
      );

  Widget _wide(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(alignment: Alignment.topCenter, child: _cover(264)),
          const SizedBox(width: 30),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ..._heading(context, titleSize: 25),
                const SizedBox(height: 16),
                ..._facts(context),
                const SizedBox(height: 16),
                Expanded(child: _description(context)),
                const SizedBox(height: 16),
                _actions(context),
              ],
            ),
          ),
        ],
      );

  Widget _narrow(BuildContext context) => Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Center(child: _cover(150)),
                  const SizedBox(height: 20),
                  ..._heading(context, titleSize: 20),
                  const SizedBox(height: 14),
                  ..._facts(context),
                  const SizedBox(height: 14),
                  _descriptionText(context),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          _actions(context),
        ],
      );

  List<Widget> _heading(BuildContext context, {required double titleSize}) {
    final muted = Theme.of(context).colorScheme.onSurface.withAlpha(165);
    return [
      Padding(
        // Clear of the close button.
        padding: const EdgeInsets.only(right: 28),
        child: Text(book.title,
            key: const ValueKey('webBookTitle'),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: titleSize,
                height: 1.25,
                fontWeight: FontWeight.w800)),
      ),
      if (book.author.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(book.author,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 15.5, color: muted)),
      ],
      if (book.publisher.isNotEmpty) ...[
        const SizedBox(height: 3),
        Text(book.publisher,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: muted.withAlpha(120))),
      ],
    ];
  }

  List<Widget> _facts(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withAlpha(165);
    final fraction = book.fraction;
    final String reading;
    if (book.finished) {
      reading = l10n.webFilterFinished;
    } else if (fraction != null && fraction > 0) {
      reading = l10n.webPercentRead((fraction * 100).round().clamp(1, 99));
    } else if (book.started) {
      reading = l10n.webFilterReading;
    } else {
      reading = l10n.webNotStarted;
    }
    final size = book.sizeBytes;
    return [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _Chip(
              icon: Icons.menu_book_outlined,
              label: size == null ? 'EPUB' : 'EPUB · ${formatBytes(size)}'),
          _Chip(
            key: const ValueKey('webBookWhere'),
            icon: book.downloaded
                ? Icons.download_done_rounded
                : Icons.cloud_outlined,
            label:
                book.downloaded ? l10n.webFilterDownloaded : l10n.webOnAccount,
          ),
        ],
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: book.finished ? 1 : (fraction ?? 0).clamp(0, 1),
                minHeight: 5,
                color: scheme.secondary,
                backgroundColor: scheme.onSurface.withAlpha(24),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(reading,
              key: const ValueKey('webBookReading'),
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: muted)),
        ],
      ),
      for (final MapEntry(key: lang, value: count) in book.translated.entries)
        if (count > 0)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                Icon(Icons.translate, size: 15, color: muted),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                      l10n.webTranslated(
                          count, languageForCode(lang).nativeName),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: muted)),
                ),
              ],
            ),
          ),
    ];
  }

  Widget _descriptionText(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface;
    final text = _plain(book.description);
    return Text(
      text.isEmpty ? AppLocalizations.of(context).webNoDescription : text,
      style: TextStyle(
          fontSize: 14,
          height: 1.6,
          color: muted.withAlpha(text.isEmpty ? 110 : 200)),
    );
  }

  Widget _description(BuildContext context) => ShaderMask(
        // The text fades at the foot instead of being cut mid-line.
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Colors.white, Colors.transparent],
          stops: [0, 0.86, 1],
        ).createShader(rect),
        blendMode: BlendMode.dstIn,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 18),
          child: _descriptionText(context),
        ),
      );

  Widget _actions(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final resume = book.started && !book.finished;
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              key: const ValueKey('webBookRead'),
              autofocus: true,
              style: ElevatedButton.styleFrom(
                backgroundColor: scheme.secondary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(
                    fontSize: 15.5, fontWeight: FontWeight.w700),
              ),
              onPressed: () => Navigator.of(context).pop(WebBookAction.read),
              icon: Icon(
                  book.downloaded
                      ? Icons.auto_stories_outlined
                      : Icons.cloud_download_outlined,
                  size: 20),
              label: Text(resume ? l10n.webContinue : l10n.webRead),
            ),
          ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<WebBookAction>(
          key: const ValueKey('webBookMore'),
          tooltip: l10n.webMore,
          icon: const Icon(Icons.more_horiz),
          onSelected: (action) => Navigator.of(context).pop(action),
          itemBuilder: (_) => [
            if (book.downloaded && book.onAccount)
              PopupMenuItem(
                  value: WebBookAction.removeCopy,
                  child: Text(l10n.webRemoveCopy)),
            PopupMenuItem(
                value: WebBookAction.delete,
                child: Text(l10n.webDeleteEverywhere,
                    style: TextStyle(color: scheme.error))),
          ],
        ),
      ],
    );
  }
}

/// An EPUB's description is often HTML: the words only.
String _plain(String description) => description
    .replaceAll(RegExp(r'<br\s*/?>|</p>|</div>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();

class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.onSurface.withAlpha(16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.onSurface.withAlpha(180)),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface.withAlpha(200))),
        ],
      ),
    );
  }
}
