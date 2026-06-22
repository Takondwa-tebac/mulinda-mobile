import 'package:flutter/material.dart';

/// Mulinda brand palette.
///
/// Source palette: #ff9f1c, #ffbf69, #ffffff, #cbf3f0, #2ec4b6.
/// On-colors are derived for accessible contrast (dark text on the bright
/// teal/orange brand colors).
abstract class AppColors {
  // Brand
  static const teal = Color(0xFF2EC4B6); // primary
  static const tealPale = Color(0xFFCBF3F0); // primary container
  static const orange = Color(0xFFFF9F1C); // secondary / CTA / FAB
  static const orangeLight = Color(0xFFFFBF69); // secondary container
  static const white = Color(0xFFFFFFFF);

  // Derived on-colors (dark, for contrast on bright brand colors)
  static const onTeal = Color(0xFF00332E);
  static const onTealPale = Color(0xFF00504A);
  static const onOrange = Color(0xFF3D2600);
  static const onOrangeLight = Color(0xFF4A2E00);

  // Neutrals (light)
  static const ink = Color(0xFF1C1B1B);
  static const inkVariant = Color(0xFF3C4947);
  static const outline = Color(0xFF6C7A77);
  static const outlineVariant = Color(0xFFBBCAC6);
  static const surfaceLow = Color(0xFFF6F3F2);
  static const surfaceContainer = Color(0xFFF0EDED);
  static const surfaceHigh = Color(0xFFE5E2E1);

  // Neutrals (dark)
  static const darkSurface = Color(0xFF121413);
  static const darkSurfaceContainer = Color(0xFF1E211F);
  static const darkSurfaceHigh = Color(0xFF2A2E2C);
  static const darkInk = Color(0xFFE5E2E1);
  static const darkInkVariant = Color(0xFFBBCAC6);

  // Status
  static const error = Color(0xFFBA1A1A);
  static const onError = Color(0xFFFFFFFF);
  static const success = Color(0xFF0A8754);
  static const warning = Color(0xFFE8A317);
}
