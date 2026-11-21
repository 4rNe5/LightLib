// The series of the web library, packed: each series a card as wide as
// its volumes need, the cards laid in rows that run edge to edge, the
// covers of a row all one size - so a screen shows many series at once,
// not one full-width row each with most of it empty.

// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/search_results.dart' show volumeOf;
import 'package:openlib/web/web_library.dart';

/// One row of the packing: which cards ([items], by their place in the
/// list given), each one's covers on a line ([perLine]), and the width of
/// every cover in the row.
@immutable
class BentoRow {
  const BentoRow(this.items, this.perLine, this.cover);

  final List<int> items;
  final List<int> perLine;
  final double cover;

  @override
  String toString() => 'BentoRow($items, $perLine, ${cover.toStringAsFixed(1)})';
}

/// How the series' cards are laid out in [width].
@immutable
class BentoSizes {
  const BentoSizes({
    required this.target,
    required this.gap,
    required this.inner,
    required this.pad,
    this.stretch = 1.3,
  });

  /// A wide window, a phone (or a window under 520 wide), what lies
  /// between.
  /// (A wide window's covers start at 88: seven series of the owner's
  /// kind - 2 to 6 volumes, one of 11 - in three rows under the book
  /// being read, on one screen of a 1440 x 900 window. At 104 they took
  /// four rows and 1,060 px.)
  factory BentoSizes.of(double width, {required bool wide}) => wide
      ? const BentoSizes(target: 88, gap: 16, inner: 10, pad: 12)
      : width < 520
          ? const BentoSizes(target: 70, gap: 10, inner: 8, pad: 10)
          : const BentoSizes(target: 80, gap: 14, inner: 10, pad: 12);

  /// The width a cover is packed at; a row then grows its covers to fill.
  final double target;

  /// Between the cards.
  final double gap;

  /// Between the covers of a card.
  final double inner;

  /// Round a card's covers (each side).
  final double pad;

  /// How far a row's covers may grow to reach the edge ([target] times
  /// this); a row that would need more stays as it is, at the start.
  final double stretch;

  /// How wide a card of [n] covers on a line is, at cover width [cover].
  double card(int n, double cover) => n * cover + (n - 1) * inner + 2 * pad;

  /// How many covers fit on a line of a card as wide as [width].
  int lineOf(double width) =>
      ((width - 2 * pad + inner) / (target + inner)).floor().clamp(1, 1 << 20);
}

/// [counts] (each series' number of volumes, in the order shown) packed
/// into rows [width] wide. A card asks for its volumes on one line, or a
/// whole row where they do not fit (they go on more lines there). Each
/// card takes the first row with room for it at [BentoSizes.target] - a
/// small series fills a gap an earlier row left - and each row's covers
/// then grow, all alike, until the row reaches the edge.
List<BentoRow> packSeries(List<int> counts,
    {required double width, required BentoSizes sizes}) {
  final most = sizes.lineOf(width);
  final rows = <({List<int> items, List<int> perLine, double used})>[];
  for (var i = 0; i < counts.length; i++) {
    final k = counts[i].clamp(1, most);
    final w = sizes.card(k, sizes.target);
    var placed = false;
    for (var r = 0; r < rows.length && !placed; r++) {
      final row = rows[r];
      if (row.used + sizes.gap + w <= width + 0.01) {
        rows[r] = (
          items: [...row.items, i],
          perLine: [...row.perLine, k],
          used: row.used + sizes.gap + w,
        );
        placed = true;
      }
    }
    if (!placed) rows.add((items: [i], perLine: [k], used: w));
  }
  return [
    for (final row in rows)
      BentoRow(row.items, row.perLine, () {
        final covers = row.perLine.fold<int>(0, (a, k) => a + k);
        var fixed = (row.items.length - 1) * sizes.gap;
        for (final k in row.perLine) {
          fixed += (k - 1) * sizes.inner + 2 * sizes.pad;
        }
        final fill = (width - fixed) / covers;
        return fill.clamp(sizes.target, sizes.target * sizes.stretch);
      }()),
  ];
}

/// How a volume is called under its cover in its series' card: its
/// number (the series' name is over the card), or its title where the
/// title names none.
String volumeCaption(AppLocalizations l10n, WebBook book) {
  final v = volumeOf(book.title).display;
  return v.isEmpty ? book.title : l10n.volumeNumber(v);
}

