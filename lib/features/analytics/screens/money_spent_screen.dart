import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/semantic_colors.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/report_charts.dart';
import '../../../core/widgets/report_controls.dart';
import '../../../core/widgets/report_table.dart';
import '../analytics_nav.dart';
import '../data/analytics_models.dart';
import '../data/analytics_repository.dart';
import '../presentation/analytics_text.dart';
import '../widgets/report_parts.dart';
import '../widgets/report_period.dart';

/// "Money spent": the total for a period, how it compares, day by day as a
/// bar chart or a table, what stands out and the payments themselves.
class MoneySpentScreen extends ConsumerStatefulWidget {
  const MoneySpentScreen({super.key, this.initial = PeriodSelection.defaultPeriod});

  final PeriodSelection initial;

  @override
  ConsumerState<MoneySpentScreen> createState() => _MoneySpentScreenState();
}

class _MoneySpentScreenState extends ConsumerState<MoneySpentScreen> {
  late PeriodSelection _period = widget.initial;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(analyticsSummaryProvider(_period));
    final data = async.valueOrNull;
    return Scaffold(
      appBar: AppBar(title: Text('analytics.title.spent'.tr())),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(analyticsSummaryProvider(_period));
          await ref.read(analyticsSummaryProvider(_period).future);
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
              error: (_, _) => [ErrorRetry(onRetry: () => ref.invalidate(analyticsSummaryProvider(_period)))],
              data: (s) => _body(context, s),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context, AnalyticsSummary s) {
    final today = _period.key == PeriodKey.today && _period.offset == 0;
    if (s.expenseCount == 0 && s.expense.minorUnits == 0) {
      // No zeros, charts or insights for an empty period.
      return [
        EmptyState(
          key: const ValueKey('report-empty'),
          icon: Icons.calendar_today_outlined,
          title: (today ? 'analytics.empty.todayTitle' : 'analytics.empty.periodTitle').tr(),
          body: 'analytics.empty.body'.tr(),
          actionLabel: 'analytics.empty.add'.tr(),
          onAction: () => context.push(Routes.addTransaction),
          secondaryLabel: today ? 'analytics.empty.seeWeek'.tr() : null,
          onSecondary: today ? () => setState(() => _period = const PeriodSelection(PeriodKey.thisWeek)) : null,
        ),
      ];
    }
    final series = s.series;
    final caption = [
      trPlural('analytics.paymentCount', s.expenseCount),
      if (_period.key != PeriodKey.today) 'analytics.avgPerDay'.tr(namedArgs: {'amount': moneyWords(s.averagePerDay)}),
    ].join(' · ');
    return [
      CoverageNote(period: s.period),
      const SizedBox(height: AppSpacing.lg),
      ReportHeadline(kicker: 'analytics.youSpent'.tr(), amount: s.expense, caption: caption),
      ComparisonFor(comparison: s.expenseComparison, period: s.period),
      if (s.topCategoriesShare != null && _period.key != PeriodKey.today)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Card(
            child: ListTile(
              key: const ValueKey('where-it-went'),
              minTileHeight: 60,
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                child: const Icon(Icons.pie_chart_outline, size: 20),
              ),
              title: Text('analytics.whereItWent'.tr(), style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('analytics.whereItWentSub'.tr(namedArgs: {'pct': '${s.topCategoriesShare}'})),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => AnalyticsNav.spending(context, _period),
            ),
          ),
        ),
      if (series != null && series.length > 1)
        _DayByDay(summary: s, series: series)
      else
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.lg),
          child: NoteRow(icon: Icons.info_outline, text: 'analytics.chartNeedsWeek'.tr()),
        ),
      InsightsSection(insights: s.insights, selection: _period, period: s.period),
      NeedMoreHistory(period: s.period, comparison: s.expenseComparison),
      ReportPayments(
        title: 'analytics.payments'.tr(),
        selection: _period,
        query: AnalyticsNav.query(_period, period: s.period, kind: ReportKind.expense),
        seeAllLabel: trPlural('analytics.seeAllPayments', s.expenseCount),
      ),
    ];
  }
}

/// Spending per day: bars (today hatched, the average dashed) or a table of
/// the same series whose total row equals the headline.
class _DayByDay extends ConsumerWidget {
  const _DayByDay({required this.summary, required this.series});

  final AnalyticsSummary summary;
  final List<SeriesPoint> series;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final table = ref.watch(reportTableViewProvider('spent'));
    final n = series.length;
    String dayLabel(SeriesPoint p) => n <= 7 ? 'common.weekdayShort.${p.date.weekday}'.tr() : fmtDay(p.date);
    String readout(SeriesPoint p) {
      final day = p.complete ? fmtWeekday(p.date) : '${fmtWeekday(p.date)} ${'analytics.readoutToday'.tr()}';
      return trPlural('analytics.readoutDay', p.count, {'date': day, 'amount': moneyWords(p.expense)});
    }

    final avg = summary.averagePerDay;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xl, bottom: AppSpacing.sm),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    'analytics.dayByDay'.tr(),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              ChartTableToggle(
                showTable: table,
                onChanged: (v) => ref.read(reportTableViewProvider('spent').notifier).state = v,
              ),
            ],
          ),
        ),
        if (!table) ...[
          MulindaBarChart(
            key: const ValueKey('day-chart'),
            hint: 'analytics.readoutHint'.tr(),
            average: avg.minorUnits > 0 ? avg.minorUnits.toDouble() : null,
            semanticsLabel: 'analytics.chartSemantics'.tr(namedArgs: {'days': '$n'}),
            bars: [
              for (final p in series)
                BarDatum(
                  value: p.expense.minorUnits.toDouble(),
                  label: dayLabel(p),
                  readout: readout(p),
                  partial: !p.complete,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.xs,
            children: [
              if (avg.minorUnits > 0)
                ChartLegendItem(dashed: true, label: 'analytics.dailyAverage'.tr(namedArgs: {'amount': moneyWords(avg)})),
              if (series.any((p) => !p.complete))
                ChartLegendItem(color: context.semantic.brandInk, hatched: true, label: 'analytics.todayNotOver'.tr()),
            ],
          ),
        ] else
          SizedBox(
            height: n > 8 ? 8 * AppSpacing.minTouch + 96 : null,
            child: SingleChildScrollView(
              primary: false,
              child: ReportTable(
                key: const ValueKey('day-table'),
                flex: const [5, 4, 3],
                columns: ['analytics.table.date'.tr(), 'analytics.table.spent'.tr(), 'analytics.table.payments'.tr()],
                rows: [
                  for (final p in series)
                    ReportTableRow(
                      cells: [
                        p.complete ? fmtWeekday(p.date) : '${fmtWeekday(p.date)} ${'analytics.soFarSuffix'.tr()}',
                        p.expense.whole,
                        '${p.count}',
                      ],
                    ),
                ],
                footer: ['analytics.table.total'.tr(), summary.expense.whole, '${summary.expenseCount}'],
              ),
            ),
          ),
      ],
    );
  }
}
