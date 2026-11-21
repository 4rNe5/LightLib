// How much room the window has, and where a foldable screen folds.
//
// Layouts follow the window's width (never a device or a posture): a
// phone, a folded foldable - one pane; an unfolded one, a tablet, a
// window dragged wide - two panes side by side, with the same parts in
// the same order. Where the screen has a fold down its middle, the panes
// meet at the fold, so nothing to read or tap lies on it.

// Dart imports:
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

// Flutter imports:
import 'package:flutter/material.dart';

/// Material's width classes: under 600 dp, 600 to 839, 840 and over.
enum WindowWidth { compact, medium, expanded }

WindowWidth windowWidthOf(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width >= 840) return WindowWidth.expanded;
  if (width >= 600) return WindowWidth.medium;
  return WindowWidth.compact;
}

/// Room for two panes side by side (an unfolded foldable is about 750 dp
/// wide: each pane is then about as wide as a phone).
bool useTwoPanes(BuildContext context) =>
    windowWidthOf(context) != WindowWidth.compact;

/// A fold or hinge that runs from the top of the screen to its bottom,
/// between two halves that are side by side: its place on the screen.
/// Null on a screen without one (or folded shut, or with the fold
/// running across).
Rect? verticalFoldOf(BuildContext context) =>
    _foldOf(context, vertical: true)?.bounds;

/// A fold that runs across the screen, between an upper and a lower half.
Rect? horizontalFoldOf(BuildContext context) =>
    _foldOf(context, vertical: false)?.bounds;

/// The screen is held half open (like a book, or standing on a table).
bool isHalfOpened(BuildContext context) => MediaQuery.maybeOf(context)
        ?.displayFeatures
        .any((f) => f.state == DisplayFeatureState.postureHalfOpened) ??
    false;

DisplayFeature? _foldOf(BuildContext context, {required bool vertical}) {
  final media = MediaQuery.maybeOf(context);
  if (media == null) return null;
  for (final f in media.displayFeatures) {
    if (f.type != DisplayFeatureType.fold &&
        f.type != DisplayFeatureType.hinge) {
      continue;
    }
    final b = f.bounds;
    final runsDown = b.height >= media.size.height * 0.8;
    final runsAcross = b.width >= media.size.width * 0.8;
    if (vertical && runsDown && !runsAcross) {
      // (Somewhere in the middle: a fold at the edge divides nothing.)
      if (b.center.dx > media.size.width * 0.25 &&
          b.center.dx < media.size.width * 0.75) {
        return f;
      }
    }
    if (!vertical && runsAcross && !runsDown) {
      if (b.center.dy > media.size.height * 0.25 &&
          b.center.dy < media.size.height * 0.75) {
        return f;
      }
    }
  }
  return null;
}

/// Two panes side by side: [start] takes the room there is, [end] the
/// rest. On a screen with a fold down its middle [end] begins just past
/// the fold; elsewhere it takes [endShare] of the width, within [minEnd]
/// and [maxEnd]. [trailing]: what lies between this widget's right edge
/// and the screen's (the tabs' rail), so the fold is found where it is.
class TwoPane extends StatelessWidget {
  const TwoPane({
    super.key,
    required this.start,
    required this.end,
    this.trailing = 0,
    this.endShare = 0.46,
    this.minEnd = 280,
    this.maxEnd = 460,
    this.gutter = 12,
  });

  final Widget start;
  final Widget end;
  final double trailing;
  final double endShare;
  final double minEnd;
  final double maxEnd;

  /// The room left between the panes (half of it on each side of a fold).
  final double gutter;

  /// How wide the end pane is in a row [width] wide on this screen.
  static double endWidth(
    BuildContext context,
    double width, {
    double trailing = 0,
    double endShare = 0.46,
    double minEnd = 280,
    double maxEnd = 460,
    double gutter = 12,
  }) {
    final fold = verticalFoldOf(context);
    if (fold != null) {
      final screen = MediaQuery.sizeOf(context).width;
      final past = screen - fold.right - gutter / 2 - trailing;
      // (A fold too near an edge of this row to give both panes room is
      // no place to split.)
      if (past >= 240 && width - past - gutter >= 200) return past;
    }
    return (width * endShare).clamp(minEnd, maxEnd).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final endWidth = TwoPane.endWidth(context, constraints.maxWidth,
          trailing: trailing,
          endShare: endShare,
          minEnd: minEnd,
          maxEnd: maxEnd,
          gutter: gutter);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: start),
          SizedBox(width: gutter),
          SizedBox(width: endWidth, child: end),
        ],
      );
    });
  }
}
