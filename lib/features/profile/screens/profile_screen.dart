import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_mode_controller.dart';
import '../../auth/providers/auth_controller.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final isNyanja = context.locale.languageCode == 'ny';

    return Scaffold(
      appBar: AppBar(title: Text('nav.profile'.tr())),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Language
          _SectionLabel('profile.language'.tr()),
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
          const SizedBox(height: 20),
          // Appearance
          _SectionLabel('profile.appearance'.tr()),
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
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
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
