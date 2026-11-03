import 'dart:math' as math;

import 'package:flutter/material.dart';

// The HOLA Circle look: a ring of electric-blue light on a night sky, with a
// brighter glint that travels slowly round it and a second swoosh of light.

/// Paints a glowing ring. [phase] (0–1) turns the bright glint round the
/// ring; [progress] (0–1) draws the ring in, for the splash.
class GlowRingPainter extends CustomPainter {
  final Alignment center;

  /// Ring radius as a share of the canvas width.
  final double scale;
  final Color color;
  final double phase, progress, intensity;
  final bool swoosh, sky;

  const GlowRingPainter({
    this.center = const Alignment(.55, -.2),
    this.scale = .62,
    this.color = const Color(0xFF2F80FF),
    this.phase = 0,
    this.progress = 1,
    this.intensity = 1,
    this.swoosh = true,
    this.sky = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (sky) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF000000), Color(0xFF020814), Color(0xFF041230)],
            stops: [0, .55, 1],
          ).createShader(rect),
      );
    }
    if (progress <= 0 || intensity <= 0) return;
    final c = center.alongSize(size);
    final r = size.width * scale;
    final k = intensity;
    final turn = phase * 2 * math.pi;
    final sweep = 2 * math.pi * progress.clamp(0.0, 1.0);
    final start = -math.pi / 2 + turn * .25;
    final ring = Rect.fromCircle(center: c, radius: r);

    // Light pooling just inside the rim (the poster's lit edge).
    canvas.drawCircle(
      c,
      r * 1.08,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: 0),
            color.withValues(alpha: 0),
            color.withValues(alpha: .16 * k * progress),
            color.withValues(alpha: 0),
          ],
          stops: const [0, .72, .9, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r * 1.08)),
    );

    // Brightness varies round the ring; the glint moves with [phase].
    Shader sweepShader(double a) => SweepGradient(
      transform: GradientRotation(turn),
      colors: [
        color.withValues(alpha: .25 * a),
        color.withValues(alpha: a),
        const Color(0xFFBFE0FF).withValues(alpha: a),
        color.withValues(alpha: .55 * a),
        color.withValues(alpha: .2 * a),
        color.withValues(alpha: .7 * a),
        color.withValues(alpha: .25 * a),
      ],
      stops: const [0, .12, .2, .32, .55, .8, 1],
    ).createShader(ring);

    // Wide soft halo, then a tighter glow, then the bright core line.
    canvas.drawArc(
      ring,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * .16
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * .09)
        ..shader = sweepShader(.45 * k),
    );
    canvas.drawArc(
      ring,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5)
        ..shader = sweepShader(.9 * k),
    );
    canvas.drawArc(
      ring,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..shader = sweepShader(k),
    );

    // A second, wider swoosh of light crossing the lower side.
    if (swoosh) {
      final s = Rect.fromCircle(center: c.translate(-r * .18, r * .1), radius: r * 1.22);
      final from = math.pi * .05 + turn * .1, len = math.pi * .55 * progress;
      for (final (w, blur, a) in [(r * .1, r * .06, .28), (3.0, 3.0, .7), (1.0, 0.0, .9)]) {
        canvas.drawArc(
          s,
          from,
          len,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = w
            ..maskFilter = blur > 0 ? MaskFilter.blur(BlurStyle.normal, blur) : null
            ..shader = SweepGradient(
              transform: GradientRotation(from),
              colors: [
                color.withValues(alpha: 0),
                color.withValues(alpha: a * k),
                const Color(0xFFBFE0FF).withValues(alpha: a * k),
                color.withValues(alpha: 0),
              ],
              stops: const [0, .08, .12, .16],
            ).createShader(s),
        );
      }
    }
  }

  @override
  bool shouldRepaint(GlowRingPainter o) =>
      o.phase != phase || o.progress != progress || o.intensity != intensity || o.color != color || o.center != center || o.scale != scale || o.sky != sky || o.swoosh != swoosh;
}

/// Night sky with a slowly turning glowing ring. Used behind headers and pages.
class GlowSky extends StatefulWidget {
  final Alignment center;
  final double scale, intensity;
  final Color color;
  final bool sky, swoosh;
  final Widget? child;
  const GlowSky({super.key, this.center = const Alignment(.55, -.2), this.scale = .62, this.intensity = 1, this.color = const Color(0xFF2F80FF), this.sky = true, this.swoosh = true, this.child});
  @override
  State<GlowSky> createState() => _GlowSkyState();
}

class _GlowSkyState extends State<GlowSky> with SingleTickerProviderStateMixin {
  // One slow turn every 24 s: alive, never busy.
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 24));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: AnimatedBuilder(
      animation: _c,
      builder: (_, child) => CustomPaint(
        painter: GlowRingPainter(center: widget.center, scale: widget.scale, color: widget.color, phase: _c.value, intensity: widget.intensity, sky: widget.sky, swoosh: widget.swoosh),
        child: child,
      ),
      child: widget.child ?? const SizedBox.expand(),
    ),
  );
}
