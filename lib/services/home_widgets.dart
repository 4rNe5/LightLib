// Android home-screen widgets: the library's bento cards (the book being
// read, the reading record) as widgets. The app writes what they show -
// already worded in the app's language - and Android draws it; a tap
// opens the book or the library.

// Dart imports:
import 'dart:async';
import 'dart:convert';
import 'dart:io';

// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/book_covers.dart';
import 'package:openlib/services/hidden_covers.dart';
import 'package:openlib/services/library_organization.dart';
import 'package:openlib/services/local_book_import.dart'
    show isLocalImagePath, localImageFilePath;
import 'package:openlib/services/reading_recap.dart';
import 'package:openlib/ui/components/book_card_widget.dart'
    show coverHeadersFor;

/// What a widget tap asks the app to show.
@immutable
class WidgetAction {
  const WidgetAction.openBook(String this.bookId) : library = false;
  const WidgetAction.openLibrary()
      : bookId = null,
        library = true;

  final String? bookId;
  final bool library;

  static WidgetAction? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['bookId'];
    if (id is String && id.isNotEmpty) return WidgetAction.openBook(id);
    if (raw['library'] == true) return const WidgetAction.openLibrary();
    return null;
  }
}

/// Everything the widgets show, as the JSON Android reads.
@visibleForTesting
Map<String, Object?> widgetSnapshot({
  required List<LibraryBook> books,
  required ReadingRecap? recap,
  required AppLocalizations l10n,
  required String localeTag,
  required Map<String, String?> covers,
  DateTime? now,
}) {
  final reading =
      books.where((b) => b.status == ReadingStatus.inProgress).toList();
  final continuing = reading.isNotEmpty;
  final featured = continuing ? reading : books;
  Map<String, Object?>? book(LibraryBook? b) => b == null
      ? null
      : {
          'id': b.id,
          'title': b.title,
          'author': b.author,
          'cover': covers[b.id],
        };
  final finished =
      books.where((b) => b.status == ReadingStatus.completed).length;
  final r = recap;
  final m = r?.milestone;
  return {
    'version': 1,
    'updatedAt': (now ?? DateTime.now()).millisecondsSinceEpoch,
    'total': books.length,
    'finished': finished,
    'hero': book(featured.isEmpty ? null : featured.first),
    'next': book(featured.length > 1 ? featured[1] : null),
    'labels': {
      'hero': continuing ? l10n.libraryContinueReading : l10n.libraryRecentlyAdded,
      'empty': l10n.widgetEmptyLibrary,
      'nextUp': l10n.widgetNextUp,
      'count': l10n.libraryFinishedCount(finished),
      'books': l10n.libraryAllBooks,
    },
    'recap': r == null || m == null
        ? null
        : {
            'completed': '${r.completed}${l10n.recapBooksUnit}',
            'checkpoints': l10n.recapCheckpoints,
            'toNext': m.next == null
                ? l10n.recapAllCheckpoints
                : l10n.recapToNextCheckpoint(m.remaining(r.completed), m.next!),
            'progress': m.progress(r.completed),
            'streak': '${r.currentStreak}${l10n.recapDaysUnit}',
            'streakOn': r.currentStreak > 0,
            'streakLabel':
                r.currentStreak > 0 ? l10n.recapStreak : l10n.recapStreakStart,
            'longest': l10n.recapLongestStreak(r.longestStreak),
            'weeks': l10n.recapLastFourWeeks,
            'days': r.recentDays,
            'readingDays': l10n.recapReadingDays(r.recentReadingDays),
            'month': l10n.recapMonthTitle(
                DateFormat.MMMM(localeTag).format(DateTime(2000, r.month))),
            'monthCompleted': '${r.completedThisMonth}${l10n.recapBooksUnit}',
            'monthLabel': l10n.recapFinishedThisMonth,
          },
  };
}

class HomeWidgets {
  HomeWidgets._();
  static final instance = HomeWidgets._();

  static const _channel = MethodChannel('lightlib/widgets');

  bool get supported => !kIsWeb && Platform.isAndroid;

  /// The last tap on a widget that the app has not acted on yet.
  final ValueNotifier<WidgetAction?> pending = ValueNotifier(null);

  bool _listening = false;

  /// Hears taps while the app runs, and the one that started it.
  Future<void> init() async {
    if (!supported || _listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'widgetAction') {
        pending.value = WidgetAction.fromMap(call.arguments);
      }
    });
    try {
      final first = await _channel.invokeMethod<Object?>('takeLaunchAction');
      final action = WidgetAction.fromMap(first);
      if (action != null) pending.value = action;
    } catch (_) {}
  }

  String? _lastJson;
  Timer? _debounce;

  /// Writes what the widgets show; repeated calls within a moment and
  /// unchanged content are folded into one update.
  void update({
    required List<LibraryBook> books,
    required ReadingRecap? recap,
    required AppLocalizations l10n,
    required String localeTag,
  }) {
    if (!supported) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      try {
        final shown = _shownBooks(books);
        final covers = {
          for (final b in shown) b.id: await _coverFile(b),
        };
        final snapshot = widgetSnapshot(
          books: books,
          recap: recap,
          l10n: l10n,
          localeTag: localeTag,
          covers: covers,
        );
        final key = jsonEncode({...snapshot, 'updatedAt': 0});
        if (key == _lastJson) return;
        _lastJson = key;
        await _channel.invokeMethod('update', {'snapshot': jsonEncode(snapshot)});
      } catch (e) {
        debugPrint('Home widgets not updated: $e');
      }
    });
  }

  List<LibraryBook> _shownBooks(List<LibraryBook> books) {
    final reading =
        books.where((b) => b.status == ReadingStatus.inProgress).toList();
    return (reading.isNotEmpty ? reading : books).take(2).toList();
  }

  /// A local file of [book]'s cover: the full-quality one read from the
  /// book, an imported book's picture, or the online cover fetched once.
  Future<String?> _coverFile(LibraryBook book) async {
    // A hidden cover is not drawn on the home screen either.
    await HiddenCovers.instance.load();
    if (HiddenCovers.instance.isHidden(book.id)) return null;
    final saved = BookCovers.instance.coverFor(book.id);
    if (saved != null && isLocalImagePath(saved)) {
      return localImageFilePath(saved);
    }
    final thumb = book.book.thumbnail;
    if (thumb == null || thumb.isEmpty) return null;
    if (isLocalImagePath(thumb)) return localImageFilePath(thumb);
    try {
      final dir = Directory(
          p.join((await getApplicationSupportDirectory()).path, 'widget_covers'));
      if (!await dir.exists()) await dir.create(recursive: true);
      final file = File(p.join(dir.path,
          '${book.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.img'));
      if (await file.exists() && await file.length() > 0) return file.path;
      final response = await http
          .get(Uri.parse(thumb), headers: coverHeadersFor(thumb))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;
      await file.writeAsBytes(response.bodyBytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }
}
