// What is on screen while a book opens: its cover (flown here from where
// it was tapped), its name, and where the reading picks up - over the
// cover's own colours, out of focus. The reader shows it until the first
// page is up.

// Flutter imports:
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

// Project imports:
import 'package:openlib/services/library_organization.dart';
import 'package:openlib/ui/components/library_tiles.dart';
import 'package:openlib/ui/components/motion.dart';

class BookOpeningView extends StatefulWidget {
  const BookOpeningView({
    super.key,
    required this.book,
    required this.label,
    this.heroTag,
    this.progress,
    this.onClose,
  });

  final LibraryBook book;

  /// What is happening ("Opening at 62%…").
  final String label;

  /// The cover's tag where the book was tapped: it flies from there.
  final Object? heroTag;

  /// How far the book was read, 0..1, shown as a thin bar under the name.
  final double? progress;
  final VoidCallback? onClose;

  @override
  State<BookOpeningView> createState() => _BookOpeningViewState();
}

class _BookOpeningViewState extends State<BookOpeningView>
    with SingleTickerProviderStateMixin {
  // The cover drifts a little while it waits: the screen is alive, the
  // book is coming. Still on the web (a frame there is dear) and with
  // animations off.
  late final AnimationController _float = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2600));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!kIsWeb && !AppMotion.reduced(context)) _float.repeat(reverse: true);
  }

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final base = dark ? const Color(0xFF0E0E10) : const Color(0xFFF6F3F4);
    final text = dark ? Colors.white : const Color(0xFF17181A);
    final muted = text.withValues(alpha: 0.62);
    final book = widget.book;
    Widget cover = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.55 : 0.28),
              blurRadius: 36,
              offset: const Offset(0, 18)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(aspectRatio: 2 / 3, child: BookCover(book: book)),
      ),
    );
    if (widget.heroTag != null) {
      cover = Hero(tag: widget.heroTag!, child: cover);
    }
    return Material(
      key: const ValueKey('bookOpening'),
      color: base,
      child: Stack(
        fit: StackFit.expand,
        children: [
          BookCoverBackdrop(book: book, opacity: dark ? 0.5 : 0.42),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  base.withValues(alpha: 0.35),
                  base.withValues(alpha: 0.82),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 36),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedBuilder(
                        animation: _float,
                        builder: (context, child) => Transform.translate(
                          offset: Offset(
                              0,
                              -4 *
                                  Curves.easeInOut.transform(_float.value)),
                          child: child,
                        ),
                        child: SizedBox(width: 184, child: cover),
                      ),
                      const SizedBox(height: 28),
                      Appear(
                        delay: const Duration(milliseconds: 120),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              book.title,
                              textAlign: TextAlign.center,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 20,
                                  height: 1.3,
                                  fontWeight: FontWeight.w800,
                                  color: text),
                            ),
                            if (book.author.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                book.author,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 14, color: muted),
                              ),
                            ],
                            const SizedBox(height: 24),
                            SizedBox(
                              width: 200,
                              child: ProgressBar(
                                value: widget.progress ?? 0,
                                height: 4,
                                color: theme.colorScheme.secondary,
                                trackColor: text.withValues(alpha: 0.14),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              widget.label,
                              key: const ValueKey('bookOpeningLabel'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (widget.onClose != null)
            Positioned(
              top: 4,
              left: 4,
              child: SafeArea(
                child: IconButton(
                  key: const ValueKey('bookOpeningClose'),
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: widget.onClose,
                  icon: Icon(Icons.arrow_back, color: text),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
