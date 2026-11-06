import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// A full-width primary action pinned to the bottom of a screen (e.g.
/// "Contribute" on a goal). Never covers the content above it, unlike a
/// floating button, and is easy to reach with a thumb.
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({super.key, required this.label, required this.onPressed, this.icon});

  final Widget label;
  final Widget? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
          child: icon == null
              ? FilledButton(key: const ValueKey('bottom-action'), onPressed: onPressed, child: label)
              : FilledButton.icon(
                  key: const ValueKey('bottom-action'),
                  onPressed: onPressed,
                  icon: icon!,
                  label: label,
                ),
        ),
      ),
    );
  }
}
