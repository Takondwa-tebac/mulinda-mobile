import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/currency_picker.dart';
import '../../../core/network/api_exception.dart';
import '../data/activity_repository.dart';

class AddAccountScreen extends ConsumerStatefulWidget {
  const AddAccountScreen({super.key});

  @override
  ConsumerState<AddAccountScreen> createState() => _AddAccountScreenState();
}

class _AddAccountScreenState extends ConsumerState<AddAccountScreen> {
  static const _types = ['mobile_money', 'bank', 'cash', 'wallet', 'savings'];

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _opening = TextEditingController();
  String _type = 'mobile_money';
  String _currency = 'MWK';
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _opening.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref.read(activityRepositoryProvider).createAccount(
            name: _name.text.trim(),
            type: _type,
            openingBalance: double.tryParse(_opening.text.trim()),
            currency: _currency,
          );
      ref.invalidate(accountsProvider);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.displayMessage)));
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('account.title'.tr())),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: InputDecoration(labelText: 'account.name'.tr()),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'auth.required'.tr() : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: InputDecoration(labelText: 'account.type'.tr()),
                  items: _types
                      .map((t) => DropdownMenuItem(value: t, child: Text('account.$t'.tr())))
                      .toList(),
                  onChanged: (v) => setState(() => _type = v ?? _type),
                ),
                const SizedBox(height: 16),
                CurrencyField(
                  value: _currency,
                  label: 'account.currency'.tr(),
                  onChanged: (v) => setState(() => _currency = v),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _opening,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'account.openingBalance'.tr()),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _loading ? null : _save,
                  child: _loading
                      ? const _Spinner()
                      : Text('account.save'.tr()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 22,
        width: 22,
        child: CircularProgressIndicator(
            strokeWidth: 2.5, color: Theme.of(context).colorScheme.onPrimary),
      );
}
