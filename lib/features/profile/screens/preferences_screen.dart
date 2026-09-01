import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/money/currencies.dart';
import '../../../core/money/currency_picker.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/router/routes.dart';
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
  bool _summaryBusy = false;

  TimeOfDay _parseHm(String hm) {
    final parts = hm.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts.first) ?? 18,
      minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0,
    );
  }

  String _fmtHm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _toggleDailySummary(bool value) async {
    setState(() => _summaryBusy = true);
    try {
      // Turning it on needs notification permission for the push to show.
      if (value) await NotificationService.requestReminderPermissions();
      await ref.read(authControllerProvider.notifier).updateProfile(dailySummaryEnabled: value);
      _snack('profile.saved'.tr());
    } on ApiException catch (e) {
      _snack(e.displayMessage);
    } finally {
      if (mounted) setState(() => _summaryBusy = false);
    }
  }

  Future<void> _pickSummaryTime() async {
    final current = _parseHm(ref.read(currentUserProvider)?.dailySummaryTime ?? '18:00');
    final picked = await showTimePicker(
      context: context,
      initialTime: current,
      helpText: 'Send my daily summary at',
    );
    if (picked == null || !mounted) return;
    try {
      await ref.read(authControllerProvider.notifier).updateProfile(dailySummaryTime: _fmtHm(picked));
      _snack('profile.saved'.tr());
    } on ApiException catch (e) {
      _snack(e.displayMessage);
    }
  }

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
    final user = ref.watch(currentUserProvider);
    final currency = currencyInfo(user?.displayCurrency ?? 'MWK');
    final summaryEnabled = user?.dailySummaryEnabled ?? true;
    final summaryTime = _parseHm(user?.dailySummaryTime ?? '18:00');

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
          const SizedBox(height: 20),
          _Label('Notifications'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_active_outlined),
                  title: const Text('Daily spending summary'),
                  subtitle: const Text('A recap of what you spent, each day'),
                  value: summaryEnabled,
                  onChanged: _summaryBusy ? null : _toggleDailySummary,
                ),
                const Divider(height: 1),
                ListTile(
                  enabled: summaryEnabled,
                  leading: const Icon(Icons.schedule_outlined),
                  title: const Text('Send at'),
                  subtitle: Text(summaryTime.format(context)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: summaryEnabled ? _pickSummaryTime : null,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.history_outlined),
                  title: const Text('Past summaries'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(Routes.dailySummaries),
                ),
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
