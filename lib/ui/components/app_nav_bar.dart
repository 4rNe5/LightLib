// The app's bottom tab bar: a floating, frosted pill. The selected tab
// widens into a filled capsule that slides between tabs with a little
// overshoot; its icon pops and its label slides in. Motion follows the
// system's reduce-motion setting.

// Dart imports:
import 'dart:ui' as ui;

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppNavItem {
  const AppNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class AppNavBar extends StatelessWidget {
  const AppNavBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<AppNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const height = 64.0;

  /// The selected tab's share of the bar's width; the rest split it.
  static const _selectedShare = 0.36;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final accent = theme.colorScheme.secondary;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final slide =
        reduce ? Duration.zero : const Duration(milliseconds: 420);
    const curve = Curves.easeOutBack;
    final barColor = dark
        ? const Color(0xFF1B1B1D).withValues(alpha: 0.86)
        : Colors.white.withValues(alpha: 0.88);
    final idleColor = dark ? const Color(0xFFB9B9BE) : const Color(0xFF5E5E66);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(height / 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.45 : 0.07),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(height / 2),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              height: height,
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: BorderRadius.circular(height / 2),
                border: Border.all(
                  color: dark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.06),
                ),
              ),
              padding: const EdgeInsets.all(6),
              child: LayoutBuilder(builder: (context, constraints) {
                final width = constraints.maxWidth;
                final n = items.length;
                final wide = width * _selectedShare;
                final narrow = n > 1 ? (width - wide) / (n - 1) : width;
                double left(int i) =>
                    i <= selectedIndex ? i * narrow : wide + (i - 1) * narrow;
                return Stack(
                  children: [
                    // The capsule under the selected tab.
                    AnimatedPositioned(
                      duration: slide,
                      curve: curve,
                      left: left(selectedIndex),
                      top: 0,
                      bottom: 0,
                      width: wide,
                      child: DecoratedBox(
                        key: const ValueKey('navIndicator'),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(height / 2),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color.lerp(accent, Colors.white, 0.12)!,
                              Color.lerp(accent, Colors.black, 0.12)!,
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.22),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                    for (var i = 0; i < n; i++)
                      AnimatedPositioned(
                        duration: slide,
                        curve: curve,
                        left: left(i),
                        top: 0,
                        bottom: 0,
                        width: i == selectedIndex ? wide : narrow,
                        child: _NavButton(
                          key: ValueKey('navTab-$i'),
                          item: items[i],
                          selected: i == selectedIndex,
                          idleColor: idleColor,
                          reduceMotion: reduce,
                          onTap: () {
                            if (i == selectedIndex) return;
                            HapticFeedback.selectionClick();
                            onSelected(i);
                          },
                        ),
                      ),
                  ],
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    super.key,
    required this.item,
    required this.selected,
    required this.idleColor,
    required this.reduceMotion,
    required this.onTap,
  });

  final AppNavItem item;
  final bool selected;
  final Color idleColor;
  final bool reduceMotion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fade =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 260);
    final color = selected ? Colors.white : idleColor;
    final icon = TweenAnimationBuilder<double>(
      // A new key for each selection replays the pop.
      key: ValueKey(selected),
      tween: Tween(begin: selected && !reduceMotion ? 0.0 : 1.0, end: 1.0),
      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 520),
      curve: Curves.elasticOut,
      builder: (context, t, child) => Transform.scale(
        scale: selected ? 0.7 + 0.3 * t : 1.0,
        child: child,
      ),
      child: AnimatedSwitcher(
        duration: fade,
        transitionBuilder: (child, animation) =>
            FadeTransition(opacity: animation, child: child),
        child: Icon(
          selected ? item.selectedIcon : item.icon,
          key: ValueKey(selected),
          size: 23,
          color: color,
        ),
      ),
    );

    return Semantics(
      selected: selected,
      button: true,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              // The label of the selected tab slides in beside its icon.
              Flexible(
                child: AnimatedSize(
                  duration: fade,
                  curve: Curves.easeOutCubic,
                  child: selected
                      ? Padding(
                          padding: const EdgeInsets.only(left: 7),
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: reduceMotion ? 1 : 0, end: 1),
                            duration: fade,
                            curve: Curves.easeOutCubic,
                            builder: (context, t, child) => Opacity(
                              opacity: t,
                              child: Transform.translate(
                                  offset: Offset(8 * (1 - t), 0),
                                  child: child),
                            ),
                            child: Text(
                              item.label,
                              maxLines: 1,
                              overflow: TextOverflow.fade,
                              softWrap: false,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Switches between the tabs' pages with a short fade and lift.
class AppTabSwitcher extends StatelessWidget {
  const AppTabSwitcher({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return AnimatedSwitcher(
      duration: reduce ? Duration.zero : const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, if (current != null) current],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.015), end: Offset.zero)
              .animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey('tab-$index'), child: child),
    );
  }
}
