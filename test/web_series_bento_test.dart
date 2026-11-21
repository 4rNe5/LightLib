// The web library's series, packed: each a card as wide as its volumes
// need, rows that run edge to edge, one cover size within a row. They
// were one full-width row each, most of it empty: seven series took three
// screens of a wide window.

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/sync/sync_engine.dart' show RemoteBook;
import 'package:openlib/web/web_library.dart';
import 'package:openlib/web/web_series_bento.dart';

WebBook _volume(String series, int n) {
  final md5 = '${series.hashCode.abs()}'.padLeft(12, '0') +
      '$n'.padLeft(20, '0');
  return WebBook(
    md5: md5,
    series: series,
    remote: RemoteBook(
      md5: md5,
      bookId: 'local_$md5',
      fileName: '$series $n.epub',
      title: '$series $n',
      sizeBytes: 1024,
      hasFile: true,
      addedAt: DateTime.utc(2026, 11, 1),
    ),
  );
}

List<({String name, List<WebBook> volumes})> _series(
        Map<String, int> counts) =>
    [
      for (final MapEntry(key: name, value: n) in counts.entries)
        (name: name, volumes: [for (var i = 1; i <= n; i++) _volume(name, i)]),
    ];

// As in the owner's library: short series, and one longer than a line.
const _counts = {
  'Wind': 4,
  'Fog': 6,
  'Stars': 2,
  'Cat': 3,
  'Door': 2,
  'Shore': 14,
  'Summer': 2,
};

void main() {
  group('packSeries', () {
    const wide = BentoSizes(target: 104, gap: 16, inner: 10, pad: 12);
    // A 1440 px window: the library beside the side bar.
    const width = 1116.0;

    test('cards go where there is room, and each row reaches the edge', () {
      final rows =
          packSeries(_counts.values.toList(), width: width, sizes: wide);
      // Every series once, in a row of its own or beside others.
      expect([for (final r in rows) ...r.items]..sort(),
          List.generate(_counts.length, (i) => i));
      // Seven series in four rows, not seven: the small ones fill the
      // gaps the larger ones left.
      expect(rows.length, 4);
      expect(rows.first.items, [0, 2, 3]);
      for (final row in rows) {
        var used = (row.items.length - 1) * wide.gap;
        for (final k in row.perLine) {
          used += wide.card(k, row.cover);
        }
        expect(used, lessThanOrEqualTo(width + 0.01), reason: '$row');
        expect(row.cover, inInclusiveRange(wide.target, wide.target * 1.3));
        // A full row runs to the edge; only a row that would have to grow
        // its covers past the limit stops short.
        if (row.cover < wide.target * 1.3) {
          expect(used, closeTo(width, 0.01), reason: '$row');
        }
      }
    });

    test('a series longer than a line takes a whole row, one line of it',
        () {
      final most = wide.lineOf(width);
      final rows = packSeries([11, 2], width: width, sizes: wide);
      expect(rows.first.items, [0]);
      expect(rows.first.perLine, [most]);
      expect(rows[1].items, [1]);
    });

    test('a phone: two short series side by side', () {
      final phone = BentoSizes.of(361, wide: false);
      final rows = packSeries([2, 2, 3], width: 361, sizes: phone);
      expect(rows.first.items, [0, 1]);
      expect(rows.first.cover, greaterThanOrEqualTo(phone.target));
    });
  });

  Future<void> pump(WidgetTester tester, double width, {Set<String>? open}) async {
    final expanded = open ?? <String>{};
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: Center(
            child: SizedBox(
              width: width,
              child: StatefulBuilder(
                builder: (context, setState) => WebSeriesBento(
                  series: _series(_counts),
                  wide: width > 600,
                  expanded: expanded,
                  onExpand: (name) => setState(() => expanded.contains(name)
                      ? expanded.remove(name)
                      : expanded.add(name)),
                  header: (s) => Text(s.name),
                  tile: (b, caption) => Column(
                    key: ValueKey('tile:${b.title}'),
                    children: [
                      const Expanded(child: ColoredBox(color: Colors.grey)),
                      Text(caption, maxLines: 1),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('seven series on one screen of a wide window', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.reset);
    await pump(tester, 1116);
    expect(tester.takeException(), isNull);
    final bento = find.byKey(const ValueKey('webSeriesBento'));
    // (Under the bar and the book being read: about 700 of the 900.)
    expect(tester.getSize(bento).height, lessThan(720));
    for (final name in _counts.keys) {
      expect(find.byKey(ValueKey('webSeries:$name')), findsOneWidget);
    }
    // Three rows; the covers of a row are all one size.
    final tops = {
      for (final name in _counts.keys)
        tester.getTopLeft(find.byKey(ValueKey('webSeries:$name'))).dy,
    };
    expect(tops.length, 3);
    final stars = tester.getSize(find.byKey(const ValueKey('tile:Stars 2')));
    final summer = tester.getSize(find.byKey(const ValueKey('tile:Summer 1')));
    expect(summer, stars);
    // Under a cover, the volume - the series' name is over the card.
    expect(find.text('Volume 1'), findsNWidgets(_counts.length));
  });

  testWidgets('a long series shows a line, and the rest when asked',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.reset);
    await pump(tester, 1116);
    final more = find.byKey(const ValueKey('webSeriesMore:Shore'));
    expect(more, findsOneWidget);
    // (Eleven to a line at that width: ten, and how many more.)
    expect(find.text('+4'), findsOneWidget);
    expect(find.byKey(const ValueKey('tile:Shore 10')), findsOneWidget);
    expect(find.byKey(const ValueKey('tile:Shore 11')), findsNothing);

    await tester.tap(more);
    await tester.pump();
    expect(find.byKey(const ValueKey('tile:Shore 14')), findsOneWidget);
    expect(find.byKey(const ValueKey('webSeriesMore:Shore')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('webSeriesLess:Shore')));
    await tester.pump();
    expect(find.byKey(const ValueKey('tile:Shore 14')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a phone: nothing runs over the edge', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 851);
    addTearDown(tester.view.reset);
    await pump(tester, 361);
    expect(tester.takeException(), isNull);
    final stars = tester.getRect(find.byKey(const ValueKey('webSeries:Stars')));
    final door = tester.getRect(find.byKey(const ValueKey('webSeries:Door')));
    // Two short series side by side.
    expect(door.top, stars.top);
    expect(door.right, lessThanOrEqualTo(16 + 361 + 0.01));
  });
}
