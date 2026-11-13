// Le widget qui fait vivre un BotEngine : un ticker, un CustomPaint, le halo.

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/layout.dart';
import 'bot_engine.dart';

class MochiView extends StatefulWidget {
  const MochiView({
    super.key,
    required this.engine,
    required this.size,
    this.glow = true,
    this.glowColor,
    this.glowOpacity,
  });

  final BotEngine engine;
  final double size;
  final bool glow;
  final Color? glowColor;
  final double? glowOpacity;

  @override
  State<MochiView> createState() => _MochiViewState();
}

class _MochiViewState extends State<MochiView> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration elapsed) {
    var dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt <= 0 || dt > 0.1) dt = 1 / 60;
    widget.engine.update(dt);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final glowColor = widget.glowColor ?? botGlowColor(widget.engine.state);
    final glowOpacity = widget.glowOpacity ?? botGlowOpacity(widget.engine.state);
    return SizedBox(
      width: s,
      height: s,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (widget.glow)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: widget.engine,
                builder: (_, __) => Padding(
                  padding: EdgeInsets.all(s * 0.04),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          glowColor.withValues(alpha: glowOpacity),
                          glowColor.withValues(alpha: 0),
                        ],
                        stops: const [0, 0.62],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: CustomPaint(painter: _BotPainter(widget.engine)),
          ),
        ],
      ),
    );
  }
}

class _BotPainter extends CustomPainter {
  _BotPainter(this.engine) : super(repaint: engine);
  final BotEngine engine;

  @override
  void paint(Canvas canvas, Size size) {
    engine.draw(canvas, size.width, size.height);
  }

  @override
  bool shouldRepaint(covariant _BotPainter oldDelegate) => true;
}
