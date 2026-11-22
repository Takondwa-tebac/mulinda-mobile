import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/chart_tone.dart';
import '../../../core/theme/semantic_colors.dart';
import '../../../core/widgets/amount_text.dart';
import '../../../core/widgets/category_icons.dart';
import '../../../core/widgets/donut_chart.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/report_controls.dart';
import '../../../core/widgets/report_table.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../core/widgets/transaction_tile.dart';
import '../../activity/data/activity_models.dart';
import '../../activity/widgets/txn_view.dart';
import '../analytics_nav.dart';
import '../data/analytics_models.dart';
import '../data/analytics_repository.dart';
import '../presentation/analytics_text.dart';

/// A category's chart colour, toned to reach 3:1 on the card in this theme.
/// Without a colour from the server: the outline grey for Uncategorised, the
/// category palette by position for anything else.
Color reportColor(BuildContext context, String? hex, int index, {bool uncategorised = false}) {
  final scheme = Theme.of(context).colorScheme;
  final base =
      parseHexColor(hex) ??
      (uncategorised ? scheme.outline : parseHexColor(categoryColorChoices[index % categoryColorChoices.length])!);
  return context.chartToneOf(base);
}

/// The stripe colour of "Everything else".
Color othersColor(BuildContext context) => context.chartToneOf(Theme.of(context).colorScheme.outline);

ComparisonTrend _trend(ComparisonIcon icon) => switch (icon) {
  ComparisonIcon.up => ComparisonTrend.up,
  ComparisonIcon.down => ComparisonTrend.down,
  ComparisonIcon.same => ComparisonTrend.same,
  ComparisonIcon.info => ComparisonTrend.info,
};

/// A comparison as a [ComparisonLine]; nothing when there is nothing to say.
class ComparisonFor extends StatelessWidget {
  const ComparisonFor({super.key, required this.comparison, required this.period, this.hero = false, this.color});

  final Comparison comparison;
  final AnalyticsPeriod period;
  final bool hero;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final words = comparisonWords(comparison, period, hero: hero);
    if (words == null) return const SizedBox.shrink();
    return ComparisonLine(
      key: const ValueKey('comparison-line'),
      trend: _trend(words.icon),
      text: words.text,
      color: color,
      fontSize: hero ? 13 : 14,
    );
  }
}

/// "You spent / MK 285,400 / in the last 30 days, across 76 payments".
class ReportHeadline extends StatelessWidget {
  const ReportHeadline({super.key, required this.kicker, required this.amount, required this.caption, this.color});

  final String kicker;
  final Money amount;
  final String caption;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(kicker, style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: AmountText(
            amount,
            key: const ValueKey('report-headline'),
            whole: true,
            signed: false,
            style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: color ?? scheme.onSurface),
          ),
        ),
        Text(caption, style: TextStyle(color: scheme.onSurfaceVariant)),
      ],
    );
  }
}

/// "We have 6 days of your transactions so far (since 17 Nov), so this may
/// not be the full picture." Shown when history starts inside the period.
class CoverageNote extends StatelessWidget {
  const CoverageNote({super.key, required this.period});

  final AnalyticsPeriod period;

  @override
  Widget build(BuildContext context) {
    final since = period.coverageFrom;
    if (!period.partlyCovered || since == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final end = period.to == null || period.to!.isAfter(today) ? today : period.to!;
    final days = end.difference(since).inDays + 1;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: NoteRow(
        key: const ValueKey('coverage-note'),
        icon: Icons.hourglass_bottom,
        text: trPlural('analytics.coverage', days < 1 ? 1 : days, {'date': fmtDay(since)}),
      ),
    );
  }
}

/// "You need more history before we can spot a pattern", when comparisons are
/// held back for lack of history.
class NeedMoreHistory extends StatelessWidget {
  const NeedMoreHistory({super.key, required this.period, required this.comparison});

  final AnalyticsPeriod period;
  final Comparison comparison;

