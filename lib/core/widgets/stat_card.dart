import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// A small figure tile: icon, value and label. Tappable when [onTap] is set.
/// Replaces the per-screen `_Stat`, `_StatTile`, `_Indicator` and `_Card`.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.caption,
    this.captionColor,
    this.onTap,
    this.valueColor,
    this.accent,
    this.highlight = false,
    this.centered = false,
  });

  final IconData icon;
  final String label;
  final String value;

  /// A short line under the value (a grade, a band…).
  final String? caption;
  final Color? captionColor;
  final VoidCallback? onTap;
  final Color? valueColor;

  /// Icon colour (defaults to the primary colour).
  final Color? accent;

  /// Draws an outline in [accent] to draw the eye (e.g. a budget is over).
  final bool highlight;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = accent ?? scheme.primary;
    final align = centered ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    final textAlign = centered ? TextAlign.center : null;
    final content = Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: AppSpacing.minTouch),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppRadius.card,
        border: highlight ? Border.all(color: tint, width: 1.5) : null,
      ),
      child: Column(
        crossAxisAlignment: align,
        children: [
          ExcludeSemantics(child: Icon(icon, size: 20, color: tint)),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: textAlign,
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: valueColor),
          ),
          if (caption != null)
            Text(
              caption!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: textAlign,
              style: TextStyle(fontSize: 11, color: captionColor ?? scheme.onSurfaceVariant),
            ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: textAlign,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
    if (onTap == null) return content;
    return Semantics(
      button: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(onTap: onTap, borderRadius: AppRadius.card, child: content),
      ),
    );
  }
}
