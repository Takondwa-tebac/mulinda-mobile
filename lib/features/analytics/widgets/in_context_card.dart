import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../activity/data/activity_models.dart';
import '../analytics_nav.dart';
import '../data/analytics_models.dart';
import '../data/analytics_repository.dart';
import '../presentation/analytics_text.dart';

/// "In context" on a transaction opened from a report: how big it is in its
/// category and with its shop, for the report's period. Renders nothing when
/// the server sent no context (or it cannot load); the rest of the screen
/// stands on its own.
class InContextCard extends ConsumerWidget {
  const InContextCard({super.key, required this.txn, required this.period});

  final Txn txn;
  final PeriodSelection period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(transactionContextProvider((id: txn.id, period: period)));
    final ctx = async.valueOrNull;
    if (ctx == null || ctx.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final income = txn.isIncome;
    final category = categoryName(txn.categoryName);
    final range = periodRange(ctx.period);
    final lines = <(IconData, String)>[
      if (ctx.rankInCategory == 1 && (ctx.categoryCount ?? 0) >= 2)
        (
          Icons.flag_outlined,
          (income ? 'analytics.ctx.biggestInCategoryIncome' : 'analytics.ctx.biggestInCategory').tr(
            namedArgs: {'category': category},
          ),
        ),
      if (ctx.shareOfCategoryPct != null && ctx.categoryTotal != null)
        (
          Icons.pie_chart_outline,
          (income ? 'analytics.ctx.shareOfCategoryIncome' : 'analytics.ctx.shareOfCategory').tr(
            namedArgs: {
              'pct': '${ctx.shareOfCategoryPct}',
              'category': category,
              'total': moneyWords(ctx.categoryTotal),
            },
          ),
        ),
      if (ctx.merchant case final m?)
        (
          Icons.storefront_outlined,
          m.count <= 1
              ? (income ? 'analytics.ctx.merchantOnlyIncome' : 'analytics.ctx.merchantOnly').tr(
                  namedArgs: {'merchant': m.name},
                )
              : (income ? 'analytics.ctx.merchantCountIncome' : 'analytics.ctx.merchantCount').tr(
                  namedArgs: {'count': '${m.count}', 'merchant': m.name, 'total': moneyWords(m.total)},
                ),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Card(
        key: const ValueKey('in-context-card'),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text('analytics.ctx.title'.tr(), style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              Text(
                [periodTitle(period, ctx.period), if (range.isNotEmpty) range].join(', '),
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final (icon, text) in lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ExcludeSemantics(child: Icon(icon, size: 18, color: scheme.onSurfaceVariant)),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: Text(text, style: const TextStyle(height: 1.35))),
                    ],
                  ),
                ),
              if (ctx.merchant != null && ctx.merchant!.count > 1) ...[
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton(
                  key: const ValueKey('see-all-from-merchant'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppSpacing.minTouch)),
                  onPressed: () => AnalyticsNav.activity(
                    context,
                    ref,
                    AnalyticsNav.query(
                      period,
                      period: ctx.period,
                      kind: income ? ReportKind.income : ReportKind.expense,
                      merchant: ctx.merchant!.name,
                    ),
                  ),
                  child: Text('analytics.ctx.seeAllFrom'.tr(namedArgs: {'merchant': ctx.merchant!.name})),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
