import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../activity/data/activity_models.dart';
import '../../activity/data/activity_repository.dart';
import '../../activity/screens/add_transaction_screen.dart';
import '../../dashboard/data/dashboard_repository.dart';
import '../data/plan_models.dart';
import '../data/plan_repository.dart';

/// Which expenses a budget is counting right now: its category (or everything,
/// when it has none) within the period the server is measuring.
typedef BudgetPeriodKey = ({String? categoryId, String? from, String? to});

final budgetSpendProvider = FutureProvider.autoDispose.family<List<Txn>, BudgetPeriodKey>((ref, key) {
  return ref.read(activityRepositoryProvider).expensesForPeriod(
        categoryId: key.categoryId,
        from: key.from,
        to: key.to,
      );
});

/// Refresh everything that depends on a budget's spend.
void refreshBudgetData(WidgetRef ref) {
  ref
    ..invalidate(budgetsProvider)
    ..invalidate(budgetSpendProvider)
    ..invalidate(transactionsProvider)
    ..invalidate(accountsProvider)
    ..invalidate(dashboardProvider);
}

/// "Spending this period" on the budget screen: the expenses that make up the
/// spend, a way to record a new one, and a way to count an existing one.
class BudgetSpendingSection extends ConsumerWidget {
  const BudgetSpendingSection({super.key, required this.budget});

  final BudgetItem budget;

  BudgetPeriodKey get _key => (categoryId: budget.categoryId, from: budget.periodFrom, to: budget.periodTo);

  Future<void> _recordSpend(BuildContext context, WidgetRef ref) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => AddTransactionScreen(
        initialCategoryId: budget.categoryId,
        budgetName: budget.name.isEmpty ? 'budgetSpend.thisBudget'.tr() : budget.name,
        expenseOnly: true,
      ),
    ));
    refreshBudgetData(ref);
  }

  Future<void> _allocateExisting(BuildContext context, WidgetRef ref) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AllocateSheet(budget: budget),
    );
    if (changed == true) refreshBudgetData(ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final spend = ref.watch(budgetSpendProvider(_key));
    final hasCategory = budget.categoryId != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _recordSpend(context, ref),
                icon: const Icon(Icons.add, size: 18),
                label: Text('budgetSpend.recordSpend'.tr()),
              ),
            ),
            if (hasCategory) ...[
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _allocateExisting(context, ref),
                  icon: const Icon(Icons.link, size: 18),
                  label: Text('budgetSpend.addExisting'.tr()),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 18),
        Text('budgetSpend.spendingThisPeriod'.tr(),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(
          hasCategory
              ? 'budgetSpend.countsCategory'.tr(args: [budget.categoryName ?? 'budgetSpend.budget'.tr()])
              : 'budgetSpend.countsAll'.tr(),
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
        ),
        const SizedBox(height: 8),
        spend.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              children: [
                Text(e is ApiException ? e.displayMessage : 'budgetSpend.loadError'.tr()),
                TextButton(onPressed: () => ref.invalidate(budgetSpendProvider), child: Text('plan.retry'.tr())),
              ],
            ),
          ),
          data: (items) {
            if (items.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text('budgetSpend.nothingSpent'.tr(), style: TextStyle(color: scheme.onSurfaceVariant)),
                ),
              );
            }
            return Card(
              child: Column(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _SpendTile(txn: items[i]),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _SpendTile extends StatelessWidget {
  const _SpendTile({required this.txn});

  final Txn txn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title =
        txn.merchant?.isNotEmpty == true ? txn.merchant! : (txn.categoryName ?? 'budgetSpend.expense'.tr());
    final detail = [
      if (txn.component != null && txn.component != 'principal') txn.component,
      txn.categoryName,
      txn.date,
    ].where((e) => e != null && e.isNotEmpty).join(' · ');

    return ListTile(
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(
        txn.amount.formatted,
        style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onSurface),
      ),
      onTap: () => context.push(Routes.transactionDetail, extra: txn.id),
    );
  }
}

/// Expenses from this period that are not in the budget's category yet. Picking
/// one moves it into that category, so it counts toward the budget.
class _AllocateSheet extends ConsumerStatefulWidget {
  const _AllocateSheet({required this.budget});

  final BudgetItem budget;

  @override
  ConsumerState<_AllocateSheet> createState() => _AllocateSheetState();
}

class _AllocateSheetState extends ConsumerState<_AllocateSheet> {
  String? _busyId;

  Future<void> _assign(Txn txn) async {
    setState(() => _busyId = txn.id);
    try {
      // The update sends merchant and notes too (it clears what it is not given),
      // so pass the current values to leave them as they are.
      await ref.read(activityRepositoryProvider).updateTransaction(
            txn.id,
            categoryId: widget.budget.categoryId,
            merchant: txn.merchant,
            notes: txn.notes,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('budgetSpend.added'.tr())));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busyId = null);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.displayMessage)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final b = widget.budget;
    // All expenses in the period; the ones already counted are filtered out below.
    final all = ref.watch(budgetSpendProvider((categoryId: null, from: b.periodFrom, to: b.periodTo)));
    final category = b.categoryName ?? 'budgetSpend.thisBudgetsCategory'.tr();

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('budgetSpend.pickTitle'.tr(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                const SizedBox(height: 4),
                Text(
                  'budgetSpend.pickBody'.tr(args: [category]),
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13, height: 1.35),
                ),
              ],
            ),
          ),
          Expanded(
            child: all.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(e is ApiException ? e.displayMessage : 'budgetSpend.loadError'.tr())),
              data: (items) {
                final candidates = items.where((t) => t.categoryId != b.categoryId && t.parentId == null).toList();
                if (candidates.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'budgetSpend.pickEmpty'.tr(),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: candidates.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final t = candidates[i];
                    final title =
                        t.merchant?.isNotEmpty == true ? t.merchant! : (t.categoryName ?? 'budgetSpend.expense'.tr());
                    return ListTile(
                      enabled: _busyId == null,
                      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        [t.categoryName ?? 'budgetSpend.noCategory'.tr(), t.date].where((e) => e.isNotEmpty).join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: _busyId == t.id
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(t.amount.formatted, style: const TextStyle(fontWeight: FontWeight.w700)),
                      onTap: () => _assign(t),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
