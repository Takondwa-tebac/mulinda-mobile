import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_date_field.dart';
import '../../../core/widgets/category_icons.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/info_row.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/transaction_tile.dart';
import '../../activity/widgets/txn_view.dart';
import '../data/bill_models.dart';

/// A recurring bill: how much it usually is, how often, when it is next due,
/// its category and the recent payments that matched it.
class BillDetailScreen extends StatelessWidget {
  const BillDetailScreen({super.key, required this.bill});

  final Bill bill;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final cadenceKey = 'bills.cadence.${bill.cadence}';
    final cadence = cadenceKey.tr() == cadenceKey ? bill.cadence : cadenceKey.tr();

    return Scaffold(
      appBar: AppBar(title: Text(bill.label.isEmpty ? 'bills.title'.tr() : bill.label)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xxl),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  CategoryAvatar(
                    icon: bill.categoryIcon,
                    color: bill.categoryColor,
                    size: 48,
                    fallbackIcon: Icons.receipt_long_outlined,
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('bills.usually'.tr(), style: TextStyle(color: scheme.onSurfaceVariant)),
                        Text(
                          bill.amount?.formatted ?? '–',
                          key: const ValueKey('bill-amount'),
                          style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        if (bill.nextDue != null)
                          Text(
                            'bills.nextDue'.tr(args: [formatDay(bill.nextDue!)]),
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Card(
            child: Column(
              children: [
                InfoRow(icon: Icons.repeat, label: 'bills.cadenceLabel'.tr(), value: cadence),
                if (bill.nextDue != null)
                  InfoRow(
                    icon: Icons.event_outlined,
                    label: 'bills.nextDueLabel'.tr(),
                    value: formatDay(bill.nextDue!),
                  ),
                InfoRow(
                  icon: Icons.category_outlined,
                  label: 'activity2.detail.category'.tr(),
                  value: bill.categoryName ?? 'activity2.uncategorised'.tr(),
                ),
                if (bill.lastSeen != null)
                  InfoRow(icon: Icons.history, label: 'bills.lastPaid'.tr(), value: formatDay(bill.lastSeen!)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          SectionHeader('bills.recent'.tr()),
          if (bill.recent.isEmpty)
            EmptyState(compact: true, icon: Icons.receipt_long_outlined, title: 'bills.noPayments'.tr())
          else
            for (final t in bill.recent)
              TransactionTile(
                data: txnTileData(t, meta: t.occurredLocal == null ? null : dayHeaderLabel(t.occurredLocal)),
                onTap: () => context.push(Routes.transactionById(t.id)),
              ),
        ],
      ),
    );
  }
}
