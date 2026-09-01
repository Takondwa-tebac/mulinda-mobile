import 'package:flutter/material.dart';

/// One label : value line in a receipt.
class ReceiptRow {
  const ReceiptRow(this.label, this.value, {this.emphasize = false, this.muted = false});

  final String label;
  final String value;
  final bool emphasize; // larger/bolder value (e.g. amount)
  final bool muted; // secondary line (e.g. fee/levy)
}

/// A polished, share-ready receipt card in the style of a bank payment
/// confirmation: brand header, a status check, a headline amount, and a clean
/// list of label : value rows. Theme-aware (renders in light and dark).
///
/// Used for the transaction detail/receipt and the subscription payment receipt.
class ReceiptView extends StatelessWidget {
  const ReceiptView({
    super.key,
    required this.title,
    required this.rows,
    this.subtitle,
    this.amountLine,
    this.amountColor,
    this.statusIcon = Icons.check_circle,
    this.statusColor,
    this.detailsHeading = 'Details',
    this.footer = 'Thank you for using Mulinda',
    this.logoAsset = 'assets/logo.png',
  });

  final String title;
  final String? subtitle;
  final String? amountLine;
  final Color? amountColor;
  final IconData statusIcon;
  final Color? statusColor;
  final String detailsHeading;
  final List<ReceiptRow> rows;
  final String footer;
  final String logoAsset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final status = statusColor ?? scheme.primary;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Brand
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(logoAsset, width: 26, height: 26,
                  errorBuilder: (_, _, _) => const SizedBox(width: 26, height: 26)),
              const SizedBox(width: 8),
              Text('Mulinda',
                  style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 22),

          // Status check
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: status.withValues(alpha: 0.12),
              border: Border.all(color: status, width: 2),
            ),
            child: Icon(statusIcon, color: status, size: 40),
          ),
          const SizedBox(height: 16),

          Text(title,
              textAlign: TextAlign.center,
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(subtitle!,
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          ],

          if (amountLine != null) ...[
            const SizedBox(height: 18),
            Text(amountLine!,
                style: text.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800, color: amountColor ?? scheme.onSurface)),
          ],

          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(detailsHeading,
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),

          ...rows.map((r) => _RowLine(row: r)),

          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 14),
          Text(footer,
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _RowLine extends StatelessWidget {
  const _RowLine({required this.row});
  final ReceiptRow row;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(row.label,
                style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600)),
          ),
          Text(':  ', style: TextStyle(color: scheme.onSurfaceVariant)),
          Expanded(
            child: Text(
              row.value,
              style: (row.emphasize ? text.titleMedium : text.bodyMedium)?.copyWith(
                fontWeight: row.emphasize ? FontWeight.w800 : FontWeight.w600,
                color: row.muted ? scheme.onSurfaceVariant : scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
