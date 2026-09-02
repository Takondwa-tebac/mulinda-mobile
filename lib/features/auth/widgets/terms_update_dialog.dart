import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../providers/auth_controller.dart';
import 'terms_accept_sheet.dart';

/// If the signed-in user hasn't accepted the latest Terms (driven by
/// `terms_current_version` vs `terms_version` from the API), pop a dialog
/// prompting them to review and accept. No-op when they're up to date.
/// Safe to call more than once — it re-checks each time.
Future<void> maybePromptTermsUpdate(BuildContext context, WidgetRef ref) async {
  final user = ref.read(currentUserProvider);
  if (user == null || !user.needsTermsAcceptance) return;

  final action = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      icon: const Icon(Icons.gavel_outlined),
      title: const Text('We\'ve updated our Terms'),
      content: const Text(
        'We\'ve made some changes to our Terms of Service. '
        'Please take a moment to review and accept them to keep using Mulinda.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, 'later'), child: const Text('Later')),
        FilledButton(onPressed: () => Navigator.pop(context, 'review'), child: const Text('Review & accept')),
      ],
    ),
  );

  if (action != 'review' || !context.mounted) return;

  final accepted = await showTermsAcceptSheet(context);
  if (accepted != true) return;

  try {
    await ref.read(authControllerProvider.notifier).acceptTerms();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks — your acceptance was recorded.')),
      );
    }
  } on ApiException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.displayMessage)));
    }
  }
}
