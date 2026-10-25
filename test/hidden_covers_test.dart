// Hiding a library book's cover: the saved list, the cover in the
// library, and the switch.

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/database.dart';
import 'package:openlib/services/hidden_covers.dart';
import 'package:openlib/services/library_organization.dart';
import 'package:openlib/ui/components/hide_cover_controls.dart';
import 'package:openlib/ui/components/library_tiles.dart';

LibraryBook _book(String id) => LibraryBook(
      book: MyBook(
        id: id,
        title: 'Title $id',
        author: null,
        thumbnail: null,
        link: '',
        publisher: null,
        info: null,
        format: 'epub',
        description: null,
      ),
      tags: const {},
      status: ReadingStatus.unread,
    );

Widget _app(Widget child) => ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('ko'),
        home: Scaffold(body: child),
      ),
    );

void main() {
  tearDown(() => HiddenCovers.instance.debugSet({}));

  test('the saved list reads back, and nothing from anything else', () {
    expect(HiddenCovers.decode('["a","b"]'), {'a', 'b'});
    expect(HiddenCovers.decode(null), isEmpty);
    expect(HiddenCovers.decode(''), isEmpty);
    expect(HiddenCovers.decode('{"a":1}'), isEmpty);
    expect(HiddenCovers.decode('not json'), isEmpty);
  });

  testWidgets('a hidden cover shows the title card, only for that book',
      (tester) async {
    HiddenCovers.instance.debugSet({'b'});
    await tester.pumpWidget(_app(Row(children: [
      SizedBox(width: 100, height: 150, child: BookCover(book: _book('a'))),
      SizedBox(width: 100, height: 150, child: BookCover(book: _book('b'))),
    ])));
    expect(find.byKey(const ValueKey('hiddenCover')), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('hiddenCover')),
            matching: find.text('Title b')),
        findsOneWidget);

    // Shown again at once.
    HiddenCovers.instance.setHidden('b', false).ignore();
    await tester.pump();
    expect(find.byKey(const ValueKey('hiddenCover')), findsNothing);
  });

  testWidgets('the switch and the button hide and show the cover',
      (tester) async {
    HiddenCovers.instance.debugSet({});
    await tester.pumpWidget(_app(const Column(children: [
      HideCoverSwitch(bookId: 'a'),
      HideCoverButton(bookId: 'a'),
    ])));
    expect(find.text('표지 가리기'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hideCover')));
    await tester.pump();
    expect(HiddenCovers.instance.isHidden('a'), isTrue);
    expect(
        tester.widget<SwitchListTile>(find.byKey(const ValueKey('hideCover')))
            .value,
        isTrue);
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hideCoverButton')));
    await tester.pump();
    expect(HiddenCovers.instance.isHidden('a'), isFalse);
  });
}
