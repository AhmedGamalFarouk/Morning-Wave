import 'package:flutter/material.dart';

import 'palette.dart';

/// Fraunces (soft, warm serif) speaks; Atkinson Hyperlegible Next, designed
/// for low vision, explains. Both are OFL and bundled in assets/fonts.
const _voice = 'Fraunces';
const _body = 'AtkinsonHyperlegibleNext';

/// Variable fonts need their axes set explicitly; fontWeight alone is not
/// applied to the wght axis on every Android version.
TextStyle _fraunces(double size, double weight, {double height = 1.15}) {
  return TextStyle(
    fontFamily: _voice,
    fontSize: size,
    height: height,
    letterSpacing: -0.01 * size,
    fontWeight: FontWeight.values[(weight ~/ 100) - 1],
    fontVariations: [
      FontVariation('wght', weight),
      const FontVariation('SOFT', 100),
      const FontVariation('WONK', 0),
      FontVariation('opsz', size.clamp(9, 144).toDouble()),
    ],
    color: Palette.ink,
  );
}

TextStyle _atkinson(double size, double weight, {double height = 1.4}) {
  return TextStyle(
    fontFamily: _body,
    fontSize: size,
    height: height,
    fontWeight: FontWeight.values[(weight ~/ 100) - 1],
    fontVariations: [FontVariation('wght', weight)],
    color: Palette.ink,
  );
}

/// Parent-side minimums from the design language: body 20sp, primary
/// action 28sp. Everything on the parent side uses these roles or larger.
final _textTheme = TextTheme(
  displayMedium: _fraunces(36, 560, height: 1.1),
  headlineMedium: _fraunces(28, 600),
  headlineSmall: _fraunces(24, 560),
  titleLarge: _fraunces(22, 600),
  titleMedium: _atkinson(20, 700),
  bodyLarge: _atkinson(22, 400),
  bodyMedium: _atkinson(20, 400),
  labelLarge: _atkinson(20, 700, height: 1.2),
);

ThemeData buildAppTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: Palette.sun,
        brightness: Brightness.light,
      ).copyWith(
        primary: Palette.sunEdge,
        onPrimary: Palette.ink,
        secondary: Palette.sage,
        onSecondary: Colors.white,
        surface: Palette.paper,
        onSurface: Palette.ink,
        onSurfaceVariant: Palette.inkSoft,
        surfaceContainerLowest: Palette.card,
        surfaceContainerLow: Palette.card,
        surfaceContainer: Palette.paperDeep,
        outline: Palette.peach,
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.paper,
    textTheme: _textTheme,
    splashFactory: InkSparkle.splashFactory,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Palette.ink,
        foregroundColor: Palette.paper,
        disabledBackgroundColor: Palette.paperDeep,
        disabledForegroundColor: Palette.inkSoft,
        minimumSize: const Size(64, 60),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        textStyle: _textTheme.labelLarge,
        shape: const StadiumBorder(),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Palette.ink,
        minimumSize: const Size(64, 56),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: _textTheme.labelLarge,
      ),
    ),
    // Fields sit on the paper like cut-out cards: warm fill, peach edge,
    // and the sun's edge colour while typing.
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: Palette.paper,
      labelStyle: _textTheme.bodyMedium?.copyWith(color: Palette.inkSoft),
      border: _fieldBorder(Palette.peach),
      enabledBorder: _fieldBorder(Palette.peach),
      focusedBorder: _fieldBorder(Palette.sunEdge, width: 2),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Palette.ink,
      contentTextStyle: _textTheme.bodyMedium?.copyWith(color: Palette.paper),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}

OutlineInputBorder _fieldBorder(Color color, {double width = 1}) =>
    OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(16)),
      borderSide: BorderSide(color: color, width: width),
    );

/// The parent side's primary action: 28sp and a tall, easy target.
ButtonStyle parentPrimaryButton(BuildContext context) => FilledButton.styleFrom(
  minimumSize: const Size(64, 72),
  textStyle: Theme.of(context).textTheme.headlineMedium,
);
