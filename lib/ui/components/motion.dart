// The app's motion: one set of timings and curves, and the few moving
// parts built on them - a tile that gives under the finger, content that
// rises into place, a number that counts up, a route that fades through.
//
// Motion says what happened (this was pressed, that came from there); it
// is short, it never blocks a tap, and with the system's "remove
// animations" setting everything here stands still.

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

abstract final class AppMotion {
  /// A press, a toggle.
  static const quick = Duration(milliseconds: 140);

  /// Something on the page changing place or size.
  static const standard = Duration(milliseconds: 280);

  /// A pane or a page coming in.
  static const emphasized = Duration(milliseconds: 420);

  /// Fast out, long soft landing (Material's "emphasized decelerate").
  static const Curve enter = Cubic(0.05, 0.7, 0.1, 1);

  /// Leaving: quicker than arriving.
  static const Curve exit = Cubic(0.3, 0, 0.8, 0.15);

  /// A spring with a little life in it, for things under the finger.
  static final SpringDescription press = SpringDescription.withDampingRatio(
      mass: 1, stiffness: 520, ratio: 0.62);

  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

/// [child] gives a little under the finger and springs back when let go:
/// the tap is felt before anything else happens. Taps and long presses
/// are this widget's own (no ink).
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.96,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// How small it gets while held.
  final double scale;
  final HitTestBehavior behavior;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController.unbounded(vsync: this, value: 0);

  void _to(double target) {
    if (!mounted) return;
    if (AppMotion.reduced(context)) {
      _c.value = 0;
      return;
    }
    _c.animateWith(
        SpringSimulation(AppMotion.press, _c.value, target, _c.velocity));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: enabled ? (_) => _to(1) : null,
      onTapUp: enabled ? (_) => _to(0) : null,
      onTapCancel: enabled ? () => _to(0) : null,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) => Transform.scale(
          scale: 1 - (1 - widget.scale) * _c.value.clamp(-0.4, 1.2),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}

/// [child] fades in and rises a few pixels, once, when first built -
/// later by [delay] (items of a list: each a little after the one
/// before). Built again, it stays where it is.
class Appear extends StatefulWidget {
  const Appear({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 14,
    this.duration = AppMotion.emphasized,
  });

  /// The [index]th of a run of items: 35 ms after the one before, the
  /// ninth and later with the eighth (a long list does not trickle in).
  Appear.staggered(int index, {Key? key, required Widget child})
      : this(
            key: key,
            child: child,
            delay: Duration(milliseconds: 35 * index.clamp(0, 8)));

  final Widget child;
  final Duration delay;
  final double offset;
  final Duration duration;

  @override
  State<Appear> createState() => _AppearState();
}

class _AppearState extends State<Appear> with SingleTickerProviderStateMixin {
  // One clock for the wait and the move (no timer is left waiting when
  // the widget goes before its turn).
  late final Duration _total = widget.delay + widget.duration;
  late final AnimationController _c =
      AnimationController(vsync: this, duration: _total);
  late final double _wait = _total == Duration.zero
      ? 0
      : widget.delay.inMicroseconds / _total.inMicroseconds;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AppMotion.reduced(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        if (_c.value >= 1) return child!;
        final moved = _wait >= 1
            ? 1.0
            : ((_c.value - _wait) / (1 - _wait)).clamp(0.0, 1.0).toDouble();
        final t = AppMotion.enter.transform(moved);
        return Opacity(
          opacity: t.clamp(0.0, 1.0).toDouble(),
          child: Transform.translate(
              offset: Offset(0, widget.offset * (1 - t)), child: child),
        );
      },
      child: widget.child,
    );
  }
}

/// A number that counts up to [value] when first shown and from the old
/// value when it changes.
class CountUp extends StatelessWidget {
  const CountUp(this.value,
      {super.key, required this.style, this.suffix = '', this.prefix = ''});

  final int value;
  final TextStyle style;
  final String suffix;
  final String prefix;

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduced(context)) {
      return Text('$prefix$value$suffix', style: style);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.toDouble()),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) =>
          Text('$prefix${v.round()}$suffix', style: style),
    );
  }
}

/// A bar that fills to [value] (0..1; null: how far is not known, an
/// even, still track) and moves when [value] does.
class ProgressBar extends StatelessWidget {
  const ProgressBar({
    super.key,
    required this.value,
    this.height = 4,
    this.color,
    this.trackColor,
  });

  final double? value;
  final double height;
  final Color? color;
  final Color? trackColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = color ?? scheme.primary;
    final track = trackColor ?? scheme.onSurface.withValues(alpha: 0.12);
    final target = (value ?? 0).clamp(0.0, 1.0).toDouble();
    Widget bar(double v) => ClipRRect(
          borderRadius: BorderRadius.circular(height),
          child: SizedBox(
            height: height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: track),
                FractionallySizedBox(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: v,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: fill,
                      borderRadius: BorderRadius.circular(height),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
    if (AppMotion.reduced(context)) return bar(target);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: target),
      duration: const Duration(milliseconds: 600),
      curve: AppMotion.enter,
      builder: (context, v, _) => bar(v),
    );
  }
}

/// A page that fades in over the one before (no slide): for a page that
/// shares a picture with the one it comes from - the picture flies, the
/// rest changes around it.
class FadeThroughRoute<T> extends PageRouteBuilder<T> {
  FadeThroughRoute({required WidgetBuilder builder, super.settings})
      : super(
          pageBuilder: (context, _, __) => builder(context),
          transitionDuration: const Duration(milliseconds: 380),
          reverseTransitionDuration: const Duration(milliseconds: 260),
          transitionsBuilder: (context, animation, _, child) {
            if (AppMotion.reduced(context)) return child;
            return FadeTransition(
              opacity: CurvedAnimation(
                  parent: animation,
                  curve: const Interval(0, 0.7, curve: Curves.easeOut),
                  reverseCurve: Curves.easeIn),
              child: child,
            );
          },
        );
}
