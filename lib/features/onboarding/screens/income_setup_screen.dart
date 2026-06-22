import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/permissions/permission_service.dart';
import '../../auth/providers/auth_controller.dart';

/// First-run: the user declares their monthly income band, which drives the
/// backend's bracket-adaptive savings rules, health score, and advice.
class IncomeSetupScreen extends ConsumerStatefulWidget {
  const IncomeSetupScreen({super.key});

  @override
  ConsumerState<IncomeSetupScreen> createState() => _IncomeSetupScreenState();
}

class _IncomeSetupScreenState extends ConsumerState<IncomeSetupScreen> {
  // Values match the API IncomeBracket enum.
  static const _bands = [
    ('low', 'income.low'),
    ('lower_middle', 'income.lowerMiddle'),
    ('middle', 'income.middle'),
    ('upper_middle', 'income.upperMiddle'),
    ('upper', 'income.upper'),
  ];

  String? _selected;
  bool _loading = false;

  Future<void> _continue() async {
    final band = _selected;
    if (band == null) return;
    setState(() => _loading = true);

    // First-run is a natural moment to ask for notification permission
    // (bill & loan-repayment reminders). Best-effort, never blocks.
    await ref.read(permissionServiceProvider).requestNotifications();

    try {
      await ref.read(authControllerProvider.notifier).setIncomeBracket(band);
      // Router guard routes to home once the bracket is set.
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.displayMessage)));
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('income.title'.tr(),
                      style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  Text('income.subtitle'.tr(),
                      style: text.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                itemCount: _bands.length,
                itemBuilder: (_, i) {
                  final (value, key) = _bands[i];
                  return _BandTile(
                    label: '$key.label'.tr(),
                    range: '$key.range'.tr(),
                    selected: _selected == value,
                    onTap: () => setState(() => _selected = value),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: FilledButton(
                onPressed: (_selected == null || _loading) ? null : _continue,
                child: _loading
                    ? SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      )
                    : Text('common.continue'.tr()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BandTile extends StatelessWidget {
  const _BandTile({
    required this.label,
    required this.range,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String range;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
                        )),
                    const SizedBox(height: 2),
                    Text(range,
                        style: TextStyle(
                          color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                        )),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: selected ? scheme.primary : scheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