/// The series, packed (see [packSeries]). [tile] draws a volume at the
/// width given, with its caption; [header] the card's name line. A card
/// whose volumes go on more than one line shows one line and a tile with
/// how many more, until it is opened ([expanded], [onExpand]).
class WebSeriesBento extends StatelessWidget {
  const WebSeriesBento({
    super.key,
    required this.series,
    required this.wide,
    required this.tile,
    required this.header,
    this.expanded = const {},
    this.onExpand,
  });

  final List<({String name, List<WebBook> volumes})> series;
  final bool wide;
  final Widget Function(WebBook book, String caption) tile;
  final Widget Function(({String name, List<WebBook> volumes}) s) header;
  final Set<String> expanded;
  final ValueChanged<String>? onExpand;

  /// A cover's caption: one line.
  static const caption = 26.0;

  /// The card's name line.
  static const headerHeight = 30.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final sizes = BentoSizes.of(width, wide: wide);
      // A series longer than a line asks for a whole row; folded, it
      // shows a line of it.
      final rows = packSeries([for (final s in series) s.volumes.length],
          width: width, sizes: sizes);
      return Column(
        key: const ValueKey('webSeriesBento'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in rows)
            Padding(
              padding: EdgeInsets.only(bottom: sizes.gap),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var j = 0; j < row.items.length; j++) ...[
                    if (j > 0) SizedBox(width: sizes.gap),
                    _card(context, l10n, scheme, series[row.items[j]],
                        row.perLine[j], row.cover, sizes),
                  ],
                ],
              ),
            ),
        ],
      );
    });
  }

  Widget _card(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme scheme,
    ({String name, List<WebBook> volumes}) s,
    int perLine,
    double cover,
    BentoSizes sizes,
  ) {
    final long = s.volumes.length > perLine;
    final open = !long || expanded.contains(s.name);
    // Folded: the first volumes, the last place telling how many more.
    final shown = open ? s.volumes : s.volumes.take(perLine - 1).toList();
    final more = s.volumes.length - shown.length;
    final tileHeight = cover / 0.7 + caption;
    return Container(
      key: ValueKey('webSeries:${s.name}'),
      width: sizes.card(perLine, cover),
      padding: EdgeInsets.fromLTRB(sizes.pad, 8, sizes.pad, sizes.pad - 2),
      decoration: BoxDecoration(
        color: scheme.onSurface.withAlpha(12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: headerHeight, child: header(s)),
          Wrap(
            spacing: sizes.inner,
            runSpacing: 12,
            children: [
              for (final b in shown)
                SizedBox(
                  width: cover,
                  height: tileHeight,
                  child: tile(b, volumeCaption(l10n, b)),
                ),
              if (more > 0)
                SizedBox(
                  width: cover,
                  height: tileHeight,
                  child: _More(
                    key: ValueKey('webSeriesMore:${s.name}'),
                    count: more,
                    label: l10n.seriesVolumes(more),
                    onTap: () => onExpand?.call(s.name),
                  ),
                ),
              if (long && open && onExpand != null)
                SizedBox(
                  width: cover,
                  height: tileHeight,
                  child: _More(
                    key: ValueKey('webSeriesLess:${s.name}'),
                    count: 0,
                    label: '',
                    onTap: () => onExpand?.call(s.name),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The place of the volumes a folded card does not show: how many, and a
/// tap to show them (or, [count] 0, to fold the card again).
class _More extends StatefulWidget {
  const _More(
      {super.key, required this.count, required this.label, this.onTap});

  final int count;
  final String label;
  final VoidCallback? onTap;

  @override
  State<_More> createState() => _MoreState();
}

class _MoreState extends State<_More> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final folding = widget.count == 0;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 0.7,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                decoration: BoxDecoration(
                  color: scheme.onSurface.withAlpha(_hover ? 22 : 12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: scheme.onSurface.withAlpha(30)),
                ),
                alignment: Alignment.center,
                child: folding
                    ? Icon(Icons.unfold_less_rounded,
                        color: scheme.onSurface.withAlpha(170))
                    : Semantics(
                        label: widget.label,
                        button: true,
                        child: Text('+${widget.count}',
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: scheme.secondary)),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
