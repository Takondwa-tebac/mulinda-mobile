import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/semantic_colors.dart';

/// A section title with an optional action ("See all") on the right.
class SectionHeader extends StatelessWidget {
  const SectionHeader(
    this.title, {
    super.key,
    this.actionLabel,
    this.onAction,
    this.trailing,
    this.padding = const EdgeInsets.only(bottom: AppSpacing.sm),
    this.dense = false,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  /// The small, coloured label style used above grouped settings cards.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = dense
        ? theme.textTheme.labelLarge?.copyWith(color: context.semantic.brandInk, fontWeight: FontWeight.w700)
        : theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);
    return Padding(
      padding: dense ? const EdgeInsets.only(left: AppSpacing.xs, bottom: AppSpacing.sm) : padding,
      child: Row(
        children: [
          Expanded(
            child: Semantics(header: true, child: Text(title, style: style)),
          ),
          ?trailing,
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(minimumSize: const Size(AppSpacing.minTouch, AppSpacing.minTouch)),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}
