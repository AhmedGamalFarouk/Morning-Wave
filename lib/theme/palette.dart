import 'package:flutter/material.dart';

/// The sunrise palette from docs/design-language.md: cream paper, soft
/// peach, muted sun yellow, gentle sky and a warm green. Nothing saturated.
abstract final class Palette {
  // Surfaces: warm paper, never white.
  static const paper = Color(0xFFFBF3E6);
  static const paperDeep = Color(0xFFF5E6D0);
  static const card = Color(0xFFFFFAF2);

  // Ink: warm brown instead of black, so type feels written, not printed.
  static const ink = Color(0xFF3A281D);
  static const inkSoft = Color(0xFF6B5244);

  // The sun, from its core outwards.
  static const sunCore = Color(0xFFFFD77A);
  static const sun = Color(0xFFF6B94B);
  static const sunEdge = Color(0xFFEE9A4D);
  static const glow = Color(0xFFFBD3A6);

  // Accents.
  static const peach = Color(0xFFF4C7AE);
  static const sky = Color(0xFFCFE0EA);
  static const sage = Color(0xFF7E9F83);
  static const sageDeep = Color(0xFF4F6E55);

  /// Warm shadow tint: brown-orange, never grey.
  static const shadow = Color(0xFF8A5A2B);
}
