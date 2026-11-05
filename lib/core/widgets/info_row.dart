import 'package:flutter/material.dart';

/// A label on the left, a value on the right (detail screens).
class InfoRow extends StatelessWidget {
  const InfoRow({super.key, this.icon, required this.label, required this.value, this.valueColor});

  final IconData? icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: icon == null ? null : Icon(icon, size: 20, color: scheme.onSurfaceVariant),
      title: Text(label, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
      trailing: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.5),
        child: Text(
          value,
          textAlign: TextAlign.end,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: FontWeight.w600, color: valueColor),
        ),
      ),
    );
  }
}
