import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Builds Mulinda's light and dark Material 3 themes from the brand palette.
abstract class AppTheme {
  static const _radius = 16.0;

  static ThemeData get light => _build(_lightScheme, Brightness.light);
  static ThemeData get dark => _build(_darkScheme, Brightness.dark);

  static const _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.teal,
    onPrimary: AppColors.onTeal,
    primaryContainer: AppColors.tealPale,
    onPrimaryContainer: AppColors.onTealPale,
    secondary: AppColors.orange,
    onSecondary: AppColors.onOrange,
    secondaryContainer: AppColors.orangeLight,
    onSecondaryContainer: AppColors.onOrangeLight,
    tertiary: AppColors.teal,
    onTertiary: AppColors.onTeal,
    error: AppColors.error,
    onError: AppColors.onError,
    surface: AppColors.white,
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.inkVariant,
    surfaceContainerLowest: AppColors.white,
    surfaceContainerLow: AppColors.surfaceLow,
    surfaceContainer: AppColors.surfaceContainer,
    surfaceContainerHigh: AppColors.surfaceHigh,
    outline: AppColors.outline,
    outlineVariant: AppColors.outlineVariant,
  );

  static const _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.teal,
    onPrimary: AppColors.onTeal,
    primaryContainer: AppColors.onTealPale,
    onPrimaryContainer: AppColors.tealPale,
    secondary: AppColors.orangeLight,
    onSecondary: AppColors.onOrangeLight,
    secondaryContainer: Color(0xFF7A4F00),
    onSecondaryContainer: AppColors.orangeLight,
    tertiary: AppColors.tealPale,
    onTertiary: AppColors.onTealPale,
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    surface: AppColors.darkSurface,
    onSurface: AppColors.darkInk,
    onSurfaceVariant: AppColors.darkInkVariant,
    surfaceContainerLowest: Color(0xFF0D0F0E),
    surfaceContainerLow: AppColors.darkSurfaceContainer,
    surfaceContainer: AppColors.darkSurfaceContainer,
    surfaceContainerHigh: AppColors.darkSurfaceHigh,
    outline: AppColors.outline,
    outlineVariant: Color(0xFF3C4947),
  );

  static ThemeData _build(ColorScheme scheme, Brightness brightness) {
    final base = ThemeData(brightness: brightness, useMaterial3: true);

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.secondary,
        foregroundColor: scheme.onSecondary,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
