import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/motion.dart';
import '../theme/palette.dart';
import 'sun_painter.dart';

/// The parent's one action: tap the sun to say good morning.
///
/// It breathes while it waits, sinks a little under the finger, and on tap
/// swells, stretches its rays and lets a few motes of light and small
/// hearts drift up before it settles. With system animations off it simply
/// changes state.
class MorningSun extends StatefulWidget {
  const MorningSun({
    super.key,
    required this.label,
    required this.semanticLabel,
    this.onPressed,
    this.warmth = 1,
  });

  /// Words inside the sun, 28sp or larger.
  final String label;
  final String semanticLabel;

  /// Null makes the sun rest: it still glows but no longer takes taps.
  final VoidCallback? onPressed;
  final double warmth;

  @override
  State<MorningSun> createState() => _MorningSunState();
}

class _MorningSunState extends State<MorningSun> with TickerProviderStateMixin {
  late final _breath = AnimationController(
    vsync: this,
    duration: Motion.breath,
  );
  late final _turn = AnimationController(
    vsync: this,
    duration: Motion.raysTurn,
  );
  late final _press = AnimationController(vsync: this, duration: Motion.press);
  late final _celebrate = AnimationController(
    vsync: this,
    duration: Motion.celebrate,
  );

  bool _calm = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _calm = MediaQuery.disableAnimationsOf(context);
    if (_calm) {
      _breath.stop();
      _turn.stop();
    } else {
      if (!_breath.isAnimating) _breath.repeat(reverse: true);
      if (!_turn.isAnimating) _turn.repeat();
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    _turn.dispose();
    _press.dispose();
    _celebrate.dispose();
    super.dispose();
  }

  bool get _enabled => widget.onPressed != null;

  void _handleTap() {
    if (!_enabled) return;
    HapticFeedback.mediumImpact();
    if (!_calm) _celebrate.forward(from: 0);
    widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.headlineMedium!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(constraints.maxWidth * 0.9, 340.0);
        return Semantics(
          button: _enabled,
          label: widget.semanticLabel,
          excludeSemantics: true,
          onTap: _enabled ? _handleTap : null,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: _enabled ? (_) => _press.forward() : null,
            onTapUp: _enabled ? (_) => _press.reverse() : null,
            onTapCancel: _enabled ? _press.reverse : null,
            onTap: _handleTap,
            child: AnimatedBuilder(
              animation: Listenable.merge([_breath, _turn, _press, _celebrate]),
              builder: (context, _) {
                final bloom = _bloom(_celebrate.value);
                final scale =
                    (1 - 0.05 * Motion.settle.transform(_press.value)) *
                    (1 + 0.1 * bloom);
                return SizedBox.square(
                  dimension: side,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Transform.scale(
                        scale: scale,
                        child: CustomPaint(
                          size: Size.square(side),
                          painter: SunPainter(
                            breath: Motion.glow.transform(_breath.value),
                            turn: _turn.value,
                            rayReach: 1 + 0.75 * bloom,
                            warmth: widget.warmth,
                          ),
                        ),
                      ),
                      if (_celebrate.isAnimating)
                        CustomPaint(
                          size: Size.square(side),
                          painter: _LightMotesPainter(_celebrate.value),
                        ),
                      SizedBox(
                        width: side * 0.5,
                        child: AnimatedSwitcher(
                          duration: Motion.crossfade,
                          switchInCurve: Motion.fadeIn,
                          switchOutCurve: Motion.fadeOut,
                          child: Text(
                            widget.label,
                            key: ValueKey(widget.label),
                            textAlign: TextAlign.center,
                            style: textStyle.copyWith(height: 1.08),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// Rises quickly, then eases back to rest: a single warm swell.
  static double _bloom(double t) {
    if (t == 0 || t == 1) return 0;
    const peak = 0.3;
    return t < peak
        ? Motion.settle.transform(t / peak)
        : 1 - Motion.glow.transform((t - peak) / (1 - peak));
  }
}

/// A handful of light motes and small hearts drifting up from the sun.
/// Positions are fixed per mote so the moment looks the same every morning.
class _LightMotesPainter extends CustomPainter {
  const _LightMotesPainter(this.t);

  final double t;

  static final _motes = List.generate(16, (i) {
    final random = math.Random(i * 7 + 3);
    return (
      angle: -math.pi / 2 + (random.nextDouble() - 0.5) * math.pi * 1.5,
      travel: 0.18 + random.nextDouble() * 0.2,
      size: 5 + random.nextDouble() * 7,
      delay: random.nextDouble() * 0.25,
      heart: i % 4 == 0,
    );
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final start = size.shortestSide * 0.3;

    for (final mote in _motes) {
      final local = ((t - mote.delay) / (1 - mote.delay)).clamp(0.0, 1.0);
      if (local == 0) continue;
      final eased = Motion.settle.transform(local);
      final distance = start + size.shortestSide * mote.travel * eased;
      final position =
          center +
          Offset(math.cos(mote.angle), math.sin(mote.angle)) * distance -
          Offset(0, 18 * eased);
      final alpha = math.sin(math.pi * local) * 0.9;

      if (mote.heart) {
        canvas.drawPath(
          heartPath(position, mote.size * 1.8),
          Paint()..color = Palette.sunEdge.withValues(alpha: alpha),
        );
      } else {
        canvas.drawCircle(
          position,
          mote.size / 2,
          Paint()
            ..color = Palette.sunCore.withValues(alpha: alpha)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_LightMotesPainter old) => old.t != t;
}
