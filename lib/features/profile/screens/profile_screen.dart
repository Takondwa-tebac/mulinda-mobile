import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/income/income_bands.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/theme_mode_controller.dart';
import '../../auth/providers/auth_controller.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final user = ref.watch(currentUserProvider);
    final isNyanja = context.locale.languageCode == 'ny';
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
                  leading: const Icon(Icons.shield_outlined),
                  title: Text('permissions.title'.tr()),
                  subtitle: Text('permissions.manageSub'.tr()),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(Routes.permissions),
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
          const SizedBox(height: 20),

          // Preferences
          _Label('profile.preferences'.tr()),
          Card(
            child: RadioGroup<bool>(
              groupValue: isNyanja,
              onChanged: (v) => context.setLocale(Locale(v == true ? 'ny' : 'en')),
              child: Column(
                children: [
                  RadioListTile<bool>(value: true, title: Text('profile.chichewa'.tr())),
                  RadioListTile<bool>(value: false, title: Text('profile.english'.tr())),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: RadioGroup<ThemeMode>(
              groupValue: themeMode,
              onChanged: (m) => ref.read(themeModeProvider.notifier).set(m!),
              child: Column(
                children: [
                  RadioListTile<ThemeMode>(value: ThemeMode.system, title: Text('profile.themeSystem'.tr())),
                  RadioListTile<ThemeMode>(value: ThemeMode.light, title: Text('profile.themeLight'.tr())),
                  RadioListTile<ThemeMode>(value: ThemeMode.dark, title: Text('profile.themeDark'.tr())),
                ],
              ),
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
          const SizedBox(height: 28),
          _Label('profile.dangerZone'.tr()),
          if (user != null)
            OutlinedButton.icon(
              onPressed: () => _showDeleteAccount(context, user.username),
              icon: const Icon(Icons.delete_forever_outlined),
              label: Text('profile.deleteAccount'.tr()),
              style: OutlinedButton.styleFrom(
                foregroundColor: scheme.error,
                side: BorderSide(color: scheme.error),
              ),
            ),
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

  void _showDeleteAccount(BuildContext context, String username) {
    showDialog<void>(
      context: context,
      builder: (_) => _DeleteAccountDialog(username: username),
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

/// GitHub-style destructive confirmation: the user must type their username
/// exactly before the Delete button enables.
class _DeleteAccountDialog extends ConsumerStatefulWidget {
  const _DeleteAccountDialog({required this.username});
  final String username;

  @override
  ConsumerState<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<_DeleteAccountDialog> {
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
      // Auth state flips to unauthenticated → router redirects to login.
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
              ? const SizedBox(
                  height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2.5))
              : Text('profile.deleteConfirm'.tr()),
        ),
      ],
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
