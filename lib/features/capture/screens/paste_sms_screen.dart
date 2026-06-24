import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/permissions/permission_service.dart';
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
  bool _importLoading = false;

  @override
  void dispose() {
    _body.dispose();
    _sender.dispose();
    super.dispose();
  }

  Future<void> _importFromInbox() async {
    setState(() => _importLoading = true);
    try {
      final granted =
          await ref.read(permissionServiceProvider).requestSms();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('SMS permission denied. Please enable it in Settings.')),
          );
        }
        return;
      }

      final query = SmsQuery();
      final messages = await query.querySms(
        kinds: [SmsQueryKind.inbox],
        count: 50,
      );

      // Filter for likely financial messages
      final financial = messages.where((m) {
        final body = (m.body ?? '').toLowerCase();
        return body.contains('mwk') ||
            body.contains('kwacha') ||
            body.contains('airtel') ||
            body.contains('mpamba') ||
            body.contains('tnm') ||
            body.contains('received') ||
            body.contains('sent') ||
            body.contains('withdrawn') ||
            body.contains('deposited') ||
            body.contains('payment') ||
            body.contains('balance') ||
            body.contains('transaction');
      }).toList();

      if (!mounted) return;

      if (financial.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No financial SMS messages found in your inbox.')),
        );
        return;
      }

      final picked = await showModalBottomSheet<SmsMessage>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _SmsPickerSheet(messages: financial),
      );

      if (picked != null && mounted) {
        _body.text = picked.body ?? '';
        _sender.text = picked.sender ?? '';
      }
    } finally {
      if (mounted) setState(() => _importLoading = false);
    }
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
      appBar: AppBar(
        title: Text('sms.title'.tr()),
        actions: [
          TextButton.icon(
            onPressed: (_loading || _importLoading) ? null : _importFromInbox,
            icon: _importLoading
                ? SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: scheme.primary),
                  )
                : const Icon(Icons.inbox_outlined, size: 18),
            label: const Text('Import'),
          ),
        ],
      ),
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
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'auth.required'.tr() : null,
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

class _SmsPickerSheet extends StatelessWidget {
  const _SmsPickerSheet({required this.messages});

  final List<SmsMessage> messages;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      expand: false,
      builder: (_, controller) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Text('Select a message',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              controller: controller,
              itemCount: messages.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final msg = messages[i];
                final date = msg.date;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: scheme.primaryContainer,
                    child: Icon(Icons.sms_outlined,
                        color: scheme.onPrimaryContainer, size: 18),
                  ),
                  title: Text(
                    msg.sender ?? 'Unknown',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    msg.body ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: date != null
                      ? Text(
                          '${date.day}/${date.month}',
                          style: TextStyle(
                              color: scheme.onSurfaceVariant, fontSize: 12),
                        )
                      : null,
                  onTap: () => Navigator.of(context).pop(msg),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
