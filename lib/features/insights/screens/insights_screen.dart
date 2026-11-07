import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/notifications/notification_router.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/skeleton.dart';
import '../data/insights_repository.dart';
import '../widgets/notification_card.dart';

/// The notification centre: filter chips, day groups, one action per card,
/// and "Mark all as read".
class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key});

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen> {
  InsightFilter _filter = InsightFilter.all;

  /// Marked read on this phone and not yet reloaded (optimistic).
  final Set<String> _readHere = {};

  /// When the list on screen was loaded; "mark all" only covers up to then.
  DateTime _loadedAt = DateTime.now();

  bool _isRead(Insight i) => i.isRead || _readHere.contains(i.id);

  Future<void> _refresh() async {
    ref
      ..invalidate(insightsProvider)
      ..invalidate(unreadInsightsCountProvider);
    await ref.read(insightsProvider.future);
    if (mounted) {
      setState(() {
        _readHere.clear();
        _loadedAt = DateTime.now();
      });
    }
  }

  Future<void> _markAllRead(List<Insight> visible) async {
    final ids = [
      for (final i in visible)
        if (!_isRead(i)) i.id,
    ];
    if (ids.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _readHere.addAll(ids));
    try {
      // With no filter, everything loaded so far; with a filter, just those shown.
      await ref
          .read(insightsRepositoryProvider)
          .markAllReadOrEach(before: _filter == InsightFilter.all ? _loadedAt : null, ids: ids);
      ref.invalidate(unreadInsightsCountProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() => _readHere.removeAll(ids));
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(e is ApiException ? e.displayMessage : 'notifications2.markFailed'.tr())),
        );
    }
  }

  void _act(InsightAction action) {
    final id = action.data['insight_id']?.toString();
    if (id != null) setState(() => _readHere.add(id));
    NotificationRouter.instance.open(ref, action.data, router: GoRouter.of(context));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(insightsProvider);
    final all = async.valueOrNull ?? const <Insight>[];
    final unread = all.where((i) => !_isRead(i)).length;
    final visible = all.where((i) => matchesFilter(i, _filter, isRead: _isRead(i))).toList();
    final visibleUnread = visible.any((i) => !_isRead(i));
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: Text('notifications2.title'.tr()),
        actions: [
          if (visibleUnread)
            TextButton(
              key: const ValueKey('mark-all-read'),
              onPressed: () => _markAllRead(visible),
              child: Text('notifications2.markAllRead'.tr()),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
                child: Row(
                  children: [
                    for (final f in InsightFilter.values)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.sm),
                        child: ChoiceChip(
                          key: ValueKey('insight-filter-${f.name}'),
                          showCheckmark: false,
                          selected: _filter == f,
                          onSelected: (_) => setState(() => _filter = f),
                          label: Text(
                            f == InsightFilter.unread && unread > 0
                                ? '${'notifications2.filter.unread'.tr()} ($unread)'
                                : 'notifications2.filter.${f.name}'.tr(),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            ...async.when(
              skipLoadingOnRefresh: true,
              loading: () => [const SliverToBoxAdapter(child: SkeletonList(count: 5, shrinkWrap: true))],
              error: (_, _) => [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: ErrorRetry(
                      message: 'insights.loadError'.tr(),
                      onRetry: () => ref.invalidate(insightsProvider),
                    ),
                  ),
                ),
              ],
              data: (_) {
                if (visible.isEmpty) {
                  return [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: all.isEmpty || _filter == InsightFilter.unread
                            ? EmptyState(
                                key: const ValueKey('insights-caught-up'),
                                icon: Icons.notifications_off_outlined,
                                title: 'notifications2.caughtUpTitle'.tr(),
                                body: 'notifications2.caughtUpBody'.tr(),
                              )
                            : EmptyState(
                                key: const ValueKey('insights-filter-empty'),
                                icon: Icons.filter_list_off,
                                title: 'notifications2.filterEmptyTitle'.tr(),
                                body: 'notifications2.filterEmptyBody'.tr(),
                                actionLabel: 'notifications2.showAll'.tr(),
                                onAction: () => setState(() => _filter = InsightFilter.all),
                              ),
                      ),
                    ),
                  ];
                }
                return [
                  for (final (label, items) in groupInsights(visible, now)) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
                        child: Semantics(
                          header: true,
                          child: Text(
                            label,
                            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                      sliver: SliverList.list(
                        children: [
                          for (final i in items)
                            NotificationCard(
                              insight: i,
                              isRead: _isRead(i),
                              now: now,
                              // The detail screen marks it as read when it opens.
                              onOpen: () => context.push(Routes.notificationDetailFor(i.id), extra: i),
                              onAction: _act,
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
                ];
              },
            ),
          ],
        ),
      ),
    );
  }
}
