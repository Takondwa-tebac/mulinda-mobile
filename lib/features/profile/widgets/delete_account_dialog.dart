import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../auth/providers/auth_controller.dart';

/// Show the GitHub-style destructive account-deletion confirmation.
Future<void> showDeleteAccountDialog(BuildContext context, String username) {
  return showDialog(
    context: context,
    builder: (_) => DeleteAccountDialog(username: username),
  );
}

/// The user must type their username exactly before the Delete button enables.
/// Required for Play Store account-deletion compliance.
class DeleteAccountDialog extends ConsumerStatefulWidget {
  const DeleteAccountDialog({super.key, required this.username});
  final String username;

  @override
  ConsumerState<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<DeleteAccountDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _matches => _controller.text.trim() == widget.username;

  Future<void> _delete() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).deleteAccount(_controller.text.trim());
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.displayMessage);
    } catch (_) {
      if (mounted) setState(() => _error = 'coach.error'.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text('profile.deleteAccount'.tr()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('profile.deleteWarning'.tr(), style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          Text('profile.deleteConfirmPrompt'.tr(args: [widget.username]),
              style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            autocorrect: false,
            enableSuggestions: false,
            enabled: !_busy,
            decoration: InputDecoration(
              hintText: widget.username,
              border: const OutlineInputBorder(),
              errorText: _error,
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text('form.cancel'.tr()),
        ),
        FilledButton(
          onPressed: (_matches && !_busy) ? _delete : null,
          style: FilledButton.styleFrom(backgroundColor: scheme.error),
          child: _busy
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2.5))
              : Text('profile.deleteConfirm'.tr()),
        ),
      ],
    );
  }
}
