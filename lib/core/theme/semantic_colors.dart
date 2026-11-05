import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Colours with a meaning (money in, money out, on track, at risk, over) that
/// Material's [ColorScheme] has no slot for. Registered on both themes; read
/// with `context.semantic`.
@immutable
class SemanticColors extends ThemeExtension<SemanticColors> {
  const SemanticColors({
    required this.income,
    required this.expense,
    required this.success,
    required this.successContainer,
    required this.warning,
    required this.warningContainer,
    required this.danger,
    required this.dangerContainer,
    required this.brandInk,
  });

  /// Money coming in.
  final Color income;

  /// Money going out (kept neutral: spending is normal, not an error).
  final Color expense;

  final Color success;
  final Color successContainer;
  final Color warning;
  final Color warningContainer;
  final Color danger;
  final Color dangerContainer;

  /// Brand teal dark enough to read as text on light surfaces.
  final Color brandInk;

  static const light = SemanticColors(
    income: AppColors.tealInk,
    expense: AppColors.ink,
    success: AppColors.successInk,
    successContainer: Color(0xFFD7F2E4),
    warning: AppColors.warningInk,
    warningContainer: Color(0xFFFFEFC7),
    danger: AppColors.error,
    dangerContainer: Color(0xFFFFDAD6),
    brandInk: AppColors.tealInk,
  );

  static const dark = SemanticColors(
    income: AppColors.teal,
    expense: AppColors.darkInk,
    success: Color(0xFF6FD8A4),
    successContainer: Color(0xFF0F3D28),
    warning: AppColors.orangeLight,
    warningContainer: Color(0xFF4A3300),
    danger: Color(0xFFFFB4AB),
    dangerContainer: Color(0xFF5C1A14),
    brandInk: AppColors.teal,
  );

  @override
  SemanticColors copyWith({
    Color? income,
    Color? expense,
    Color? success,
    Color? successContainer,
    Color? warning,
    Color? warningContainer,
    Color? danger,
    Color? dangerContainer,
    Color? brandInk,
  }) => SemanticColors(
    income: income ?? this.income,
    expense: expense ?? this.expense,
    success: success ?? this.success,
    successContainer: successContainer ?? this.successContainer,
    warning: warning ?? this.warning,
    warningContainer: warningContainer ?? this.warningContainer,
    danger: danger ?? this.danger,
    dangerContainer: dangerContainer ?? this.dangerContainer,
    brandInk: brandInk ?? this.brandInk,
  );

  @override
  SemanticColors lerp(ThemeExtension<SemanticColors>? other, double t) {
    if (other is! SemanticColors) return this;
    return SemanticColors(
      income: Color.lerp(income, other.income, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      success: Color.lerp(success, other.success, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerContainer: Color.lerp(dangerContainer, other.dangerContainer, t)!,
      brandInk: Color.lerp(brandInk, other.brandInk, t)!,
    );
  }
}

extension SemanticColorsX on BuildContext {
  /// The semantic colours of the current theme (falls back to the light/dark
  /// defaults when a bare `ThemeData` without the extension is in use, e.g. tests).
  SemanticColors get semantic {
    final theme = Theme.of(this);
    return theme.extension<SemanticColors>() ??
        (theme.brightness == Brightness.dark ? SemanticColors.dark : SemanticColors.light);
  }
}
