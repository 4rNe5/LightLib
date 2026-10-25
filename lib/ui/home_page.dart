import 'package:flutter/material.dart';
import 'package:openlib/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlib/state/state.dart';
import 'package:openlib/ui/categories_page.dart';
import 'package:openlib/ui/components/active_downloads_widget.dart';
import 'package:openlib/ui/components/page_title_widget.dart';
import 'package:openlib/ui/trending_page.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final List<Widget> _pages = const [
    TrendingPage(),
    GenresPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final selectedIndex = ref.watch(homePageSelectedIndexProvider);
    return Scaffold(
      body: Column(
        children: [
          const SizedBox(height: 8),
          const ActiveDownloadsWidget(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
            child: LargeTitle(
              selectedIndex == 0
                  ? AppLocalizations.of(context).trending
                  : AppLocalizations.of(context).genres,
              padding: EdgeInsets.zero,
              trailing: PelletContainer(
                selectedIndex: selectedIndex,
                onTrendingSelected: () => {
                  ref.read(homePageSelectedIndexProvider.notifier).state = 0
                },
                onCategoriesSelected: () => {
                  ref.read(homePageSelectedIndexProvider.notifier).state = 1
                },
              ),
            ),
          ),
          const _RegionSwitch(),
          Expanded(child: _pages[selectedIndex]), // Display the selected page
        ],
      ),
    );
  }
}

class PelletContainer extends StatelessWidget {
  final int selectedIndex;
  final VoidCallback onTrendingSelected;
  final VoidCallback onCategoriesSelected;

  const PelletContainer({
    super.key,
    required this.selectedIndex,
    required this.onTrendingSelected,
    required this.onCategoriesSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      width: 105,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: Theme.of(context).colorScheme.secondary,
        // Border matches secondary color to avoid white border in dark mode
        border: Border.all(color: Theme.of(context).colorScheme.secondary),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Left Button (Trending)
          Expanded(
            child: GestureDetector(
              onTap: onTrendingSelected,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                decoration: BoxDecoration(
                  color: selectedIndex == 0
                      ? Theme.of(context).colorScheme.secondary
                      : (Theme.of(context).brightness == Brightness.dark
                          ? const Color(
                              0xFF1E1E1E) // Dark Grey for unselected in Dark Mode
                          : Theme.of(context)
                              .colorScheme
                              .primary), // White for unselected in Light Mode
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(25),
                    bottomLeft: Radius.circular(25),
                    topRight: Radius.circular(0),
                    bottomRight: Radius.circular(0),
                  ),
                ),
                child: TextButton.icon(
                  onPressed: null, // Disable direct onPressed to avoid conflict
                  icon: Icon(
                    Icons.trending_up,
                    color: selectedIndex == 0
                        ? Colors.white // Always white when selected (on Red)
                        : Theme.of(context)
                            .colorScheme
                            .tertiary, // Black/White based on theme when unselected
                  ),
                  label: const Text(''), // Empty label
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ),
            ),
          ),
          const VerticalDivider(
            width: 0,
            thickness: 1,
            color: Colors.grey,
          ),
          // Right Button (Categories)
          Expanded(
            child: GestureDetector(
              onTap: onCategoriesSelected,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                decoration: BoxDecoration(
                  color: selectedIndex == 1
                      ? Theme.of(context).colorScheme.secondary
                      : (Theme.of(context).brightness == Brightness.dark
                          ? const Color(
                              0xFF1E1E1E) // Dark Grey for unselected in Dark Mode
                          : Theme.of(context)
                              .colorScheme
                              .primary), // White for unselected in Light Mode
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(0),
                    bottomLeft: Radius.circular(0),
                    topRight: Radius.circular(25),
                    bottomRight: Radius.circular(25),
                  ),
                ),
                child: TextButton.icon(
                  onPressed: null,
                  icon: Icon(
                    Icons.dashboard_rounded,
                    color: selectedIndex == 1
                        ? Colors.white // Always white when selected (on Red)
                        : Theme.of(context)
                            .colorScheme
                            .tertiary, // Black/White based on theme when unselected
                  ),
                  label: const Text(''), // Empty label
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Japan (the default) or the English-speaking world.
class _RegionSwitch extends ConsumerWidget {
  const _RegionSwitch();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final region = ref.watch(homeRegionProvider);
    // Text tabs with a bar under the chosen one: lighter than a second
    // row of buttons above the category chips.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
      child: Row(
        key: const ValueKey('homeRegion'),
        children: [
          for (final r in HomeRegion.values)
            _RegionTab(
              key: ValueKey('homeRegion-${r.name}'),
              label: r == HomeRegion.japan
                  ? l10n.homeRegionJapan
                  : l10n.homeRegionWestern,
              selected: r == region,
              onTap: () => ref.read(homeRegionProvider.notifier).set(r),
            ),
        ],
      ),
    );
  }
}

class _RegionTab extends StatelessWidget {
  const _RegionTab({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, 6, 14, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: (theme.textTheme.titleMedium ?? const TextStyle())
                    .copyWith(
                  fontSize: 17,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected
                      ? scheme.onSurface
                      : scheme.onSurface.withValues(alpha: 0.45),
                ),
                child: Text(label),
              ),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                height: 3,
                width: selected ? 20 : 0,
                decoration: BoxDecoration(
                  color: scheme.secondary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
