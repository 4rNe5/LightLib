// A one-line label that slowly scrolls when its text does not fit, like
// the title bars in webtoon and music apps.

// Flutter imports:
import 'package:flutter/material.dart';

class MarqueeText extends StatefulWidget {
  const MarqueeText(
    this.text, {
    super.key,
    this.style,
    this.gap = 32,
    this.velocity = 30,
    this.pause = const Duration(milliseconds: 1800),
  });

  final String text;
  final TextStyle? style;

  /// Space between the end of the text and its next repetition.
  final double gap;

  /// Scroll speed in logical pixels per second.
  final double velocity;

  /// Rest at the start of every loop, so the title can be read.
  final Duration pause;

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  Duration? _period;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _run(Duration period) {
    if (_period == period && _controller.isAnimating) return;
    _period = period;
    _controller.repeat(period: period);
  }

  void _stop() {
    if (_controller.isAnimating) _controller.stop();
    _controller.value = 0;
    _period = null;
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return LayoutBuilder(builder: (context, constraints) {
      final painter = TextPainter(
        text: TextSpan(text: widget.text, style: style),
        maxLines: 1,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final width = painter.width;
      final height = painter.height;
      painter.dispose();

      final fits = width <= constraints.maxWidth;
      if (fits || still || !constraints.hasBoundedWidth) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _stop();
        });
        return Text(widget.text,
            style: style,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis);
      }

      final travel = width + widget.gap;
      final scroll =
          Duration(milliseconds: (travel / widget.velocity * 1000).round());
      final period = scroll + widget.pause;
      final pauseShare = widget.pause.inMilliseconds / period.inMilliseconds;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _run(period);
      });

      return SizedBox(
        height: height,
        width: constraints.maxWidth,
        child: ShaderMask(
          shaderCallback: (rect) => const LinearGradient(
            colors: [Colors.black, Colors.black, Colors.transparent],
            stops: [0, 0.86, 1],
          ).createShader(rect),
          blendMode: BlendMode.dstIn,
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final t = _controller.value;
                final progress =
                    t < pauseShare ? 0.0 : (t - pauseShare) / (1 - pauseShare);
                return Transform.translate(
                  offset: Offset(-travel * Curves.linear.transform(progress), 0),
                  child: child,
                );
              },
              child: OverflowBox(
                alignment: AlignmentDirectional.centerStart,
                maxWidth: double.infinity,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.text, style: style, maxLines: 1),
                    SizedBox(width: widget.gap),
                    Text(widget.text, style: style, maxLines: 1),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}
