import 'package:flutter/material.dart';

import '../theme/palette.dart';

/// A card that sits on the paper like a note on a table: warm fill, soft
/// warm shadow, no border. Replaces Material's Card on every screen.
class PaperCard extends StatelessWidget {
  const PaperCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.color = Palette.card,
    this.gradient,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Gradient? gradient;

  static const radius = BorderRadius.all(Radius.circular(22));

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: gradient == null ? color : null,
        gradient: gradient,
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Palette.shadow.withValues(alpha: 0.09),
            offset: const Offset(0, 10),
            blurRadius: 28,
          ),
          BoxShadow(
            color: Palette.shadow.withValues(alpha: 0.05),
            offset: const Offset(0, 1),
            blurRadius: 3,
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
