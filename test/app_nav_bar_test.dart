// The tab bar: at the bottom on a phone (one capsule under the selected
// tab, its label shown, taps reported, the selected tab not re-reported),
// down the left edge on a wide screen.

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/ui/components/app_nav_bar.dart';

const _items = [
  AppNavItem(icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'Home'),
  AppNavItem(icon: Icons.search, selectedIcon: Icons.search, label: 'Search'),
  AppNavItem(icon: Icons.book_outlined, selectedIcon: Icons.book, label: 'Library'),
];

Widget _bar(int selected, ValueChanged<int> onSelected) => MaterialApp(
      home: Scaffold(
        bottomNavigationBar: AppNavBar(
          items: _items,
          selectedIndex: selected,
          onSelected: onSelected,
        ),
      ),
    );

void main() {
  testWidgets('shows the selected label and reports other taps',
      (tester) async {
    final taps = <int>[];
    await tester.pumpWidget(_bar(0, taps.add));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Search'), findsNothing);
    expect(find.byKey(const ValueKey('navIndicator')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('navTab-0')));
    await tester.tap(find.byKey(const ValueKey('navTab-2')));
    expect(taps, [2]);
  });

  testWidgets('the capsule moves under the new tab', (tester) async {
    await tester.pumpWidget(_bar(0, (_) {}));
    await tester.pumpAndSettle();
    final before =
        tester.getTopLeft(find.byKey(const ValueKey('navIndicator'))).dx;
    await tester.pumpWidget(_bar(2, (_) {}));
    await tester.pumpAndSettle();
    final after =
        tester.getTopLeft(find.byKey(const ValueKey('navIndicator'))).dx;
    expect(after, greaterThan(before));
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
  });

  testWidgets('tabs switch with no animation when motion is reduced',
      (tester) async {
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: _bar(1, (_) {}),
    ));
    await tester.pump();
    expect(find.text('Search'), findsOneWidget);
  });

  testWidgets('the capsule never leaves the bar on its way to an end',
      (tester) async {
    for (final (from, to) in [(0, 2), (2, 0)]) {
      await tester.pumpWidget(_bar(from, (_) {}));
      await tester.pumpAndSettle();
      final bar = tester.getRect(find.byType(AppNavBar));
      await tester.pumpWidget(_bar(to, (_) {}));
      var widest = 0.0;
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final r = tester.getRect(find.byKey(const ValueKey('navIndicator')));
        expect(r.left, greaterThanOrEqualTo(bar.left + 16));
        expect(r.right, lessThanOrEqualTo(bar.right - 16));
        if (r.width > widest) widest = r.width;
      }
      final end = tester.getRect(find.byKey(const ValueKey('navIndicator')));
      // It stretched on the way and settled at its own width.
      expect(widest, greaterThan(end.width));
    }
  });

  Widget rail(int selected, ValueChanged<int> onSelected) => MaterialApp(
        home: Scaffold(
          body: Row(children: [
            AppNavRail(
                items: _items, selectedIndex: selected, onSelected: onSelected),
            const Expanded(child: SizedBox()),
          ]),
        ),
      );

  testWidgets('a wide screen gets the pill on its side: taps reported',
      (tester) async {
    final taps = <int>[];
    await tester.pumpWidget(rail(1, taps.add));
    await tester.pumpAndSettle();
    // The selected tab's name only, as in the bar.
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
    expect(find.byKey(const ValueKey('navRailIndicator')), findsOneWidget);
    // Centred top to bottom, in order, on the left edge.
    final home = tester.getCenter(find.byKey(const ValueKey('navRailTab-0')));
    final library =
        tester.getCenter(find.byKey(const ValueKey('navRailTab-2')));
    final screen = tester.getRect(find.byType(Scaffold));
    expect(home.dy, lessThan(library.dy));
    final pill = tester.getRect(find.descendant(
        of: find.byKey(const ValueKey('navRail')),
        matching: find.byType(BackdropFilter)));
    expect(pill.center.dy, closeTo(screen.center.dy, 1));
    expect(pill.left, 12);
    expect(pill.width, AppNavRail.pillWidth);
    await tester.tap(find.byKey(const ValueKey('navRailTab-1')));
    await tester.tap(find.byKey(const ValueKey('navRailTab-2')));
    expect(taps, [2]);
  });

  testWidgets('the rail\'s capsule never leaves the pill on its way',
      (tester) async {
    for (final (from, to) in [(0, 2), (2, 0)]) {
      await tester.pumpWidget(rail(from, (_) {}));
      await tester.pumpAndSettle();
      final pill = tester.getRect(find.descendant(
          of: find.byKey(const ValueKey('navRail')),
          matching: find.byType(BackdropFilter)));
      await tester.pumpWidget(rail(to, (_) {}));
      var tallest = 0.0;
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final r =
            tester.getRect(find.byKey(const ValueKey('navRailIndicator')));
        expect(r.top, greaterThanOrEqualTo(pill.top + 6 - 0.01));
        expect(r.bottom, lessThanOrEqualTo(pill.bottom - 6 + 0.01));
        if (r.height > tallest) tallest = r.height;
      }
      final end =
          tester.getRect(find.byKey(const ValueKey('navRailIndicator')));
      expect(tallest, greaterThan(end.height));
    }
  });

  testWidgets('the rail from 600 wide: unfolded yes, folded no',
      (tester) async {
    Future<bool> at(Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      late bool rail;
      await tester.pumpWidget(MaterialApp(
          home: Builder(builder: (context) {
        rail = useNavRail(context);
        return const SizedBox();
      })));
      return rail;
    }

    addTearDown(tester.view.reset);
    expect(await at(const Size(412, 915)), isFalse); // a folded phone
    expect(await at(const Size(884, 1104)), isTrue); // unfolded (Fold)
    expect(await at(const Size(915, 412)), isTrue); // a phone on its side
  });
}
