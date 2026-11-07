import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// A friendly "nothing here yet" block: icon, title, optional body and up to
/// two calls to action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  /// Less vertical room, for use inside a card or list.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: compact ? AppSpacing.lg : AppSpacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Container(
              width: compact ? 56 : 72,
              height: compact ? 56 : 72,
              decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
              child: Icon(icon, size: compact ? 28 : 36, color: scheme.onPrimaryContainer),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (body != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              body!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: onAction,
              style: FilledButton.styleFrom(minimumSize: const Size(160, AppSpacing.minTouch)),
              child: Text(actionLabel!),
            ),
          ],
          if (secondaryLabel != null && onSecondary != null) ...[
            const SizedBox(height: AppSpacing.xs),
            TextButton(
              onPressed: onSecondary,
              style: TextButton.styleFrom(minimumSize: const Size(AppSpacing.minTouch, AppSpacing.minTouch)),
              child: Text(secondaryLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

/// Puts [child] in the middle of a scrollable area that fills most of the
/// screen, so pull-to-refresh still works around loading/empty/error states.
/// Replaces the per-screen `_Fill` / `_CenterBox` helpers.
class ScrollFill extends StatelessWidget {
  const ScrollFill({super.key, required this.child, this.heightFactor = 0.6});

  final Widget child;
  final double heightFactor;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: MediaQuery.sizeOf(context).height * heightFactor),
          child: Center(child: child),
        ),
      ],
    );
  }
}
