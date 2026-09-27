import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/palette.dart';

/// Paints the Morning Wave sun: a warm glow, soft tapered rays and a round
/// core lit from the upper left. Shared by the parent's Morning Sun and the
/// small suns on the child side.
class SunPainter extends CustomPainter {
  const SunPainter({
    this.breath = 0,
    this.turn = 0,
    this.rayReach = 1,
    this.warmth = 1,
  });

  /// 0..1, the slow inhale and exhale of the glow.
  final double breath;

  /// 0..1, one full turn of the rays.
  final double turn;

  /// Ray length multiplier; the celebration pushes it past 1.
  final double rayReach;

  /// 1 is full morning light, lower values rest the sun (away mode).
  final double warmth;

  static const rayCount = 12;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final core = size.shortestSide * 0.31;

    _paintGlow(canvas, center, core);
    _paintRays(canvas, center, core);
    _paintCore(canvas, center, core);
  }

  void _paintGlow(Canvas canvas, Offset center, double core) {
    final radius = core * (1.55 + 0.1 * breath) * (0.85 + 0.15 * warmth);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          Palette.glow.withValues(alpha: 0.85 * warmth),
          Palette.glow.withValues(alpha: 0.35 * warmth),
          Palette.glow.withValues(alpha: 0),
        ],
        stops: const [0.45, 0.72, 1],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);
  }

  void _paintRays(Canvas canvas, Offset center, double core) {
    final inner = core * 1.16;
    final length = core * (0.22 + 0.04 * breath) * rayReach;
    final paint = Paint()
      ..color = Color.lerp(
        Palette.sun,
        Palette.sunEdge,
        0.3,
      )!.withValues(alpha: 0.5 * warmth)
      ..strokeWidth = core * 0.075
      ..strokeCap = StrokeCap.round;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(turn * 2 * math.pi);
    for (var i = 0; i < rayCount; i++) {
      // Alternate long and short rays, like light through a window.
      final reach = i.isEven ? length : length * 0.6;
      canvas.drawLine(Offset(0, -inner), Offset(0, -inner - reach), paint);
      canvas.rotate(2 * math.pi / rayCount);
    }
    canvas.restore();
  }

  void _paintCore(Canvas canvas, Offset center, double core) {
    final rect = Rect.fromCircle(center: center, radius: core);

    // Soft warm shadow under the sun so it sits on the paper.
    canvas.drawCircle(
      center.translate(0, core * 0.10),
      core,
      Paint()
        ..color = Palette.shadow.withValues(alpha: 0.18 * warmth)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, core * 0.16),
    );

    final restful = Color.lerp(Palette.paperDeep, Palette.sun, warmth)!;
    canvas.drawCircle(
      center,
      core,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          radius: 1.05,
          colors: [
            Color.lerp(Palette.paper, Palette.sunCore, warmth)!,
            restful,
            Color.lerp(Palette.peach, Palette.sunEdge, warmth)!,
          ],
          stops: const [0, 0.55, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(SunPainter old) =>
      old.breath != breath ||
      old.turn != turn ||
      old.rayReach != rayReach ||
      old.warmth != warmth;
}

/// A rounded heart, drawn rather than typed, so it renders the same on
/// every phone. [size] is the heart's width.
Path heartPath(Offset center, double size) {
  final w = size;
  final h = size * 0.9;
  final left = center.dx - w / 2;
  final top = center.dy - h / 2;
  return Path()
    ..moveTo(center.dx, top + h * 0.28)
    ..cubicTo(
      left + w * 0.42,
      top - h * 0.06,
      left - w * 0.06,
      top + h * 0.2,
      left + w * 0.06,
      top + h * 0.46,
    )
    ..cubicTo(
      left + w * 0.16,
      top + h * 0.66,
      center.dx - w * 0.14,
      top + h * 0.82,
      center.dx,
      top + h,
    )
    ..cubicTo(
      center.dx + w * 0.14,
      top + h * 0.82,
      left + w * 0.84,
      top + h * 0.66,
      left + w * 0.94,
      top + h * 0.46,
    )
    ..cubicTo(
      left + w * 1.06,
      top + h * 0.2,
      left + w * 0.58,
      top - h * 0.06,
      center.dx,
      top + h * 0.28,
    )
    ..close();
}

/// A small, still sun for headings and the child's hero card.
class SunMark extends StatelessWidget {
  const SunMark({super.key, this.size = 56, this.warmth = 1});

  final double size;
  final double warmth;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: SunPainter(breath: 0.5, turn: 0.02, warmth: warmth),
      ),
    );
  }
}

/// A small drawn heart in the sunrise peach.
class HeartMark extends StatelessWidget {
  const HeartMark({super.key, this.color = Palette.sunEdge});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(
        size: const Size.square(22),
        painter: _HeartPainter(color),
      ),
    );
  }
}

class _HeartPainter extends CustomPainter {
  const _HeartPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      heartPath(size.center(Offset.zero), size.width * 0.92),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_HeartPainter old) => old.color != color;
}
