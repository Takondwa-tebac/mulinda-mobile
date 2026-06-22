import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../dashboard/data/dashboard_repository.dart';
import '../data/activity_models.dart';
import '../data/activity_repository.dart';

class AddTransactionScreen extends ConsumerStatefulWidget {
  const AddTransactionScreen({super.key});

  @override
  ConsumerState<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _merchant = TextEditingController();
  final _notes = TextEditingController();

  String _type = 'expense';
  String? _accountId;
  String? _categoryId;
  DateTime _date = DateTime.now();
  bool _loading = false;

  @override
  void dispose() {
    _amount.dispose();
    _merchant.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_accountId == null) return;
    setState(() => _loading = true);
    try {
      await ref.read(activityRepositoryProvider).createTransaction(
            accountId: _accountId!,
            type: _type,
            amount: double.parse(_amount.text.trim()),
            categoryId: _categoryId,
            occurredAt: _date,
            merchant: _merchant.text.trim(),
            notes: _notes.text.trim(),
          );
      ref
        ..invalidate(transactionsProvider)
        ..invalidate(accountsProvider)
        ..invalidate(dashboardProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('addTxn.saved'.tr())));
        Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.displayMessage)));
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider);
    final categories = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(title: Text('addTxn.title'.tr())),
      body: SafeArea(
        child: accounts.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(child: Text('activity.loadError'.tr())),
          data: (accountList) {
            if (accountList.isEmpty) return _NeedAccount(onAdded: () => ref.invalidate(accountsProvider));
            _accountId ??= accountList.first.id;

            final cats = categories.maybeWhen(
              data: (c) => c.where((x) => x.kind == _type).toList(),
              orElse: () => <Category>[],
            );
            // Drop a stale category selection when switching type.
            if (_categoryId != null && !cats.any((c) => c.id == _categoryId)) {
              _categoryId = null;
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment(value: 'expense', label: Text('addTxn.expense'.tr())),
                        ButtonSegment(value: 'income', label: Text('addTxn.income'.tr())),
                      ],
                      selected: {_type},
                      onSelectionChanged: (s) => setState(() => _type = s.first),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _amount,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: 'addTxn.amount'.tr(), prefixText: 'MK '),
                      validator: (v) {
                        final n = double.tryParse((v ?? '').trim());
                        if (n == null || n <= 0) return 'auth.required'.tr();
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _accountId,
                      decoration: InputDecoration(labelText: 'addTxn.account'.tr()),
                      items: accountList
                          .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                          .toList(),
                      onChanged: (v) => setState(() => _accountId = v),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String?>(
                      initialValue: _categoryId,
                      decoration: InputDecoration(labelText: 'addTxn.category'.tr()),
                      items: [
                        DropdownMenuItem(value: null, child: Text('addTxn.none'.tr())),
                        ...cats.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
                      ],
                      onChanged: (v) => setState(() => _categoryId = v),
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(16),
                      child: InputDecorator(
                        decoration: InputDecoration(labelText: 'addTxn.date'.tr()),
                        child: Text(_date.toIso8601String().split('T').first),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _merchant,
                      decoration: InputDecoration(labelText: 'addTxn.merchant'.tr()),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _notes,
                      maxLines: 2,
                      decoration: InputDecoration(labelText: 'addTxn.notes'.tr()),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _loading ? null : _save,
                      child: _loading
                          ? SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Theme.of(context).colorScheme.onPrimary),
                            )
                          : Text('addTxn.save'.tr()),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NeedAccount extends StatelessWidget {
  const _NeedAccount({required this.onAdded});
  final VoidCallback onAdded;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('addTxn.needAccount'.tr(), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () async {
                final added = await context.push<bool>(Routes.addAccount);
                if (added == true) onAdded();
              },
              icon: const Icon(Icons.add),
              label: Text('account.add'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
