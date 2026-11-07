import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/income/income_bands.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/security/screenshot_protection.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/section_header.dart';
import '../../auth/data/user.dart';
import '../../subscription/widgets/subscription_status_tile.dart';
import '../../auth/providers/auth_controller.dart';
import '../widgets/offline_sync_section.dart';
import '../../../core/theme/app_icons.dart';

/// Profile: the account header, then grouped settings — Account, Money &
/// accounts, Notifications & preferences, Security & privacy, Subscription,
/// Help & support and (for admins) Administration — and a confirmed log out.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);

    final bracketKey = incomeBandKey(user?.declaredIncomeBracket);
    final bracketLabel = bracketKey != null ? '$bracketKey.label'.tr() : 'profile.notSet'.tr();

    return Scaffold(
      appBar: AppBar(title: Text('nav.profile'.tr())),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screen,
          AppSpacing.lg,
          AppSpacing.screen,
          AppSpacing.xxl + MediaQuery.of(context).padding.bottom,
        ),
        children: [
          if (user != null) _Header(user: user),
          const SizedBox(height: AppSpacing.xl),

          _Section(
            title: 'profile.account'.tr(),
            children: [
              _Row(
                icon: Icons.person_outline,
                title: 'profile.editProfile'.tr(),
                onTap: () => context.push(Routes.editProfile),
              ),
              _Row(
                icon: Icons.payments_outlined,
                title: 'profile.incomeBracket'.tr(),
                subtitle: bracketLabel,
                onTap: () => _changeIncome(context, ref),
              ),
            ],
          ),

          _Section(
            title: 'profile2.moneyAccounts'.tr(),
            children: [
              _Row(
                icon: Icons.account_balance_wallet_outlined,
                title: 'profile2.accounts'.tr(),
                subtitle: 'profile2.accountsSub'.tr(),
                onTap: () => context.go(Routes.activity),
              ),
              _Row(
                icon: Icons.ios_share_outlined,
                title: 'profile2.export'.tr(),
                subtitle: 'profile2.exportSub'.tr(),
                onTap: () => context.push(Routes.exports),
              ),
              _Row(
                icon: Icons.insights_outlined,
                title: 'profile2.dailySummaries'.tr(),
                subtitle: 'profile2.dailySummariesSub'.tr(),
                onTap: () => context.push(Routes.dailySummaries),
              ),
            ],
          ),

          _Section(
            title: 'profile2.notificationsPrefs'.tr(),
            children: [
              _Row(
                icon: Icons.tune_outlined,
                title: 'profile.preferences'.tr(),
                subtitle: 'profile.preferencesSub'.tr(),
                onTap: () => context.push(Routes.preferences),
              ),
              _Row(
                icon: Icons.notifications_outlined,
                title: 'profile2.notifications'.tr(),
                subtitle: 'profile2.notificationsSub'.tr(),
                onTap: () => context.push(Routes.insights),
              ),
              _Row(
                icon: Icons.shield_outlined,
                title: 'permissions.title'.tr(),
                subtitle: 'permissions.manageSub'.tr(),
                onTap: () => context.push(Routes.permissions),
              ),
            ],
          ),

          _Section(
            title: 'profile2.securityPrivacy'.tr(),
            children: [
              _Row(
                icon: Icons.privacy_tip_outlined,
                title: 'profile2.personalData'.tr(),
                subtitle: 'profile2.personalDataSub'.tr(),
                onTap: () => context.push(Routes.personalData),
              ),
              const OfflineSyncTile(),
              if (user?.isSuperAdmin == true)
                SwitchListTile(
                  secondary: const Icon(Icons.screenshot_monitor_outlined),
                  title: Text('profile2.blockScreenshots'.tr()),
                  subtitle: Text('profile2.blockScreenshotsSub'.tr()),
                  value: ref.watch(screenshotProtectionProvider),
                  onChanged: (v) => ref.read(screenshotProtectionProvider.notifier).setProtected(v),
                ),
            ],
          ),

          _Section(title: 'subscription.title'.tr(), children: const [SubscriptionStatusTile()]),

          _Section(
            title: 'profile2.help'.tr(),
            children: [
              _Row(
                icon: AppIcons.coach,
                title: 'profile2.askCoach'.tr(),
                subtitle: 'profile2.askCoachSub'.tr(),
                onTap: () => context.push(Routes.coach),
              ),
              _Row(
                icon: Icons.data_usage_outlined,
                title: 'profile2.howDataUsed'.tr(),
                onTap: () => context.push('${Routes.legal}?slug=data-usage'),
              ),
              _Row(
                icon: Icons.policy_outlined,
                title: 'profile2.privacyPolicy'.tr(),
                onTap: () => context.push('${Routes.legal}?slug=privacy'),
              ),
              _Row(
                icon: Icons.description_outlined,
                title: 'profile2.terms'.tr(),
                onTap: () => context.push('${Routes.legal}?slug=terms'),
              ),
            ],
          ),

          if (user?.isAdmin == true)
            _Section(
              title: 'profile2.admin'.tr(),
              children: [
                _Row(
                  icon: Icons.admin_panel_settings_outlined,
                  title: 'profile2.adminPanel'.tr(),
                  subtitle: 'profile2.adminPanelSub'.tr(),
                  onTap: () => context.push(Routes.admin),
                ),
              ],
            ),

          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: () => _confirmLogout(context, ref),
            icon: const Icon(Icons.logout),
            label: Text('profile.logOut'.tr()),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('profile2.logoutTitle'.tr()),
        content: Text('profile2.logoutBody'.tr()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text('common.cancel'.tr())),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text('profile.logOut'.tr())),
        ],
      ),
    );
    if (ok == true) await ref.read(authControllerProvider.notifier).signOut();
  }

  void _changeIncome(BuildContext context, WidgetRef ref) {
    final current = ref.read(currentUserProvider)?.declaredIncomeBracket;
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
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
                  child: Text('profile.changeIncome'.tr(), style: Theme.of(sheetContext).textTheme.titleMedium),
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
                    const SizedBox(height: AppSpacing.lg),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasAvatar = user.avatarUrl != null && user.avatarUrl!.isNotEmpty;
    return Row(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: scheme.primaryContainer,
          foregroundColor: scheme.onPrimaryContainer,
          backgroundImage: hasAvatar ? NetworkImage(user.avatarUrl!) : null,
          child: hasAvatar
              ? null
              : Text(
                  _initials(user.fullName, user.username),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user.fullName.isEmpty ? user.username : user.fullName,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                user.email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'profile.editProfile'.tr(),
          icon: const Icon(Icons.edit_outlined),
          onPressed: () => context.push(Routes.editProfile),
        ),
      ],
    );
  }

  static String _initials(String fullName, String username) {
    final base = fullName.trim().isNotEmpty ? fullName.trim() : username;
    final parts = base.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
  }
}

/// A titled card of settings rows with dividers between them.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title, dense: true),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[if (i > 0) const Divider(height: 1), children[i]],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
