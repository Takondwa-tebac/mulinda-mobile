import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/amount_text.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/report_controls.dart';
import '../../../core/widgets/section_header.dart';
import '../analytics_nav.dart';
import '../data/analytics_models.dart';
import '../data/analytics_repository.dart';
import '../presentation/analytics_text.dart';
import '../widgets/report_parts.dart';
import '../widgets/report_period.dart';

/// "Money received": income by source for a period, who sent it, what was
/// left out (money moved between the user's own accounts) and the payments.
class MoneyReceivedScreen extends ConsumerStatefulWidget {
  const MoneyReceivedScreen({super.key, this.initial = PeriodSelection.defaultPeriod});

  final PeriodSelection initial;

  @override
  ConsumerState<MoneyReceivedScreen> createState() => _MoneyReceivedScreenState();
}

class _MoneyReceivedScreenState extends ConsumerState<MoneyReceivedScreen> {
  late PeriodSelection _period = widget.initial;

  BreakdownKey get _key => (period: _period, kind: ReportKind.income);

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(analyticsCategoriesProvider(_key));
    final data = async.valueOrNull;
    return Scaffold(
      appBar: AppBar(title: Text('analytics.title.received'.tr())),
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
    final income = incomeColor(context);
    final notCounted = b.notCounted;
    final notCountedNote = notCounted.count > 0
        ? Padding(
            padding: const EdgeInsets.only(top: AppSpacing.lg),
            child: NoteRow(
              key: const ValueKey('not-counted'),
              icon: Icons.swap_horiz,
              text: 'analytics.notCountedIncome'.tr(namedArgs: {'amount': moneyWords(notCounted.amount)}),
              body: 'analytics.notCountedIncomeBody'.tr(),
            ),
          )
        : null;
    if (b.isEmpty) {
      return [
        EmptyState(
          key: const ValueKey('report-empty'),
          icon: Icons.south_west,
          title: 'analytics.empty.receivedTitle'.tr(),
          body: 'analytics.empty.receivedBody'.tr(),
        ),
        ?notCountedNote,
      ];
    }
    return [
      CoverageNote(period: b.period),
      const SizedBox(height: AppSpacing.lg),
      ReportHeadline(
        kicker: 'analytics.youReceived'.tr(),
        amount: b.total,
        color: income,
        caption: trPlural('analytics.fromPayments', b.count, {'when': periodWhen(_period, b.period)}),
      ),
      ComparisonFor(comparison: b.comparison, period: b.period),
      BreakdownView(breakdown: b, selection: _period, reportId: 'received', title: 'analytics.bySource'.tr()),
      ?notCountedNote,
      InsightsSection(insights: b.insights, selection: _period, period: b.period, kind: ReportKind.income),
      NeedMoreHistory(period: b.period, comparison: b.comparison),
      if (b.parties.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.xl),
        SectionHeader('analytics.whoSentIt'.tr()),
        for (final p in b.parties)
          ListTile(
            key: ValueKey('party-${p.name}'),
            minTileHeight: 56,
            contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(trPlural('analytics.paymentCount', p.count)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AmountText(p.amount, whole: true, signed: false, style: TextStyle(color: income)),
                const SizedBox(width: AppSpacing.xs),
                const Icon(Icons.chevron_right, size: 20),
              ],
            ),
            onTap: () => AnalyticsNav.activity(
              context,
              ref,
              AnalyticsNav.query(_period, period: b.period, kind: ReportKind.income, merchant: p.name),
            ),
          ),
      ],
      ReportPayments(
        title: 'analytics.paymentsIn'.tr(),
        selection: _period,
        query: AnalyticsNav.query(_period, period: b.period, kind: ReportKind.income),
        seeAllLabel: trPlural('analytics.seeAllPayments', b.count),
      ),
    ];
  }
}
