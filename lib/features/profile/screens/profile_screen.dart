import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/income/income_bands.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../auth/providers/auth_controller.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final scheme = Theme.of(context).colorScheme;

    final bracketKey = incomeBandKey(user?.declaredIncomeBracket);
    final bracketLabel = bracketKey != null ? '$bracketKey.label'.tr() : 'profile.notSet'.tr();

    return Scaffold(
      appBar: AppBar(title: Text('nav.profile'.tr())),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header
          if (user != null)
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.onPrimaryContainer,
                  backgroundImage:
                      (user.avatarUrl != null && user.avatarUrl!.isNotEmpty)
                          ? NetworkImage(user.avatarUrl!)
                          : null,
                  child: (user.avatarUrl == null || user.avatarUrl!.isEmpty)
                      ? Text(
                          _initials(user.fullName, user.username),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                        )
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.fullName.isEmpty ? user.username : user.fullName,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      Text(user.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          const SizedBox(height: 24),

          // Account
          _Label('profile.account'.tr()),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text('profile.editProfile'.tr()),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(Routes.editProfile),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.payments_outlined),
                  title: Text('profile.incomeBracket'.tr()),
                  subtitle: Text(bracketLabel),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _changeIncome(context, ref),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.tune_outlined),
                  title: Text('profile.preferences'.tr()),
                  subtitle: Text('profile.preferencesSub'.tr()),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(Routes.preferences),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: Text('permissions.title'.tr()),
                  subtitle: Text('permissions.manageSub'.tr()),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(Routes.permissions),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Personal data & privacy'),
                  subtitle: const Text('Export, summaries, delete account, legal'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(Routes.personalData),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.workspace_premium_outlined),
                  title: Text('subscription.title'.tr()),
                  subtitle: Text(user?.subscription.active == true
                      ? (user!.subscription.isTrial
                          ? 'subscription.trialActive'.tr()
                          : user.subscription.planLabel ?? 'subscription.active'.tr())
                      : 'subscription.free'.tr()),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(Routes.subscription),
                ),
              ],
            ),
          ),
          if (user?.isAdmin == true) ...[
            const SizedBox(height: 20),
            _Label('Administration'),
            Card(
              child: ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: const Text('Admin Panel'),
                subtitle: const Text('Users, notifications, audit trail'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(Routes.admin),
              ),
            ),
          ],
          const SizedBox(height: 28),
          OutlinedButton.icon(
            onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
            icon: const Icon(Icons.logout),
            label: Text('profile.logOut'.tr()),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _changeIncome(BuildContext context, WidgetRef ref) {
    final current = ref.read(currentUserProvider)?.declaredIncomeBracket;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (_, scrollController) => SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('profile.changeIncome'.tr(),
                      style: Theme.of(sheetContext).textTheme.titleMedium),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    for (final band in kIncomeBands)
                      ListTile(
                        title: Text('${band.$2}.label'.tr()),
                        subtitle: Text('${band.$2}.range'.tr()),
                        trailing: current == band.$1 ? const Icon(Icons.check) : null,
                        onTap: () async {
                          Navigator.of(sheetContext).pop();
                          try {
                            await ref.read(authControllerProvider.notifier).setIncomeBracket(band.$1);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context)
                                ..hideCurrentSnackBar()
                                ..showSnackBar(SnackBar(content: Text('profile.saved'.tr())));
                            }
                          } on ApiException catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context)
                                ..hideCurrentSnackBar()
                                ..showSnackBar(SnackBar(content: Text(e.displayMessage)));
                            }
                          }
                        },
                      ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _initials(String fullName, String username) {
    final base = fullName.trim().isNotEmpty ? fullName.trim() : username;
    final parts = base.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
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
