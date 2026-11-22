import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/amount_text.dart';
import '../../../core/widgets/donut_chart.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/report_controls.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/report_table.dart';
import '../analytics_nav.dart';
import '../data/analytics_models.dart';
import '../data/analytics_repository.dart';
import '../presentation/analytics_text.dart';
import 'report_parts.dart';
import 'report_period.dart';

/// Home's answer to "how did my last 30 days go?": one sentence, four
/// figures that each open their report, and the spending comparison. Driven
/// by `/analytics/summary` for the period chosen on the chip.
class HomeAnalyticsHero extends ConsumerWidget {
  const HomeAnalyticsHero({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(homePeriodProvider);
    final async = ref.watch(analyticsSummaryProvider(selection));
    final scheme = Theme.of(context).colorScheme;
    return async.when(
      skipLoadingOnRefresh: true,
      loading: () => const SkeletonBox(key: ValueKey('home-hero-loading'), height: 260, radius: AppRadius.xl),
      error: (_, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: ErrorRetry(
            compact: true,
            message: 'analytics.home.loadError'.tr(),
            onRetry: () => ref.invalidate(analyticsSummaryProvider(selection)),
          ),
        ),
      ),
      data: (s) => _Hero(summary: s, selection: selection, on: scheme.onPrimary, background: scheme.primary),
    );
  }
}

class _Hero extends ConsumerWidget {
  const _Hero({required this.summary, required this.selection, required this.on, required this.background});

  final AnalyticsSummary summary;
  final PeriodSelection selection;
  final Color on;
  final Color background;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = summary;
    final text = Theme.of(context).textTheme;
    final headline = s.isEmpty
        ? 'analytics.home.nothingYet'.tr()
        : s.income.minorUnits <= 0
        ? null
        : s.net.minorUnits < 0
        ? 'analytics.home.spentMore'.tr()
        : 'analytics.home.leftOver'.tr(namedArgs: {'amount': moneyWords(s.net)});
    final biggest = s.biggestExpense;

    return Container(
      key: const ValueKey('home-analytics-hero'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(AppRadius.xl)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: on.withValues(alpha: 0.10),
            borderRadius: AppRadius.chip,
            child: InkWell(
              key: const ValueKey('home-period-chip'),
              borderRadius: AppRadius.chip,
              onTap: () async {
                final picked = await showPeriodSheet(context, selection);
                if (picked != null) ref.read(homePeriodProvider.notifier).state = picked;
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          periodTitle(selection, s.period),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: on, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Icon(Icons.expand_more, size: 18, color: on),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (headline != null)
            Text(
              headline,
              key: const ValueKey('home-headline'),
              style: text.titleLarge?.copyWith(color: on, fontWeight: FontWeight.w800, height: 1.25),
            ),
          Text(periodRange(s.period), style: TextStyle(color: on, fontSize: 13)),
          const SizedBox(height: AppSpacing.md),
          Container(height: 1, color: on.withValues(alpha: 0.2)),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _Figure(
                  key: const ValueKey('home-fig-received'),
                  on: on,
                  label: 'analytics.home.received'.tr(),
                  value: s.income,
                  onTap: () => AnalyticsNav.received(context, selection),
                ),
              ),
              Expanded(
                child: _Figure(
                  key: const ValueKey('home-fig-spent'),
                  on: on,
                  label: 'analytics.home.spent'.tr(),
                  value: s.expense,
                  onTap: () => AnalyticsNav.spent(context, selection),
                ),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Figure(
                  key: const ValueKey('home-fig-count'),
                  on: on,
                  label: 'analytics.home.transactions'.tr(),
                  text: '${s.totalCount}',
                  caption: 'analytics.home.outIn'.tr(namedArgs: {'out': '${s.expenseCount}', 'in': '${s.incomeCount}'}),
                  onTap: () => AnalyticsNav.activity(context, ref, AnalyticsNav.query(selection, period: s.period)),
                ),
              ),
              Expanded(
                child: biggest == null
                    ? const SizedBox.shrink()
                    : _Figure(
                        key: const ValueKey('home-fig-biggest'),
                        on: on,
                        label: 'analytics.home.biggestExpense'.tr(),
                        value: biggest.amount,
                        caption: [
                          if (biggest.title.isNotEmpty) biggest.title,
                          if (biggest.occurredAt != null) fmtDay(biggest.occurredAt!),
                        ].join(', '),
                        onTap: () => AnalyticsNav.transaction(context, biggest.id, selection),
                      ),
              ),
            ],
          ),
          ComparisonFor(comparison: s.expenseComparison, period: s.period, hero: true, color: on),
        ],
      ),
    );
  }
}

/// A tappable figure on the hero (at least 56 px tall).
class _Figure extends StatelessWidget {
  const _Figure({super.key, required this.on, required this.label, this.value, this.text, this.caption, required this.onTap});

