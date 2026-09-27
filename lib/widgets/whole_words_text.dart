import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Text that grows with the system text size but never breaks a word
/// across lines. It stops growing at 1.5x, and shrinks further only when
/// its longest word would not fit the width it is given. Used for titles
/// and button labels, which start large already.
class WholeWordsText extends StatelessWidget {
  const WholeWordsText(this.text, {super.key, this.style, this.textAlign});

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  static const maxScale = 1.5;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final style = DefaultTextStyle.of(context).style.merge(this.style);
        final fontSize = style.fontSize ?? 14;
        final clamped = MediaQuery.textScalerOf(context)
            .clamp(maxScaleFactor: maxScale);
        var scale = clamped.scale(fontSize) / fontSize;

        final longest = _longestWordWidth(context, style, scale);
        if (constraints.hasBoundedWidth && longest > constraints.maxWidth) {
          scale *= constraints.maxWidth / longest;
        }

        return MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(math.max(scale, 1))),
          child: Text(text, style: this.style, textAlign: textAlign),
        );
      },
    );
  }

  double _longestWordWidth(
    BuildContext context,
    TextStyle style,
    double scale,
  ) {
    var widest = 0.0;
    for (final word in text.split(RegExp(r'\s+'))) {
      final painter = TextPainter(
        text: TextSpan(text: word, style: style),
        textDirection: Directionality.of(context),
        textScaler: TextScaler.linear(scale),
      )..layout();
      widest = math.max(widest, painter.width);
      painter.dispose();
    }
    return widest;
  }
}
