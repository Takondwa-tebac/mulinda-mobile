import 'package:easy_localization/easy_localization.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../data/insights_repository.dart';
import 'notification_detail_screen.dart' show iconForInsightType;

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
    final hasImage = insight.imageUrl != null && insight.imageUrl!.isNotEmpty;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 12),
      color: insight.isRead ? null : scheme.primaryContainer.withValues(alpha: 0.35),
      child: InkWell(
        // The detail screen marks it as read when it opens.
        onTap: () => context.push(Routes.notificationDetailFor(insight.id), extra: insight),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasImage)
              CachedNetworkImage(
                imageUrl: insight.imageUrl!,
                height: 160,
                fit: BoxFit.cover,
                placeholder: (_, _) => const SizedBox(
                  height: 160,
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                errorWidget: (_, _, _) => const SizedBox.shrink(),
              ),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.onPrimaryContainer,
                child: Icon(iconForInsightType(insight.type), size: 18),
              ),
              title: Text(
                insight.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: insight.isRead ? FontWeight.w500 : FontWeight.w700),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(insight.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (insight.date.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        insight.date,
                        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                      ),
                    ),
                ],
              ),
              isThreeLine: insight.body.length > 40,
              trailing: insight.isRead
                  ? null
                  : Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                    ),
            ),
          ],
        ),
      ),
    );
  }
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
