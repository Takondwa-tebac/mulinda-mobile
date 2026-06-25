import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../data/admin_repository.dart';

class PushNotificationScreen extends ConsumerStatefulWidget {
  const PushNotificationScreen({super.key});

  @override
  ConsumerState<PushNotificationScreen> createState() =>
      _PushNotificationScreenState();
}

class _PushNotificationScreenState
    extends ConsumerState<PushNotificationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _imageUrl = TextEditingController();
  bool _broadcastAll = true;
  bool _sending = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _imageUrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _sending = true);
    try {
      final count = await ref.read(adminRepositoryProvider).broadcastNotification(
            title: _title.text.trim(),
            body: _body.text.trim(),
            imageUrl: _imageUrl.text.trim().isEmpty ? null : _imageUrl.text.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('Sent to $count user${count == 1 ? '' : 's'}.'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ));
      _title.clear();
      _body.clear();
      _imageUrl.clear();
    } on ApiException catch (e) {
      if (!mounted) return;
      _showError(e.displayMessage);
    } catch (_) {
      if (!mounted) return;
      _showError('Failed to send notification. Please try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
          SnackBar(content: Text(message),
              backgroundColor: Theme.of(context).colorScheme.error));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Send Notification')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          children: [
            // Preview card
            Card(
              color: scheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      child: const Icon(Icons.notifications, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ValueListenableBuilder(
                            valueListenable: _title,
                            builder: (_, v, _) => Text(
                              v.text.isEmpty ? 'Notification title' : v.text,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(height: 4),
                          ValueListenableBuilder(
                            valueListenable: _body,
                            builder: (_, v, _) => Text(
                              v.text.isEmpty
                                  ? 'Your notification body will appear here...'
                                  : v.text,
                              style: TextStyle(
                                  color: scheme.onSurfaceVariant, fontSize: 13),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            Text('Compose',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: scheme.primary, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),

            TextFormField(
              controller: _title,
              maxLength: 100,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'Keep it short and clear',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Title is required' : null,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _body,
              maxLength: 500,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Message body',
                hintText: 'What do you want users to know?',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Body is required' : null,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _imageUrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Image URL (optional)',
                hintText: 'https://... — must be a public HTTPS URL',
                prefixIcon: Icon(Icons.image_outlined),
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final uri = Uri.tryParse(v.trim());
                if (uri == null || !uri.hasScheme || !uri.isAbsolute) {
                  return 'Enter a valid URL';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),

            Text('Recipients',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: scheme.primary, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),

            Card(
              child: RadioGroup<bool>(
                groupValue: _broadcastAll,
                onChanged: (v) => setState(() => _broadcastAll = v!),
                child: Column(
                  children: [
                    RadioListTile<bool>(
                      value: true,
                      title: const Text('All users'),
                      subtitle: const Text('Send to every registered user'),
                    ),
                    RadioListTile<bool>(
                      value: false,
                      title: const Text('Specific users'),
                      subtitle: const Text('Coming soon — target by user ID'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            FilledButton.icon(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Icon(Icons.send_rounded),
              label: Text(_sending ? 'Sending…' : 'Send to all users'),
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
            ),
          ],
        ),
      ),
    );
  }
}
