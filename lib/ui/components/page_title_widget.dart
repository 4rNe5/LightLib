// Flutter imports:
import 'package:flutter/material.dart';

class TitleText extends StatelessWidget {
  const TitleText(this.text, {super.key});

  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 10, bottom: 7),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.secondary,
        ),
      ),
    );
  }
}

/// The large title at the top of each main tab (Home, Search, Library,
/// Settings), in place of a shared app bar. [trailing] sits on the
/// title's baseline row, [subtitle] under it.
class LargeTitle extends StatelessWidget {
  const LargeTitle(
    this.text, {
    super.key,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(4, 4, 0, 8),
  });

  final String text;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  static const style = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
    height: 1.15,
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: Text(text,
                      key: const ValueKey('largeTitle'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style.copyWith(color: scheme.onSurface)),
                ),
                if (subtitle != null)
                  Text(subtitle!,
                      style: TextStyle(
                          fontSize: 13, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
