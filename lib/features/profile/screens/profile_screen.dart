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
                  child: Text(
                    _initials(user.fullName, user.username),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                  ),
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
          const SizedBox(height: 28),
          OutlinedButton.icon(
            onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
            icon: const Icon(Icons.logout),
            label: Text('profile.logOut'.tr()),
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
