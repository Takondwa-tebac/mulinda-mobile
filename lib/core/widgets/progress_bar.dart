import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/semantic_colors.dart';

/// How a budget (or any limit) is doing; drives its colour.
enum BudgetHealth { onTrack, atRisk, over }

/// A rounded linear progress bar. With [health] set, it takes the budget
/// colour (teal on track, amber at risk, red over).
class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.value, this.health, this.color, this.height = 8, this.semanticsLabel});

  /// 0..1 (values above 1 are drawn full).
  final double value;
  final BudgetHealth? health;
  final Color? color;
  final double height;
  final String? semanticsLabel;

  static Color colorFor(BuildContext context, BudgetHealth health) {
    return switch (health) {
      BudgetHealth.onTrack => Theme.of(context).colorScheme.primary,
      // A fill, not text, so the bright status amber is fine here.
      BudgetHealth.atRisk => AppColors.warning,
      BudgetHealth.over => context.semantic.danger,
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = color ?? (health == null ? scheme.primary : colorFor(context, health!));
    final safe = value.isNaN ? 0.0 : value;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: safe.clamp(0.0, 1.0),
        minHeight: height,
        backgroundColor: scheme.surfaceContainerHigh,
        color: fill,
        semanticsLabel: semanticsLabel,
        // Semantics only accept 0-100%; an over-spent bar reads as full.
        semanticsValue: '${(safe * 100).clamp(0, 100).round()}%',
      ),
    );
  }
}
