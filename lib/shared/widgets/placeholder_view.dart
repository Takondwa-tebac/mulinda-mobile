import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// A simple "coming soon" body used by Phase 0 tab placeholders.
class PlaceholderView extends StatelessWidget {
  const PlaceholderView({super.key, required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: scheme.outline),
          const SizedBox(height: 12),
          Text('common.comingSoon'.tr(),
              style: TextStyle(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
