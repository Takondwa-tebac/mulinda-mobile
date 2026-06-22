import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../activity/data/activity_repository.dart';

class PasteSmsScreen extends ConsumerStatefulWidget {
  const PasteSmsScreen({super.key});

  @override
  ConsumerState<PasteSmsScreen> createState() => _PasteSmsScreenState();
}

class _PasteSmsScreenState extends ConsumerState<PasteSmsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _body = TextEditingController();
  final _sender = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _body.dispose();
    _sender.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref.read(activityRepositoryProvider).ingestSms(
            _body.text.trim(),
            sender: _sender.text.trim(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('sms.queued'.tr())));
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('sms.title'.tr())),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('sms.subtitle'.tr(),
                    style: TextStyle(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _body,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: 'sms.body'.tr(),
                    alignLabelWithHint: true,
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'auth.required'.tr() : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _sender,
                  decoration: InputDecoration(labelText: 'sms.sender'.tr()),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: scheme.onPrimary),
                        )
                      : Text('sms.submit'.tr()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