  @override
  Widget build(BuildContext context) {
    if (!comparison.insufficientHistory) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final since = period.coverageFrom;
    final rolling = period.key == PeriodKey.last30Days || period.key == PeriodKey.custom;
    // Comparable once the previous window is covered too: twice the length.
    final body = rolling && since != null && period.days > 0
        ? 'analytics.needMoreHistoryBody'.tr(
            namedArgs: {
              'days': '${period.days * 2}',
              'date': fmtDay(since.add(Duration(days: period.days * 2 - 1))),
            },
          )
        : 'analytics.needMoreHistoryBodyGeneric'.tr();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        key: const ValueKey('need-more-history'),
        children: [
          ExcludeSemantics(
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
              child: Icon(Icons.hourglass_bottom, color: scheme.onPrimaryContainer),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'analytics.needMoreHistory'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(body, textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// "What stands out": up to three server insights, worded by the app.
class InsightsSection extends ConsumerWidget {
  const InsightsSection({
    super.key,
    required this.insights,
    required this.selection,
    required this.period,
    this.kind = ReportKind.expense,
  });

  final List<Insight> insights;
  final PeriodSelection selection;
  final AnalyticsPeriod period;
  final ReportKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = [
      for (final i in insights)
        if (insightWords(i, period: period, kind: kind) case final w?) (i, w),
    ];
    if (shown.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader('analytics.whatStandsOut'.tr()),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
              child: Column(
                children: [
                  for (final (insight, words) in shown)
                    InsightTile(
                      key: ValueKey('insight-${insight.key}'),
                      icon: words.icon,
                      title: words.title,
                      body: words.body,
                      actionLabel: words.actionLabel,
                      onAction: words.actionLabel == null
                          ? null
                          : () => AnalyticsNav.insight(context, ref, insight, selection, kind: kind),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A category with its amount, share and a bar of its share. Opens Category
/// detail.
class CategoryShareRow extends StatelessWidget {
  const CategoryShareRow({
    super.key,
    required this.name,
    required this.amount,
    required this.sharePct,
    required this.subtitle,
    required this.color,
    this.icon,
    this.hatched = false,
    this.showBar = true,
    this.needsCategory = false,
    this.onTap,
    this.trailingIcon = Icons.chevron_right,
  });

  final String name;
  final Money amount;
  final int sharePct;
  final String subtitle;
  final Color color;
  final String? icon;
  final bool hatched;
  final bool showBar;
  final bool needsCategory;
  final VoidCallback? onTap;
  final IconData trailingIcon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: onTap != null,
      label: '$name, ${amount.whole}, $sharePct%, $subtitle',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.xs),
            child: Row(
              children: [
                if (hatched)
                  SizedBox.square(
                    dimension: 36,
                    child: ClipOval(child: CustomPaint(painter: HatchSwatchPainter(color: color, hatched: true))),
                  )
                else
                  CategoryAvatar(icon: icon, color: '#${color.toARGB32().toRadixString(16).padLeft(8, '0')}', size: 36),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                      Text(subtitle, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                      if (needsCategory) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        StatusChip(label: 'analytics.needsCategory'.tr(), tone: StatusTone.warning),
                      ],
                      if (showBar) ...[
                        const SizedBox(height: AppSpacing.xs),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: SizedBox(
                            height: 6,
                            child: Stack(
                              children: [
                                Positioned.fill(child: ColoredBox(color: scheme.surfaceContainerHigh)),
                                FractionallySizedBox(
                                  widthFactor: (sharePct / 100).clamp(0.0, 1.0),
                                  child: hatched
                                      ? CustomPaint(
                                          painter: HatchSwatchPainter(color: color, hatched: true),
                                          size: Size.infinite,
                                        )
                                      : ColoredBox(color: color),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    AmountText(amount, whole: true, signed: false, style: TextStyle(color: scheme.onSurface)),
                    Text('$sharePct%', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  ],
                ),
                if (onTap != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Icon(trailingIcon, size: 20, color: scheme.onSurfaceVariant),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Donut and rows, or the same rows as a table, for a category breakdown.
/// Chart and table always show the same rows; the table total equals the
/// headline.
class BreakdownView extends ConsumerStatefulWidget {
  const BreakdownView({
    super.key,
    required this.breakdown,
    required this.selection,
    required this.reportId,
    required this.title,
  });

  final CategoryBreakdown breakdown;
  final PeriodSelection selection;

  /// Remembers Chart or Table for this report.
  final String reportId;
  final String title;

  @override
  ConsumerState<BreakdownView> createState() => _BreakdownViewState();
}

class _BreakdownViewState extends ConsumerState<BreakdownView> {
  bool _othersOpen = false;

  void _open(CategoryRow r) =>
      AnalyticsNav.category(context, r.routeId, widget.selection, kind: widget.breakdown.kind);

  String _payments(int n) => trPlural('analytics.paymentCount', n);

  @override
  Widget build(BuildContext context) {
    final b = widget.breakdown;
    final table = ref.watch(reportTableViewProvider(widget.reportId));
    final rows = b.rows;
    final others = b.others;
    final colors = [
      for (var i = 0; i < rows.length; i++) reportColor(context, rows[i].color, i, uncategorised: rows[i].isUncategorised),
    ];
    final hatch = othersColor(context);
    final countLabel = _payments(b.count);
    final label = [
      for (final r in rows) '${categoryName(r.name)} ${r.sharePct}%',
      if (others != null) '${'analytics.others'.tr()} ${others.sharePct}%',
    ].join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChartSectionHeader(
          title: widget.title,
          showTable: table,
          onChanged: (v) => ref.read(reportTableViewProvider(widget.reportId).notifier).state = v,
        ),
        if (!table) ...[
          Center(
            child: DonutChart(
              key: const ValueKey('breakdown-donut'),
              size: 200,
              stroke: 28,
              semanticsLabel: label,
              slices: [
                for (var i = 0; i < rows.length; i++) DonutSlice(value: rows[i].amount.minorUnits.toDouble(), color: colors[i]),
                if (others != null) DonutSlice(value: others.amount.minorUnits.toDouble(), color: hatch, hatched: true),
              ],
              center: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AmountText(b.total, whole: true, signed: false, style: const TextStyle(fontSize: 18)),
                  Text(countLabel, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (var i = 0; i < rows.length; i++)
            CategoryShareRow(
              key: ValueKey('category-row-${rows[i].routeId}'),
              name: categoryName(rows[i].name),
              icon: rows[i].icon,
              amount: rows[i].amount,
              sharePct: rows[i].sharePct,
              subtitle: _payments(rows[i].count),
              color: colors[i],
              needsCategory: rows[i].needsCategory,
              onTap: () => _open(rows[i]),
            ),
          if (others != null) ...[
            CategoryShareRow(
              key: const ValueKey('category-row-others'),
              name: 'analytics.others'.tr(),
              amount: others.amount,
              sharePct: others.sharePct,
              subtitle: trPlural('analytics.othersSub', others.members.length),
              color: hatch,
              hatched: true,
              trailingIcon: _othersOpen ? Icons.expand_less : Icons.expand_more,
              onTap: others.members.isEmpty ? null : () => setState(() => _othersOpen = !_othersOpen),
            ),
            if (_othersOpen)
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.xl),
                child: Column(
                  children: [
                    for (var i = 0; i < others.members.length; i++)
                      CategoryShareRow(
                        key: ValueKey('others-member-${others.members[i].routeId}'),
                        name: categoryName(others.members[i].name),
                        icon: others.members[i].icon,
                        amount: others.members[i].amount,
                        sharePct: others.members[i].sharePct,
                        subtitle: _payments(others.members[i].count),
                        color: reportColor(
                          context,
                          others.members[i].color,
                          rows.length + i,
                          uncategorised: others.members[i].isUncategorised,
                        ),
                        showBar: false,
                        needsCategory: others.members[i].needsCategory || others.members[i].isUncategorised,
                        onTap: () => _open(others.members[i]),
                      ),
                  ],
                ),
              ),
          ],
        ] else ...[
          ReportTable(
            key: const ValueKey('breakdown-table'),
            columns: [
              (b.kind == ReportKind.income ? 'analytics.table.source' : 'analytics.table.category').tr(),
              'analytics.table.amount'.tr(),
              'analytics.table.share'.tr(),
            ],
            rows: [
              for (var i = 0; i < rows.length; i++)
                ReportTableRow(
                  key: ValueKey('table-row-${rows[i].routeId}'),
                  cells: [categoryName(rows[i].name), rows[i].amount.whole, '${rows[i].sharePct}%'],
                  swatch: colors[i],
                  onTap: () => _open(rows[i]),
                ),
              if (others != null)
                ReportTableRow(
                  key: const ValueKey('table-row-others'),
                  cells: ['analytics.others'.tr(), others.amount.whole, '${others.sharePct}%'],
                  swatch: hatch,
                  hatched: true,
                ),
            ],
            footer: [
              'analytics.table.totalWithCount'.tr(namedArgs: {'count': countLabel}),
              b.total.whole,
              '100%',
            ],
          ),
          if (others != null && others.members.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                'analytics.othersList'.tr(
                  namedArgs: {
                    'list': others.members
                        .map((m) => '${categoryName(m.name)} ${nb(m.amount.whole)} (${m.sharePct}%)')
                        .join(', '),
                  },
                ),
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
        ],
      ],
    );
  }
}

/// The first few transactions behind a figure, then "See all N payments"
/// to Activity with the same filters.
class ReportPayments extends ConsumerWidget {
  const ReportPayments({
    super.key,
    required this.title,
    required this.query,
    required this.selection,
    required this.seeAllLabel,
  });

  final String title;
  final TxnQuery query;
  final PeriodSelection selection;
  final String seeAllLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(reportTransactionsProvider(query));
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title),
          page.when(
            loading: () => const SkeletonList(count: 3, shrinkWrap: true),
            error: (_, _) => ErrorRetry(compact: true, onRetry: () => ref.invalidate(reportTransactionsProvider(query))),
            data: (p) => Column(
              children: [
                for (final t in p.items)
                  TransactionTile(
                    data: txnTileData(t, meta: _meta(t)),
                    onTap: () => AnalyticsNav.transaction(context, t.id, selection),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            key: const ValueKey('see-all-payments'),
            onPressed: () => AnalyticsNav.activity(context, ref, query),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppSpacing.minTouch)),
            child: Text(seeAllLabel),
          ),
        ],
      ),
    );
  }

  static String? _meta(Txn t) {
    final d = t.occurredLocal;
    return d == null ? null : dayHeaderLabel(DateTime(d.year, d.month, d.day));
  }
}

/// Loading and error states shared by the report screens.
class ReportLoading extends StatelessWidget {
  const ReportLoading({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(top: AppSpacing.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonBox(width: 90),
        SizedBox(height: AppSpacing.sm),
        SkeletonBox(width: 200, height: 32),
        SizedBox(height: AppSpacing.xl),
        Center(child: SkeletonBox(height: 200, width: 200, circle: true)),
        SizedBox(height: AppSpacing.xl),
        SkeletonBox(height: 48),
        SizedBox(height: AppSpacing.md),
        SkeletonBox(height: 48),
      ],
    ),
  );
}

/// The colour money in is drawn in.
Color incomeColor(BuildContext context) => context.semantic.income;
