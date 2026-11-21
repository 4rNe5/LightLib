// How a library book is opened. One order of screens, whatever led to
// the book (the shelf, a home-screen widget, another book's page):
//
//   the tabs  →  the book's page  →  the reader
//
// and "back" walks it the other way. A book opened from outside while
// another is on screen takes that one's place - it is never laid on top
// of it, so "back" from a reader never lands in another book's reader.

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/library_organization.dart';
import 'package:openlib/ui/adaptive.dart';
import 'package:openlib/ui/components/book_opening.dart';
import 'package:openlib/ui/components/file_buttons_widget.dart'
    show BookOpenTarget, bookOpenTargetForFormat, openCbrAndCbz;
import 'package:openlib/ui/epub_viewer.dart' show launchEpubViewer;
import 'package:openlib/ui/mybook_page.dart' show BookPage;
import 'package:openlib/ui/pdf_viewer.dart' show launchPdfViewer;

/// The book the library's pane shows on a wide screen (null: the
/// overview - what is being read, the reading record).
final libraryDetailProvider = StateProvider<String?>((ref) => null);

String bookRouteName(String bookId) => 'book:$bookId';
String readerRouteName(String bookId) => 'reader:$bookId';

/// The route on top of [navigator].
Route<dynamic>? topRouteOf(NavigatorState navigator) {
  Route<dynamic>? top;
  navigator.popUntil((route) {
    top = route;
    return true;
  });
  return top;
}

/// The page of the book [bookId], over whatever is on screen.
Future<void> pushBookPage(NavigatorState navigator, String bookId,
        {Object? heroTag}) =>
    navigator.push(MaterialPageRoute<void>(
      settings: RouteSettings(name: bookRouteName(bookId)),
      builder: (_) => BookPage(id: bookId, heroTag: heroTag),
    ));

/// A book asked for from outside what is on screen (a home-screen
/// widget's tap): everything over the tabs is closed first - another
/// book's page, its reader, a sheet - and the book is shown from the
/// library: in the pane beside the shelf where there is one, as a page
/// otherwise. Nothing changes when that very book is what is on screen.
void showBookFromOutside(
    BuildContext context, WidgetRef ref, String bookId) {
  final navigator = Navigator.of(context);
  final top = topRouteOf(navigator)?.settings.name;
  if (top == readerRouteName(bookId) || top == bookRouteName(bookId)) return;
  navigator.popUntil((route) => route.isFirst);
  if (useTwoPanes(context)) {
    ref.read(libraryDetailProvider.notifier).state = bookId;
  } else {
    pushBookPage(navigator, bookId);
  }
}

/// Opens [book] to read: the reader for an EPUB (its cover on screen
/// until the first page is up), the PDF viewer, or the app the device
/// has for anything else. Completes when the reader is left.
Future<void> openBookReader(
    BuildContext context, WidgetRef ref, LibraryBook book,
    {Object? heroTag}) async {
  final format = book.book.format ?? '';
  final fileName = book.book.getFileName();
  switch (bookOpenTargetForFormat(format)) {
    case BookOpenTarget.pdf:
      await launchPdfViewer(fileName: fileName, context: context, ref: ref);
    case BookOpenTarget.epub:
      final percent = book.percent;
      await launchEpubViewer(
        fileName: fileName,
        context: context,
        ref: ref,
        settings: RouteSettings(name: readerRouteName(book.id)),
        opening: (context) {
          final l10n = AppLocalizations.of(context);
          return BookOpeningView(
            book: book,
            heroTag: heroTag,
            progress: book.progress,
            label: percent == null
                ? l10n.bookOpening
                : l10n.bookOpeningAt(percent),
            onClose: () => Navigator.of(context).maybePop(),
          );
        },
      );
    case BookOpenTarget.external:
      await openCbrAndCbz(fileName: fileName, context: context);
  }
}
