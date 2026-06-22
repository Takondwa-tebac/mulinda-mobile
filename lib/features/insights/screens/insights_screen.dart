import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/insights_repository.dart';

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(insightsProvider);

    return Scaffold(
      appBar: AppBar(title: Text('insights.title'.tr())),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(insightsProvider);
          ref.invalidate(unreadInsightsCountProvider);
          await ref.read(insightsProvider.future);
        },
        child: async.when(
          loading: () => const _Fill(child: CircularProgressIndicator()),
          error: (_, _) => _Fill(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('insights.loadError'.tr()),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: () => ref.invalidate(insightsProvider),
                  child: Text('insights.retry'.tr()),
                ),
              ],
            ),
          ),
          data: (list) => list.isEmpty
              ? _Fill(child: Text('insights.empty'.tr(), textAlign: TextAlign.center))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _InsightCard(insight: list[i], ref: ref),
                ),
        ),
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.insight, required this.ref});
  final Insight insight;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: insight.isRead ? null : scheme.primaryContainer.withValues(alpha: 0.35),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          foregroundColor: scheme.onPrimaryContainer,
          child: Icon(_iconFor(insight.type), size: 18),
        ),
        title: Text(insight.title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(insight.body),
        isThreeLine: insight.body.length > 40,
        trailing: insight.isRead
            ? null
            : Container(width: 10, height: 10, decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle)),
        onTap: insight.isRead
            ? null
            : () async {
                await ref.read(insightsRepositoryProvider).markRead(insight.id);
                ref.invalidate(insightsProvider);
                ref.invalidate(unreadInsightsCountProvider);
              },
      ),
    );
  }

  IconData _iconFor(String type) => switch (type) {
        'savings_opportunity' => Icons.lightbulb_outline,
        'spending_spike' => Icons.trending_up,
        'budget_alert' => Icons.warning_amber_rounded,
        'bill_due' => Icons.event_outlined,
        'loan_repayment_due' => Icons.account_balance_outlined,
        'announcement' => Icons.campaign_outlined,
        _ => Icons.insights_outlined,
      };
}

class _Fill extends StatelessWidget {
  const _Fill({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: Center(child: Padding(padding: const EdgeInsets.all(24), child: child)),
          ),
        ],
      );
}
