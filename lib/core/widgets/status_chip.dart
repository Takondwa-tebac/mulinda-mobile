import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/semantic_colors.dart';

/// What a status chip means; sets its colours.
enum StatusTone { neutral, brand, success, warning, danger }

/// A small rounded label: "On track", "Over", "Confirm category"…
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, this.tone = StatusTone.neutral, this.icon, this.onTap});

  final String label;
  final StatusTone tone;
  final IconData? icon;
  final VoidCallback? onTap;

  static (Color fg, Color bg) colorsFor(BuildContext context, StatusTone tone) {
    final scheme = Theme.of(context).colorScheme;
    final s = context.semantic;
    return switch (tone) {
      StatusTone.neutral => (scheme.onSurfaceVariant, scheme.surfaceContainerHigh),
      StatusTone.brand => (s.brandInk, scheme.primaryContainer),
      StatusTone.success => (s.success, s.successContainer),
      StatusTone.warning => (s.warning, s.warningContainer),
      StatusTone.danger => (s.danger, s.dangerContainer),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = colorsFor(context, tone);
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.chip),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: AppSpacing.xs)],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return chip;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.chip,
        // A taller hit area than the chip itself, so it is easy to tap.
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: chip,
        ),
      ),
    );
  }
}
