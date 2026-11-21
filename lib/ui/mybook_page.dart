// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Project imports:
import 'package:openlib/ui/adaptive.dart';
import 'package:openlib/ui/book_navigation.dart';
import 'package:openlib/ui/components/book_detail.dart';

/// A library book's page ([BookDetail]) on a screen of its own: where a
/// phone goes from the shelf, and from where the book is opened.
class BookPage extends ConsumerStatefulWidget {
  const BookPage({super.key, required this.id, this.heroTag});

  final String id;

  /// The cover's tag on the shelf (it flies from there).
  final Object? heroTag;

  @override
  ConsumerState<BookPage> createState() => _BookPageState();
}

class _BookPageState extends ConsumerState<BookPage> {
  bool _stepping = false;

  /// The window grew wide enough for the shelf and a book side by side
  /// (the phone was unfolded): this page steps into the pane beside the
  /// shelf - the same book, where it now belongs - and leaves the stack
  /// without a move, also from under a reader.
  void _stepIntoPane() {
    if (_stepping) return;
    _stepping = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _stepping = false;
      if (!mounted || !useTwoPanes(context)) return;
      final route = ModalRoute.of(context);
      if (route == null || !route.isActive) return;
      ref.read(libraryDetailProvider.notifier).state = widget.id;
      Navigator.of(context).removeRoute(route);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (useTwoPanes(context)) _stepIntoPane();
    return Scaffold(
      // (The cover's colours run up under the status bar; the page's
      // own parts keep below it.)
      body: SafeArea(
        top: false,
        bottom: false,
        child: BookDetail(
          bookId: widget.id,
          heroTag: widget.heroTag,
          leading: IconButton(
            key: const ValueKey('bookPageBack'),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          onGone: () => Navigator.of(context).maybePop(),
        ),
      ),
    );
  }
}
