import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// One money record (a goal contribution, a loan repayment…), laid out so long
/// amounts never wrap: the amount takes the flexible space and scales down if it
/// still does not fit, and the actions collapse into one overflow menu instead of
/// fixed-width buttons.
class AmountRecordCard extends StatelessWidget {
  const AmountRecordCard({
    super.key,
    required this.amount,
    required this.onEdit,
    required this.onDelete,
    this.rawDate,
    this.note,
    this.pending = false,
    this.icon = Icons.savings_outlined,
  });

  /// The formatted amount, e.g. `MK 12,500.00`.
  final String amount;

  /// An ISO date (`2026-10-06`) shown as `6 Oct 2026`.
  final String? rawDate;
  final String? note;

  /// Made offline and not synced yet.
  final bool pending;
  final IconData icon;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String? get _date {
    final raw = rawDate;
    if (raw == null || raw.isEmpty) return null;
    final d = DateTime.tryParse(raw);
    final text = d == null ? raw : '${d.day} ${_months[d.month - 1]} ${d.year}';
    return pending ? '$text \u00b7 Waiting to sync' : text;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final trimmedNote = note?.trim();
    final hasNote = trimmedNote != null && trimmedNote.isNotEmpty;
    final date = _date ?? (pending ? 'Waiting to sync' : null);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    amount,
                    maxLines: 1,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                  ),
                ),
                if (date != null) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        pending ? Icons.cloud_upload_outlined : Icons.event_outlined,
                        size: 13,
                        color: pending ? scheme.tertiary : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          date,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
                if (hasNote) ...[
                  const SizedBox(height: 4),
                  Text(
                    trimmedNote,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5, height: 1.3),
                  ),
                ],
              ],
            ),
          ),
          PopupMenuButton<String>(
            padding: EdgeInsets.zero,
            icon: Icon(Icons.more_vert, size: 20, color: scheme.onSurfaceVariant),
            onSelected: (action) {
              if (action == 'edit') onEdit();
              if (action == 'delete') onDelete();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'edit',
                child: Row(children: [
                  const Icon(Icons.edit_outlined, size: 18),
                  const SizedBox(width: 10),
                  Text('form.edit'.tr()),
                ]),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(children: [
                  Icon(Icons.delete_outline, size: 18, color: scheme.error),
                  const SizedBox(width: 10),
                  Text('form.delete'.tr(), style: TextStyle(color: scheme.error)),
                ]),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