  final Color on;
  final String label;
  final Money? value;
  final String? text;
  final String? caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final valueText = value?.whole ?? text ?? '';
    return Semantics(
      button: true,
      label: [label, valueText, if (caption != null && caption!.isNotEmpty) caption!].join(', '),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.xxs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(label, style: TextStyle(color: on, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    Icon(Icons.chevron_right, size: 16, color: on),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: value != null
                      ? AmountText(
                          value!,
                          whole: true,
                          signed: false,
                          style: TextStyle(color: on, fontSize: 18, fontWeight: FontWeight.w800),
                        )
                      : Text(valueText, style: TextStyle(color: on, fontSize: 18, fontWeight: FontWeight.w800)),
                ),
                if (caption != null && caption!.isNotEmpty)
                  Text(caption!, style: TextStyle(color: on, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The compact "Where your money is going": total, the top-three share, a
/// small donut and the top three rows. "See all" opens the full report.
class HomeWhereCard extends ConsumerWidget {
  const HomeWhereCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(homePeriodProvider);
    final async = ref.watch(analyticsCategoriesProvider((period: selection, kind: ReportKind.expense)));
    return async.maybeWhen(
      skipLoadingOnRefresh: true,
      orElse: () => const SizedBox.shrink(),
      data: (b) => b.isEmpty || b.rows.isEmpty && b.others == null
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: _WhereCard(breakdown: b, selection: selection),
            ),
    );
  }
}

class _WhereCard extends ConsumerWidget {
  const _WhereCard({required this.breakdown, required this.selection});

  final CategoryBreakdown breakdown;
  final PeriodSelection selection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = breakdown;
    final scheme = Theme.of(context).colorScheme;
    final rows = b.rows;
    final top = rows.take(3).toList();
    final more = rows.length - top.length + (b.others == null ? 0 : 1);
    final colors = [
      for (var i = 0; i < rows.length; i++) reportColor(context, rows[i].color, i, uncategorised: rows[i].isUncategorised),
    ];
    final share = summaryTopShare(ref, selection);
    final spent = 'analytics.home.spentSentence'.tr(
      namedArgs: {'amount': moneyWords(b.total), 'when': periodWhen(selection, b.period)},
    );
    final change = b.insights.where((i) => i.key == 'categoryUp' || i.key == 'categoryDown').firstOrNull;
    final changeWords = change == null ? null : insightWords(change, period: b.period);

    return Card(
      key: const ValueKey('home-where-card'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              'analytics.title.where'.tr(),
              padding: EdgeInsets.zero,
              actionLabel: 'analytics.seeAll'.tr(),
              onAction: () => AnalyticsNav.spending(context, selection),
            ),
            Text(
              [spent, if (share != null && rows.length >= 3) 'analytics.home.topThree'.tr(namedArgs: {'pct': '$share'})].join(' '),
              style: const TextStyle(height: 1.35),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                DonutChart(
                  size: 132,
                  stroke: 14,
                  semanticsLabel: [
                    for (final r in rows) '${categoryName(r.name)} ${r.sharePct}%',
                    if (b.others != null) '${'analytics.others'.tr()} ${b.others!.sharePct}%',
                  ].join(', '),
                  slices: [
                    for (var i = 0; i < rows.length; i++)
                      DonutSlice(value: rows[i].amount.minorUnits.toDouble(), color: colors[i]),
                    if (b.others != null)
                      DonutSlice(value: b.others!.amount.minorUnits.toDouble(), color: othersColor(context), hatched: true),
                  ],
                  center: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AmountText(b.total, whole: true, signed: false, style: TextStyle(fontSize: 13, color: scheme.onSurface)),
                      Text('analytics.home.spentLabel'.tr(), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < top.length; i++)
                        InkWell(
                          key: ValueKey('home-where-row-${top[i].routeId}'),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          onTap: () => AnalyticsNav.category(context, top[i].routeId, selection),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: AppSpacing.minTouch),
                            child: Row(
                              children: [
                                SizedBox.square(
                                  dimension: 10,
                                  child: CustomPaint(painter: HatchSwatchPainter(color: colors[i])),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Text(
                                    categoryName(top[i].name),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                                Text('${top[i].sharePct}%', style: const TextStyle(fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ),
                      if (more > 0)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            key: const ValueKey('home-where-more'),
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(AppSpacing.minTouch, AppSpacing.minTouch),
                            ),
                            onPressed: () => AnalyticsNav.spending(context, selection),
                            child: Text('analytics.moreCategories'.tr(namedArgs: {'count': '$more'})),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (changeWords != null)
              ComparisonLine(
                trend: change!.key == 'categoryUp' ? ComparisonTrend.up : ComparisonTrend.down,
                text: changeWords.title,
                fontSize: 13,
              ),
          ],
        ),
      ),
    );
  }

  /// The top-three share comes with the summary (`top_categories_share`).
  static int? summaryTopShare(WidgetRef ref, PeriodSelection selection) =>
      ref.watch(analyticsSummaryProvider(selection)).valueOrNull?.topCategoriesShare;
}

/// "Money in your accounts": the account balances (was "Net worth").
class MoneyInAccountsRow extends StatelessWidget {
  const MoneyInAccountsRow({super.key, required this.amount, this.accounts, required this.onTap});

  final Money amount;
  final int? accounts;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: const ValueKey('home-money-in-accounts'),
      child: InkWell(
        borderRadius: AppRadius.card,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.onPrimaryContainer,
                  child: const Icon(Icons.account_balance_wallet_outlined, size: 18),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('analytics.home.moneyInAccounts'.tr(), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                      AmountText(amount, signed: false, style: TextStyle(fontSize: 16, color: scheme.onSurface)),
                    ],
                  ),
                ),
                if (accounts != null && accounts! > 0)
                  Text(trPlural('analytics.home.accounts', accounts!), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                const SizedBox(width: AppSpacing.xs),
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
