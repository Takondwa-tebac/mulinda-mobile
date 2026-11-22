import 'package:flutter/material.dart';

/// WCAG contrast ratio between two colours (1 to 21).
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// A category colour adjusted so a chart slice, bar or swatch drawn in it
/// reaches [minContrast] (3:1, the WCAG figure for graphics) against
/// [surface]. On a light theme the colour is darkened, on a dark theme it is
/// lightened, keeping its hue so "Food" still reads as Food's orange. A colour
/// that already passes is returned unchanged.
///
/// Seeded colours that need it: Food #E67E22, Utilities #F1C40F and grey
/// #9E9E9E on light; Rent #8E44AD on dark.
Color chartTone(Color color, Brightness brightness, {required Color surface, double minContrast = 3}) {
  if (contrastRatio(color, surface) >= minContrast) return color;
  final hsl = HSLColor.fromColor(color);
  final darken = brightness == Brightness.light;
  var lightness = hsl.lightness;
  for (var i = 0; i < 40; i++) {
    lightness = (lightness + (darken ? -0.02 : 0.02)).clamp(0.0, 1.0);
    final candidate = hsl.withLightness(lightness).toColor();
    if (contrastRatio(candidate, surface) >= minContrast) return candidate;
    if (lightness == 0 || lightness == 1) break;
  }
  return hsl.withLightness(lightness).toColor();
}

extension ChartToneX on BuildContext {
  /// [chartTone] against the card surface of the current theme.
  Color chartToneOf(Color color) {
    final theme = Theme.of(this);
    return chartTone(color, theme.brightness, surface: theme.colorScheme.surfaceContainerLow);
  }
}
