import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../auth/providers/auth_controller.dart';
import '../../subscription/data/subscription_models.dart';
import '../../subscription/widgets/premium_lock.dart';
import '../data/plan_models.dart';
import '../data/plan_repository.dart';

class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final advisory = ref.watch(advisoryProvider);
    final text = Theme.of(context).textTheme;
    // Advisory (savings-rule / creditworthiness / investing) is premium.
    final canSeeAdvisory =
        ref.watch(currentUserProvider)?.can(Entitlements.advancedInsights) ?? false;

    return Scaffold(
      appBar: AppBar(title: Text('nav.plan'.tr())),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(advisoryProvider);
          await ref.read(advisoryProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            Text('plan.advisory'.tr(), style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            if (!canSeeAdvisory)
              PremiumUpsellCard(
                title: 'plan.advisoryLockedTitle'.tr(),
                message: 'plan.advisoryLockedMessage'.tr(),
                icon: Icons.insights_rounded,
                compact: true,
              )
            else
              advisory.when(
                loading: () => const _AdvisoryLoading(),
                error: (_, _) => const SizedBox.shrink(),
                data: (a) => _Advisory(summary: a),
              ),
            const SizedBox(height: 24),
            ..._tiles(context),
          ],
        ),
      ),
    );
  }

  List<Widget> _tiles(BuildContext context) {
    final items = [
      (Icons.flag_outlined, 'plan.goals', Routes.goals),
      (Icons.pie_chart_outline, 'plan.budgets', Routes.budgets),
      (Icons.account_balance_outlined, 'plan.loans', Routes.loans),
      (Icons.trending_up, 'plan.investments', Routes.investments),
      (Icons.home_work_outlined, 'plan.projects', Routes.projects),
    ];
    return items.map((it) {
      final (icon, key, route) = it;
      return Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
          title: Text(key.tr(), style: const TextStyle(fontWeight: FontWeight.w600)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(route),
        ),
      );
    }).toList();
  }
}

class _Advisory extends StatelessWidget {
  const _Advisory({required this.summary});
  final AdvisorySummary summary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reco = summary.investRecommendation;
    final posture = summary.riskPosture;
    final target = summary.targetRate;

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _Card(
              label: 'plan.savingsRule'.tr(),
              value: summary.savingsRuleName ?? '–',
              sub: summary.savingsOnTrack == null
                  ? null
                  : (summary.savingsOnTrack! ? 'plan.onTrack'.tr() : 'plan.offTrack'.tr()),
              subColor: summary.savingsOnTrack == true ? scheme.primary : scheme.error,
              icon: Icons.savings_rounded,
            )),
            const SizedBox(width: 12),
            Expanded(child: _Card(
              label: 'plan.creditworthiness'.tr(),
              value: summary.creditScore?.toString() ?? '–',
              sub: summary.creditBand,
              icon: Icons.verified_rounded,
            )),
          ],
        ),
        const SizedBox(height: 12),
        _Card(
          label: 'plan.investing'.tr(),
          value: reco == null ? '–' : 'plan.reco.$reco'.tr(),
          sub: posture == null ? null : 'plan.posture.$posture'.tr(),
          icon: Icons.insights_rounded,
          wide: true,
          extra: target == null ? null : '${(target * 100).toStringAsFixed(0)}%',
        ),
        const SizedBox(height: 8),
        Text('plan.notAdvice'.tr(),
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.label,
    required this.value,
    this.sub,
    this.subColor,
    required this.icon,
    this.wide = false,
    this.extra,
  });

  final String label;
  final String value;
  final String? sub;
  final Color? subColor;
  final IconData icon;
  final bool wide;
  final String? extra;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant))),
              if (extra != null) Text(extra!, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 8),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800)),
          if (sub != null)
            Text(sub!, style: TextStyle(fontSize: 12, color: subColor ?? scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _AdvisoryLoading extends StatelessWidget {
  const _AdvisoryLoading();
  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 90,
        child: Center(child: CircularProgressIndicator()),
      );
}
