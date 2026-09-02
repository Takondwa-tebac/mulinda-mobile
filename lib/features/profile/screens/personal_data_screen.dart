import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../auth/providers/auth_controller.dart';
import '../widgets/delete_account_dialog.dart';

/// One place for everything to do with the user's data: export it, review the
/// daily summaries built from it, read exactly what's captured and how it's
/// used, and permanently delete the account. Keeps the Profile screen tidy and
/// satisfies the Play Store account-deletion requirement.
class PersonalDataScreen extends ConsumerWidget {
  const PersonalDataScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Personal data & privacy')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 32 + MediaQuery.of(context).padding.bottom),
        children: [
          _Header(
            icon: Icons.privacy_tip_outlined,
            text: 'Your data is yours. Export it, see how it\'s used, or remove it entirely — anytime.',
          ),
          const SizedBox(height: 16),

          _Label('Your data'),
          Card(
            child: Column(
              children: [
                _tile(context, Icons.ios_share_outlined, 'Export records',
                    'Download your transactions as CSV or PDF', () => context.push(Routes.exports)),
                const Divider(height: 1),
                _tile(context, Icons.insights_outlined, 'Daily summaries',
                    'The day-by-day recaps built from your activity', () => context.push(Routes.dailySummaries)),
              ],
            ),
          ),

          const SizedBox(height: 20),
          _Label('Transparency'),
          Card(
            child: Column(
              children: [
                _tile(context, Icons.data_usage_outlined, 'What we capture & how it\'s used',
                    'Plain-language summary of your data', () => _openLegal(context, 'data-usage')),
                const Divider(height: 1),
                _tile(context, Icons.policy_outlined, 'Privacy Policy', null,
                    () => _openLegal(context, 'privacy')),
                const Divider(height: 1),
                _tile(context, Icons.description_outlined, 'Terms of Service', null,
                    () => _openLegal(context, 'terms')),
              ],
            ),
          ),

          const SizedBox(height: 20),
          _Label('Danger zone'),
          Card(
            color: scheme.errorContainer.withValues(alpha: 0.4),
            child: ListTile(
              leading: Icon(Icons.delete_forever_outlined, color: scheme.error),
              title: Text('profile.deleteAccount'.tr(),
                  style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600)),
              subtitle: const Text('Permanently remove your account and all data'),
              onTap: user == null ? null : () => showDeleteAccountDialog(context, user.username),
            ),
          ),
        ],
      ),
    );
  }

  void _openLegal(BuildContext context, String slug) =>
      context.push('${Routes.legal}?slug=$slug');

  Widget _tile(BuildContext context, IconData icon, String title, String? subtitle, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.3))),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(text,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
              )),
    );
  }
}
