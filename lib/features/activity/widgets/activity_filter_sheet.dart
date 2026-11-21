import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../data/activity_models.dart';
import '../data/activity_repository.dart';
import 'category_picker.dart';
import 'txn_view.dart';

/// Category, account and date-range filters. Returns the new query, or null
/// when dismissed. Search, type and "needs category" are kept as they were.
Future<TxnQuery?> showActivityFilterSheet(BuildContext context, TxnQuery current) {
  return showModalBottomSheet<TxnQuery>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => _FilterSheet(initial: current),
  );
}

class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet({required this.initial});

  final TxnQuery initial;

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late String? _categoryId = widget.initial.categoryId;
  late String? _accountId = widget.initial.accountId;
  late DateTime? _from = widget.initial.from;
  late DateTime? _to = widget.initial.to;

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: _from != null && _to != null ? DateTimeRange(start: _from!, end: _to!) : null,
    );
    if (picked != null) {
      setState(() {
        _from = picked.start;
        _to = picked.end;
      });
    }
  }

  void _quickRange(int days) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _from = today.subtract(Duration(days: days - 1));
      _to = today;
    });
  }

  void _thisMonth() {
    final now = DateTime.now();
    setState(() {
      _from = DateTime(now.year, now.month, 1);
      _to = DateTime(now.year, now.month, now.day);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const <Account>[];
    final kind = widget.initial.type; // only offer categories of the chosen type
    final range = _from == null || _to == null ? null : '${shortDate(_from!)} – ${shortDate(_to!)}';

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('activity2.filters'.tr(), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: AppSpacing.lg),
              CategoryPickerField(
                value: _categoryId,
                kind: kind,
                createKind: kind ?? 'expense',
                onChanged: (v) => setState(() => _categoryId = v),
              ),
              const SizedBox(height: AppSpacing.lg),
              DropdownButtonFormField<String?>(
                initialValue: accounts.any((a) => a.id == _accountId) ? _accountId : null,
                decoration: InputDecoration(labelText: 'activity2.account'.tr()),
                items: [
                  DropdownMenuItem<String?>(value: null, child: Text('activity2.allAccounts'.tr())),
                  for (final a in accounts)
                    DropdownMenuItem<String?>(
                      value: a.id,
                      child: Text(a.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => _accountId = v),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('activity2.dateRange'.tr(), style: theme.textTheme.labelLarge),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  ActionChip(label: Text('activity2.last7'.tr()), onPressed: () => _quickRange(7)),
                  ActionChip(label: Text('activity2.last30'.tr()), onPressed: () => _quickRange(30)),
                  ActionChip(label: Text('activity2.thisMonth'.tr()), onPressed: _thisMonth),
                  ActionChip(
                    avatar: const Icon(Icons.date_range, size: 18),
                    label: Text(range ?? 'activity2.pickDates'.tr()),
                    onPressed: _pickDates,
                  ),
                  if (range != null)
                    InputChip(
                      label: Text('activity2.anyDate'.tr()),
                      onDeleted: () => setState(() => _from = _to = null),
                      onPressed: () => setState(() => _from = _to = null),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(
                        widget.initial.copyWith(
                          categoryId: () => null,
                          accountId: () => null,
                          from: () => null,
                          to: () => null,
                        ),
                      ),
                      child: Text('activity2.clear'.tr()),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(
                        widget.initial.copyWith(
                          categoryId: () => _categoryId,
                          accountId: () => _accountId,
                          from: () => _from,
                          to: () => _to,
                        ),
                      ),
                      child: Text('activity2.apply'.tr()),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
