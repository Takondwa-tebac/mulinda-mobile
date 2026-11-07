import 'package:flutter/widgets.dart';

/// Spacing scale (4-pt grid). Use these instead of ad-hoc numbers so screens
/// line up with each other.
abstract class AppSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  /// Side padding of a scrolling screen body.
  static const double screen = lg;

  /// Room left under a list so the floating capture button never covers the
  /// last row.
  static const double fabClearance = 96;

  /// The minimum size of anything tappable (Material / WCAG target size).
  static const double minTouch = 48;

  static const gapXs = SizedBox(width: xs, height: xs);
  static const gapSm = SizedBox(width: sm, height: sm);
  static const gapMd = SizedBox(width: md, height: md);
  static const gapLg = SizedBox(width: lg, height: lg);
  static const gapXl = SizedBox(width: xl, height: xl);

  static const screenPadding = EdgeInsets.fromLTRB(screen, sm, screen, fabClearance);
}

/// Corner radii. The brand radius is 16.
abstract class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double pill = 999;

  static final card = BorderRadius.circular(lg);
  static final chip = BorderRadius.circular(pill);
}
