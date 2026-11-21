import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// "Couldn't load this" with a retry button. [compact] renders an inline row
/// for use inside a card.
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, this.message, required this.onRetry, this.compact = false});

  final String? message;
  final VoidCallback onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = message ?? 'common.loadError'.tr();
    if (compact) {
      return Row(
        children: [
          Icon(Icons.cloud_off_outlined, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(text, style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(minimumSize: const Size(AppSpacing.minTouch, AppSpacing.minTouch)),
            child: Text('common.retry'.tr()),
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_outlined, size: 40, color: scheme.onSurfaceVariant),
          const SizedBox(height: AppSpacing.md),
          Text(text, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.md),
          FilledButton.tonal(
            onPressed: onRetry,
            style: FilledButton.styleFrom(minimumSize: const Size(140, AppSpacing.minTouch)),
            child: Text('common.retry'.tr()),
          ),
        ],
      ),
    );
  }
}
