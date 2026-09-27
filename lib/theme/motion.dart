import 'package:flutter/animation.dart';

/// Motion should feel like sunlight moving through a room: slow, soft, and
/// never bouncy. One place for durations and curves so screens agree.
abstract final class Motion {
  static const breath = Duration(milliseconds: 4800);
  static const raysTurn = Duration(seconds: 150);
  static const press = Duration(milliseconds: 160);
  static const celebrate = Duration(milliseconds: 1600);
  static const crossfade = Duration(milliseconds: 520);

  /// For AnimatedSwitcher: the old words fade out before the new ones fade
  /// in, so two sentences never overlap.
  static const fadeIn = Interval(0.45, 1, curve: Curves.easeOut);
  static const fadeOut = Interval(0.55, 1, curve: Curves.easeIn);

  static const settle = Curves.easeOutCubic;
  static const glow = Curves.easeInOutSine;
}
