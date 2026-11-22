import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/amount_text.dart';
import '../../../core/widgets/category_icons.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/report_charts.dart';
import '../../../core/widgets/report_controls.dart';
import '../../../core/widgets/report_table.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/stat_card.dart';
import '../analytics_nav.dart';
import '../data/analytics_models.dart';
import '../data/analytics_repository.dart';
import '../presentation/analytics_text.dart';
import '../widgets/report_parts.dart';
import '../widgets/report_period.dart';

/// One category over a period: total and share, how often and how much per
/// payment, the monthly trend, where the money went and the payments
/// themselves. Also used for income categories and for Uncategorised.
class CategoryDetailScreen extends ConsumerStatefulWidget {
  const CategoryDetailScreen({
    super.key,
    required this.categoryId,
    this.kind = ReportKind.expense,
    this.initial = PeriodSelection.defaultPeriod,
  });

  /// A category id or `uncategorised`.
  final String categoryId;
  final ReportKind kind;
  final PeriodSelection initial;

  @override
  ConsumerState<CategoryDetailScreen> createState() => _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends ConsumerState<CategoryDetailScreen> {
  late PeriodSelection _period = widget.initial;

  CategoryDetailKey get _key => (id: widget.categoryId, period: _period, kind: widget.kind);
  bool get _uncategorised => widget.categoryId == 'uncategorised';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(analyticsCategoryDetailProvider(_key));
    final d = async.valueOrNull;
    final name = d == null ? '' : categoryName(_uncategorised ? null : d.category?.name);
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(analyticsCategoryDetailProvider(_key));
          await ref.read(analyticsCategoryDetailProvider(_key).future);
        },
        child: ListView(
          padding: AppSpacing.screenPadding,
          children: [
            PeriodChip(selection: _period, period: d?.period, onChanged: (p) => setState(() => _period = p)),
            const SizedBox(height: AppSpacing.md),
            ...async.when(
              skipLoadingOnRefresh: true,
              loading: () => const [ReportLoading()],
              error: (e, _) => [
                if (e is ApiException && e.statusCode == 404)
                  EmptyState(icon: Icons.label_off_outlined, title: 'common.itemGone'.tr())
                else
                  ErrorRetry(onRetry: () => ref.invalidate(analyticsCategoryDetailProvider(_key))),
              ],
              data: (d) => _body(context, d, name),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context, CategoryDetail d, String name) {
    final scheme = Theme.of(context).colorScheme;
    final color = reportColor(context, d.category?.color, 0, uncategorised: _uncategorised);
    final income = d.kind == ReportKind.income;
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CategoryAvatar(
                    icon: d.category?.icon,
                    color: d.category?.color,
                    size: 48,
                    fallbackIcon: Icons.label_off_outlined,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: AmountText(
                            d.total,
                            key: const ValueKey('report-headline'),
                            whole: true,
                            signed: false,
                            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: scheme.onSurface),
                          ),
                        ),
                        Text(
                          [
                            (income ? 'analytics.cat.shareOfIncome' : 'analytics.cat.shareOfSpending').tr(
                              namedArgs: {'pct': '${d.sharePct}'},
                            ),
                            if (d.count < 2) trPlural('analytics.paymentCount', d.count),
                          ].join(' · '),
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Semantics(
                label: '${d.sharePct}%',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: LinearProgressIndicator(
                    value: (d.sharePct / 100).clamp(0.0, 1.0),
                    minHeight: 8,
                    color: color,
                    backgroundColor: scheme.surfaceContainerHigh,
                  ),
                ),
              ),
              ComparisonFor(comparison: d.comparison, period: d.period),
            ],
          ),
        ),
      ),
      if (d.count == 0)
        EmptyState(
          compact: true,
          icon: Icons.receipt_long_outlined,
          title: 'analytics.empty.categoryTitle'.tr(),
        )
      else ...[
        const SizedBox(height: AppSpacing.md),
        _stats(context, d, name),
        _trend(context, d, name, color),
        _merchants(context, d, color),
      ],
      InsightsSection(insights: d.insights, selection: _period, period: d.period, kind: d.kind),
      if (d.count > 0)
        ReportPayments(
          title: 'analytics.cat.paymentsTitle'.tr(namedArgs: {'category': name}),
          selection: _period,
          query: AnalyticsNav.query(
            _period,
            period: d.period,
            kind: d.kind,
            categoryId: _uncategorised ? null : widget.categoryId,
            uncategorised: _uncategorised,
          ),
          seeAllLabel: trPlural('analytics.seeAllCategoryPayments', d.count, {'category': name}),
        ),
    ];
  }

  Widget _stats(BuildContext context, CategoryDetail d, String name) {
    final scheme = Theme.of(context).colorScheme;
    if (d.highest == null && d.lowest == null && d.median == null) {
      return Column(
        children: [
          if (d.average != null && d.count >= 2)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: StatCard(icon: Icons.insights, label: 'analytics.cat.average'.tr(), value: d.average!.whole),
            ),
          NoteRow(
            key: const ValueKey('stats-need-two'),
            icon: Icons.insights,
            text: 'analytics.cat.statsNeedTwo'.tr(namedArgs: {'category': name}),
          ),
        ],
      );
    }
    String txnCaption(TxnRef t) =>
        [if (t.title.isNotEmpty) t.title, if (t.occurredAt != null) fmtDay(t.occurredAt!)].join(', ');
    Widget pair(Widget a, Widget b) => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [Expanded(child: a), const SizedBox(width: AppSpacing.md), Expanded(child: b)],
      ),
    );
    final typical = d.median != null
        ? StatCard(
            icon: Icons.insights,
            label: 'analytics.cat.typical'.tr(),
            value: d.median!.whole,
            caption: 'analytics.cat.halfLess'.tr(),
          )
        : StatCard(icon: Icons.insights, label: 'analytics.cat.average'.tr(), value: (d.average ?? d.total).whole);
    final averageNote = d.median != null && d.average != null
        ? (d.average!.minorUnits > d.median!.minorUnits * 1.25
              ? 'analytics.cat.avgHigher'.tr(namedArgs: {'amount': moneyWords(d.average)})
              : 'analytics.cat.avgPlain'.tr(namedArgs: {'amount': moneyWords(d.average)}))
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        pair(
          StatCard(icon: Icons.format_list_bulleted, label: 'analytics.cat.payments'.tr(), value: '${d.count}'),
          typical,
        ),
        if (d.highest != null || d.lowest != null) ...[
          const SizedBox(height: AppSpacing.md),
          pair(
            d.highest == null
                ? const SizedBox.shrink()
                : StatCard(
                    key: const ValueKey('stat-highest'),
                    icon: Icons.flag_outlined,
                    label: 'analytics.cat.highest'.tr(),
                    value: d.highest!.amount.whole,
                    caption: txnCaption(d.highest!),
                    onTap: () => AnalyticsNav.transaction(context, d.highest!.id, _period),
                  ),
            d.lowest == null
                ? const SizedBox.shrink()
                : StatCard(
                    key: const ValueKey('stat-lowest'),
                    icon: Icons.south,
                    label: 'analytics.cat.lowest'.tr(),
                    value: d.lowest!.amount.whole,
                    caption: txnCaption(d.lowest!),
                    onTap: () => AnalyticsNav.transaction(context, d.lowest!.id, _period),
                  ),
          ),
        ],
        if (averageNote != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm, left: AppSpacing.xxs),
            child: Text(averageNote, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ),
      ],
    );
  }

  Widget _trend(BuildContext context, CategoryDetail d, String name, Color color) {
    final trend = d.trend;
    if (trend == null || trend.points.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.md),
        child: NoteRow(
          key: const ValueKey('trend-needs-history'),
          icon: Icons.hourglass_bottom,
          text: 'analytics.cat.trendNeedsHistory'.tr(),
        ),
      );
    }
    final table = ref.watch(reportTableViewProvider('category-trend'));
    final points = trend.points;
    final complete = points.where((p) => p.complete).toList();
    final partial = points.where((p) => !p.complete).firstOrNull;
    String? story;
    if (complete.length >= 2) {
      final hi = complete.reduce((a, b) => b.amount.minorUnits > a.amount.minorUnits ? b : a);
      final lo = complete.reduce((a, b) => b.amount.minorUnits < a.amount.minorUnits ? b : a);
      story = d.steady == true
          ? 'analytics.cat.steady'.tr(
              namedArgs: {
                'category': name,
                'min': moneyWords(lo.amount),
                'max': moneyWords(hi.amount),
                'month': fmtMonthLong(complete.first.start),
              },
            )
          : 'analytics.cat.varied'.tr(
              namedArgs: {
                'category': name,
                'high': fmtMonthLong(hi.start),
                'highAmount': moneyWords(hi.amount),
                'low': fmtMonthLong(lo.start),
                'lowAmount': moneyWords(lo.amount),
              },
            );
    }
    String readout(TrendPoint p) => trPlural('analytics.cat.readout', p.count, {
      'month': p.complete ? fmtMonthShort(p.start) : 'analytics.cat.soFarShort'.tr(namedArgs: {'month': fmtMonthShort(p.start)}),
      'amount': moneyWords(p.amount),
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChartSectionHeader(
          title: 'analytics.cat.byMonth'.tr(namedArgs: {'category': name}),
          showTable: table,
          onChanged: (v) => ref.read(reportTableViewProvider('category-trend').notifier).state = v,
        ),
        if (!table) ...[
          if (story != null)
            Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: Text(story, key: const ValueKey('trend-story'))),
          MulindaLineChart(
            key: const ValueKey('trend-chart'),
            color: color,
            currency: d.total.currency,
            semanticsLabel: [for (final p in points) readout(p)].join('. '),
            points: [
              for (final p in points)
                LinePointDatum(
                  minorUnits: p.amount.minorUnits,
                  label: fmtMonthShort(p.start),
                  readout: readout(p),
                  partial: !p.complete,
                ),
            ],
          ),
          if (partial != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: ChartLegendItem(
                color: color,
                dashed: true,
                label: 'analytics.cat.soFarLegend'.tr(namedArgs: {'month': fmtMonthLong(partial.start)}),
              ),
            ),
        ] else
          ReportTable(
            key: const ValueKey('trend-table'),
            flex: const [4, 4, 3],
            columns: ['analytics.table.month'.tr(), name, 'analytics.table.payments'.tr()],
            rows: [
              for (final p in points)
                ReportTableRow(
                  cells: [
                    p.complete ? fmtMonthLong(p.start) : '${fmtMonthLong(p.start)} ${'analytics.soFarSuffix'.tr()}',
                    p.amount.whole,
                    '${p.count}',
                  ],
                ),
            ],
          ),
      ],
    );
  }

  Widget _merchants(BuildContext context, CategoryDetail d, Color color) {
    if (d.merchants.isEmpty) return const SizedBox.shrink();
    final income = d.kind == ReportKind.income;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader((income ? 'analytics.cat.whoFrom' : 'analytics.cat.whereSpent').tr()),
          for (final m in d.merchants)
            CategoryShareRow(
              key: ValueKey('merchant-${m.name ?? 'other'}'),
              name: m.name ?? 'analytics.cat.otherPlaces'.tr(),
              amount: m.amount,
              sharePct: m.sharePct,
              subtitle: trPlural('analytics.paymentCount', m.count),
              color: color,
              icon: d.category?.icon,
              onTap: m.name == null
                  ? null
                  : () => AnalyticsNav.activity(
                      context,
                      ref,
                      AnalyticsNav.query(
                        _period,
                        period: d.period,
                        kind: d.kind,
                        categoryId: _uncategorised ? null : widget.categoryId,
                        uncategorised: _uncategorised,
                        merchant: m.name,
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}
