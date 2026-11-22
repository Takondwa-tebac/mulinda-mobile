import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/router/routes.dart';
import 'package:go_router/go_router.dart';
import '../data/analytics_models.dart';
import '../data/analytics_repository.dart';
import '../presentation/analytics_text.dart';
import '../widgets/report_parts.dart';
import '../widgets/report_period.dart';

/// "Where your money is going": spending by category for a period, as a
/// donut with rows or as a table. Every row opens Category detail.
class WhereMoneyGoesScreen extends ConsumerStatefulWidget {
  const WhereMoneyGoesScreen({super.key, this.initial = PeriodSelection.defaultPeriod});

  final PeriodSelection initial;

  @override
  ConsumerState<WhereMoneyGoesScreen> createState() => _WhereMoneyGoesScreenState();
}

class _WhereMoneyGoesScreenState extends ConsumerState<WhereMoneyGoesScreen> {
  late PeriodSelection _period = widget.initial;

  BreakdownKey get _key => (period: _period, kind: ReportKind.expense);

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(analyticsCategoriesProvider(_key));
    final data = async.valueOrNull;
    return Scaffold(
      appBar: AppBar(title: Text('analytics.title.where'.tr())),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(analyticsCategoriesProvider(_key));
          await ref.read(analyticsCategoriesProvider(_key).future);
        },
        child: ListView(
          padding: AppSpacing.screenPadding,
          children: [
            ReportPeriodBar(
              selection: _period,
              period: data?.period,
              onChanged: (p) => setState(() => _period = p),
            ),
            ...async.when(
              skipLoadingOnRefresh: true,
              skipLoadingOnReload: false,
              loading: () => const [ReportLoading()],
              error: (_, _) => [ErrorRetry(onRetry: () => ref.invalidate(analyticsCategoriesProvider(_key)))],
              data: (b) => _body(context, b),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context, CategoryBreakdown b) {
    final scheme = Theme.of(context).colorScheme;
    if (b.isEmpty) {
      return [
        EmptyState(
          key: const ValueKey('report-empty'),
          icon: Icons.donut_large,
          title: 'analytics.empty.periodTitle'.tr(),
          body: 'analytics.empty.body'.tr(),
          actionLabel: 'analytics.empty.add'.tr(),
          onAction: () => context.push(Routes.addTransaction),
        ),
      ];
    }
    final notCounted = b.notCounted;
    return [
      CoverageNote(period: b.period),
      const SizedBox(height: AppSpacing.lg),
      ReportHeadline(
        kicker: 'analytics.youSpent'.tr(),
        amount: b.total,
        caption: trPlural('analytics.acrossPayments', b.count, {'when': periodWhen(_period, b.period)}),
      ),
      ComparisonFor(comparison: b.comparison, period: b.period),
      BreakdownView(
        breakdown: b,
        selection: _period,
        reportId: 'where',
        title: 'analytics.byCategory'.tr(),
      ),
      InsightsSection(insights: b.insights, selection: _period, period: b.period),
      NeedMoreHistory(period: b.period, comparison: b.comparison),
      const SizedBox(height: AppSpacing.lg),
      Text(
        notCounted.count > 0
            ? 'analytics.notCountedSpending'.tr(namedArgs: {'amount': moneyWords(notCounted.amount)})
            : 'analytics.footnote.fees'.tr(),
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      ),
      if (notCounted.count > 0)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Text(
            'analytics.footnote.feesShort'.tr(),
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ),
    ];
  }
}
