import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/bottom_action_bar.dart';
import '../../../core/widgets/info_row.dart';
import '../../auth/providers/auth_controller.dart';
import '../data/subscription_models.dart';

/// "Premium is on until ..." after a payment the server confirmed: the pass,
/// when it ends and what was paid. Nothing renews by itself.
class PassConfirmationScreen extends ConsumerWidget {
  const PassConfirmationScreen({super.key, required this.invoice, this.topUp = false});

  final InvoiceModel invoice;
  final bool topUp;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final sub = ref.watch(currentUserProvider)?.subscription ?? const SubscriptionInfo.none();
    final ends = sub.active ? sub.endsAt?.toLocal() : null;
    final locale = context.locale.languageCode;
    final passName = topUp
        ? 'upgrade.done.topUpLabel'.tr(namedArgs: {'plan': invoice.periodLabel})
        : invoice.periodLabel;

    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.xl),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: CircleAvatar(
                radius: 28,
                backgroundColor: scheme.primaryContainer,
                child: Icon(Icons.check_rounded, size: 30, color: scheme.onPrimaryContainer),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              ends == null
                  ? 'upgrade.done.titleNoDate'.tr()
                  : 'upgrade.done.title'.tr(namedArgs: {
                      'date': DateFormat.MMMMd(locale).add_Hm().format(ends),
                    }),
              key: const ValueKey('pass-confirmation-title'),
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'upgrade.done.body'.tr(),
              style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: AppSpacing.xl),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                child: Column(
                  children: [
                    InfoRow(label: 'upgrade.done.pass'.tr(), value: passName),
                    InfoRow(label: 'upgrade.done.paid'.tr(), value: invoice.amount.formatted),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomActionBar(
        label: Text('upgrade.done.cta'.tr()),
        onPressed: () => Navigator.of(context).pop(),
      ),
    );
  }
}
