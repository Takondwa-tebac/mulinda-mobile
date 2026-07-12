import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/currencies.dart';
import '../../../core/money/currency_picker.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/security/biometric_service.dart';
import '../../../core/theme/theme_mode_controller.dart';
import '../../auth/providers/auth_controller.dart';

/// Dedicated preferences screen (language, theme, display currency, biometrics)
/// — moved off the profile screen so it can grow without cluttering it.
class PreferencesScreen extends ConsumerStatefulWidget {
  const PreferencesScreen({super.key});

  @override
  ConsumerState<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends ConsumerState<PreferencesScreen> {
  bool _bioEnabled = false;
  bool _bioAvailable = false;
  bool _bioBusy = false;

  @override
  void initState() {
    super.initState();
    _loadBiometric();
  }

  Future<void> _loadBiometric() async {
    final bio = ref.read(biometricServiceProvider);
    final available = await bio.isAvailable();
    final enabled = await bio.isEnabled();
    if (mounted) {
      setState(() {
        _bioAvailable = available;
        _bioEnabled = enabled;
      });
    }
  }

  Future<void> _toggleBiometric(bool value) async {
    final bio = ref.read(biometricServiceProvider);
    setState(() => _bioBusy = true);
    try {
      if (value) {
        final ok = await bio.authenticate('security.unlockReason'.tr());
        if (ok) {
          await bio.setEnabled(true);
          if (mounted) setState(() => _bioEnabled = true);
        }
      } else {
        await bio.setEnabled(false);
        if (mounted) setState(() => _bioEnabled = false);
      }
    } finally {
      if (mounted) setState(() => _bioBusy = false);
    }
  }

  Future<void> _changeCurrency() async {
    final current = ref.read(currentUserProvider)?.displayCurrency ?? 'MWK';
    final picked = await showCurrencyPicker(context, selected: current);
    if (picked == null || picked == current || !mounted) return;
    try {
      await ref.read(authControllerProvider.notifier).updateProfile(displayCurrency: picked);
      _snack('profile.saved'.tr());
    } on ApiException catch (e) {
      _snack(e.displayMessage);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final isNyanja = context.locale.languageCode == 'ny';
    final currency = currencyInfo(ref.watch(currentUserProvider)?.displayCurrency ?? 'MWK');

    return Scaffold(
      appBar: AppBar(title: Text('profile.preferences'.tr())),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Label('profile.language'.tr()),
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
          _Label('profile.theme'.tr()),
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
          const SizedBox(height: 20),
          _Label('profile.moneySecurity'.tr()),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.language_outlined),
                  title: Text('currency.display'.tr()),
                  subtitle: Text('${currency.flag}  ${currency.code} · ${currency.name}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _changeCurrency,
                ),
                if (_bioAvailable) ...[
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.fingerprint),
                    title: Text('security.biometricLock'.tr()),
                    subtitle: Text('security.biometricSub'.tr()),
                    value: _bioEnabled,
                    onChanged: _bioBusy ? null : _toggleBiometric,
                  ),
                ],
              ],
            ),
          ),
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
