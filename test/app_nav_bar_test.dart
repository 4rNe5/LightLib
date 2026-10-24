// The bottom tab bar: one capsule under the selected tab, its label
// shown, taps reported, the selected tab not re-reported.

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
}
