import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/semantic_colors.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/transaction_tile.dart';
import '../../capture/data/inbox_repository.dart';
import '../../dashboard/data/dashboard_repository.dart';
import '../data/activity_feed.dart';
import '../data/activity_models.dart';
import '../data/activity_repository.dart';
import '../data/day_grouping.dart';
import '../widgets/activity_filter_sheet.dart';
import '../widgets/category_quick_fix.dart';
import '../widgets/txn_view.dart';
import '../../../shared/plural.dart';

/// Activity: search, quick filters, the filter sheet, day-grouped list with
/// infinite scroll, and the category quick-fix.
class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  final _scroll = ScrollController();
  late final TextEditingController _search = TextEditingController(text: ref.read(activityFilterProvider).search);
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (_scroll.hasClients && _scroll.position.extentAfter < 600) {
      ref.read(activityFeedProvider.notifier).loadMore();
    }
  }

  TxnQuery get _query => ref.read(activityFilterProvider);
  void _setQuery(TxnQuery q) => ref.read(activityFilterProvider.notifier).set(q);

  void _onSearch(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _setQuery(_query.copyWith(search: text)));
  }

  Future<void> _refresh() async {
    ref
      ..invalidate(accountsProvider)
      ..invalidate(transactionsProvider)
      ..invalidate(reviewTransactionsProvider)
      ..invalidate(activityFeedProvider);
    await ref
        .read(activityFeedProvider.future)
        .catchError((_) => const ActivityFeed(items: [], page: 1, hasMore: false));
  }

  Future<void> _openFilters() async {
    final result = await showActivityFilterSheet(context, _query);
    if (result != null) _setQuery(result);
  }

  Future<void> _quickFix(Txn t) async {
    final feed = ref.read(activityFeedProvider.notifier);
    final index = ref.read(activityFeedProvider).valueOrNull?.items.indexWhere((e) => e.id == t.id) ?? 0;
    await openCategoryQuickFix(
      context,
      ref,
      t,
      onLocalUpdate: feed.patch,
      onRevert: (original) => feed.restore(original, index),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(activityFilterProvider);
    final feed = ref.watch(activityFeedProvider);
    final accounts = ref.watch(accountsProvider);
    final pending = ref.watch(pendingCountProvider);
    final reviewCount = ref.watch(reviewCountProvider).valueOrNull ?? 0;
    final needsAttention = ref.watch(dashboardProvider).valueOrNull?.needsAttention;

    // Keep the search box in step when another screen changes the filters.
    ref.listen(activityFilterProvider, (_, next) {
      if (next.search != _search.text && !(_debounce?.isActive ?? false)) _search.text = next.search;
    });

    return Scaffold(
      appBar: AppBar(
        title: Text('nav.activity'.tr()),
        actions: [
          IconButton(
            tooltip: 'activity2.reviewAuto'.tr(),
            onPressed: () => context.push(Routes.review),
            icon: Badge(
              isLabelVisible: reviewCount > 0,
              label: Text('$reviewCount'),
              child: const Icon(Icons.fact_check_outlined),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'common.more'.tr(),
            icon: Badge(isLabelVisible: pending > 0, smallSize: 8, child: const Icon(Icons.more_vert)),
            onSelected: (v) => context.push(v == 'export' ? Routes.exports : Routes.inbox),
            itemBuilder: (_) => [
              _menuItem(context, 'inbox', Icons.inbox_outlined, 'inbox.title'.tr(), count: pending),
              _menuItem(context, 'export', Icons.ios_share_outlined, 'activity2.export'.tr()),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm, AppSpacing.screen, 0),
              sliver: SliverList.list(
                children: [
                  if (reviewCount > 0) ...[
                    _ReviewBanner(count: reviewCount, onTap: () => context.push(Routes.review)),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  if (query.isDefault)
                    accounts.maybeWhen(
                      data: (a) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                        child: _AccountsStrip(accounts: a, onAdded: () => ref.invalidate(accountsProvider)),
                      ),
                      orElse: () => const SizedBox.shrink(),
                    ),
                  TextField(
                    controller: _search,
                    onChanged: _onSearch,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'activity2.searchHint'.tr(),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search.text.isEmpty && query.search.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'common.clear'.tr(),
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _debounce?.cancel();
                                _search.clear();
                                _setQuery(query.copyWith(search: ''));
                              },
                            ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _FilterChips(
                    query: query,
                    needsAttention: needsAttention,
                    onChanged: _setQuery,
                    onMore: _openFilters,
                  ),
                ],
              ),
            ),
            ...feed.when(
              skipLoadingOnRefresh: true,
              loading: () => [const SliverToBoxAdapter(child: SkeletonList(count: 8, shrinkWrap: true))],
              error: (_, _) => [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: ErrorRetry(onRetry: () => ref.invalidate(activityFeedProvider))),
                ),
              ],
              data: (f) => _listSlivers(context, f, query),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _listSlivers(BuildContext context, ActivityFeed f, TxnQuery query) {
    if (f.items.isEmpty) {
      final filtered = !query.isDefault;
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: query.needsCategory && query.search.isEmpty && query.sheetFilterCount == 0
                ? EmptyState(
                    icon: Icons.task_alt,
                    title: 'activity2.allCategorisedTitle'.tr(),
                    body: 'activity2.allCategorisedBody'.tr(),
                    actionLabel: 'activity2.showAll'.tr(),
                    onAction: () => _setQuery(TxnQuery.none),
                  )
                : filtered
                ? EmptyState(
                    icon: Icons.search_off,
                    title: 'activity2.noMatchesTitle'.tr(),
                    body: 'activity2.noMatchesBody'.tr(),
                    actionLabel: 'activity2.clearFilters'.tr(),
                    onAction: () {
                      _search.clear();
                      _setQuery(TxnQuery.none);
                    },
                  )
                : EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'activity2.emptyTitle'.tr(),
                    body: 'activity2.emptyBody'.tr(),
                    actionLabel: 'activity2.addTransaction'.tr(),
                    onAction: () => context.push(Routes.addTransaction),
                    secondaryLabel: 'activity2.captureSms'.tr(),
                    onSecondary: () => context.push(Routes.pasteSms),
                  ),
          ),
        ),
      ];
    }

    final groups = groupByDay(f.items);
    final now = DateTime.now();
    return [
      for (final g in groups)
        SliverMainAxisGroup(
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: _DayHeaderDelegate(group: g, now: now),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
              sliver: SliverList.builder(itemCount: g.items.length, itemBuilder: (_, i) => _row(g.items[i])),
            ),
          ],
        ),
      SliverToBoxAdapter(
        child: _Footer(feed: f, onRetry: () => ref.read(activityFeedProvider.notifier).loadMore()),
      ),
    ];
  }

  Widget _row(Txn t) {
    final tile = TransactionTile(
      data: txnTileData(t),
      onTap: () => context.push(Routes.transactionDetail, extra: t.id),
      onLongPress: t.type == 'transfer' ? null : () => _quickFix(t),
      onConfirmCategory: () => _quickFix(t),
    );
    if (t.type == 'transfer') return tile;
    // Swipe right to categorise: opens the sheet and leaves the row in place.
    return Dismissible(
      key: ValueKey('swipe-${t.id}'),
      direction: DismissDirection.startToEnd,
      confirmDismiss: (_) async {
        await _quickFix(t);
        return false;
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            Icon(Icons.category_outlined, color: Theme.of(context).colorScheme.onPrimaryContainer),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'activity2.categorise'.tr(),
              style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onPrimaryContainer),
            ),
          ],
        ),
      ),
      child: tile,
    );
  }
}

/// All / Income / Expenses / Needs category, plus the "Filters" button.
class _FilterChips extends StatelessWidget {
  const _FilterChips({
    required this.query,
    required this.needsAttention,
    required this.onChanged,
    required this.onMore,
  });

  final TxnQuery query;
  final int? needsAttention;
  final ValueChanged<TxnQuery> onChanged;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final all = query.type == null && !query.needsCategory;
    final extra = query.sheetFilterCount;
    final needsLabel = needsAttention != null && needsAttention! > 0
        ? '${'activity2.filterNeedsCategory'.tr()} ($needsAttention)'
        : 'activity2.filterNeedsCategory'.tr();

    Widget chip(String label, bool selected, VoidCallback onTap, {Key? key}) => Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: ChoiceChip(
        key: key,
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => onTap(),
      ),
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip(
            'activity2.filterAll'.tr(),
            all,
            () => onChanged(query.copyWith(type: () => null, needsCategory: false)),
          ),
          chip(
            'activity2.filterIncome'.tr(),
            query.type == 'income',
            () => onChanged(query.copyWith(type: () => query.type == 'income' ? null : 'income', needsCategory: false)),
          ),
          chip(
            'activity2.filterExpenses'.tr(),
            query.type == 'expense',
            () =>
                onChanged(query.copyWith(type: () => query.type == 'expense' ? null : 'expense', needsCategory: false)),
          ),
          chip(
            needsLabel,
            query.needsCategory,
            () => onChanged(query.copyWith(type: () => null, needsCategory: !query.needsCategory)),
            key: const ValueKey('filter-needs-category'),
          ),
          ActionChip(
            avatar: const Icon(Icons.tune, size: 18),
            label: Text(extra > 0 ? '${'activity2.filters'.tr()} ($extra)' : 'activity2.filters'.tr()),
            onPressed: onMore,
          ),
        ],
      ),
    );
  }
}

/// A day header that stays at the top while its rows scroll beneath it.
class _DayHeaderDelegate extends SliverPersistentHeaderDelegate {
  _DayHeaderDelegate({required this.group, required this.now});

  final DayGroup group;
  final DateTime now;

  static const _height = 40.0;

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = context.semantic;
    final currency = group.currency;
    final totals = <InlineSpan>[
      if (currency != null && group.outMinor > 0)
        TextSpan(
          text: '-${formatMinor(group.outMinor, currency)}',
          style: TextStyle(color: semantic.expense),
        ),
      if (currency != null && group.outMinor > 0 && group.inMinor > 0) const TextSpan(text: '  '),
      if (currency != null && group.inMinor > 0)
        TextSpan(
          text: '+${formatMinor(group.inMinor, currency)}',
          style: TextStyle(color: semantic.income),
        ),
    ];
    return Container(
      color: scheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
      alignment: Alignment.centerLeft,
      child: Semantics(
        header: true,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              flex: 2,
              child: Text(
                dayHeaderLabel(group.day, now: now),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            if (totals.isNotEmpty)
              Flexible(
                flex: 3,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text.rich(
                      TextSpan(children: totals),
                      maxLines: 1,
                      style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _DayHeaderDelegate old) =>
      old.group.day != group.day ||
      old.group.inMinor != group.inMinor ||
      old.group.outMinor != group.outMinor ||
      old.now.day != now.day;
}

class _Footer extends StatelessWidget {
  const _Footer({required this.feed, required this.onRetry});

  final ActivityFeed feed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget body;
    if (feed.loadingMore) {
      body = const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5));
    } else if (feed.loadMoreFailed) {
      body = ErrorRetry(compact: true, message: 'activity2.loadMoreFailed'.tr(), onRetry: onRetry);
    } else if (!feed.hasMore) {
      body = Text('activity2.endOfList'.tr(), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12));
    } else {
      body = const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.lg, AppSpacing.screen, AppSpacing.fabClearance),
      child: Center(child: body),
    );
  }
}

/// A labeled overflow-menu row, optionally with a count pill.
PopupMenuItem<String> _menuItem(BuildContext context, String value, IconData icon, String label, {int count = 0}) {
  final scheme = Theme.of(context).colorScheme;
  return PopupMenuItem<String>(
    value: value,
    child: Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: Text(label)),
        if (count > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
            decoration: BoxDecoration(color: scheme.error, borderRadius: AppRadius.chip),
            child: Text(
              '$count',
              style: TextStyle(color: scheme.onError, fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
      ],
    ),
  );
}

/// Prominent, self-surfacing prompt to review auto-recorded transactions.
class _ReviewBanner extends StatelessWidget {
  const _ReviewBanner({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer,
      borderRadius: AppRadius.card,
      child: InkWell(
        borderRadius: AppRadius.card,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Icon(Icons.fact_check_outlined, color: scheme.onPrimaryContainer),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trCount('activity2.toReviewCount', count),
                      style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      'activity2.toReviewSub'.tr(),
                      style: TextStyle(fontSize: 12, color: scheme.onPrimaryContainer.withValues(alpha: 0.8)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onPrimaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountsStrip extends StatelessWidget {
  const _AccountsStrip({required this.accounts, required this.onAdded});
  final List<Account> accounts;
  final VoidCallback onAdded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showAddButton = accounts.length > 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('activity.accounts'.tr(), style: const TextStyle(fontWeight: FontWeight.w700)),
            if (showAddButton)
              TextButton.icon(
                onPressed: () => _addAccount(context),
                icon: const Icon(Icons.add, size: 18),
                label: Text('account.add'.tr()),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            // +1 for the trailing "add account" tile when accounts <= 2
            itemCount: accounts.length + (showAddButton ? 0 : 1),
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (_, i) {
              if (!showAddButton && i == accounts.length) return _AddAccountTile(onTap: () => _addAccount(context));
              final a = accounts[i];
              return InkWell(
                onTap: () => context.push(Routes.accountDetail, extra: a),
                borderRadius: AppRadius.card,
                child: Container(
                  width: 180,
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: AppRadius.card),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              a.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onPrimaryContainer),
                            ),
                          ),
                          Icon(Icons.chevron_right, size: 18, color: scheme.onPrimaryContainer),
                        ],
                      ),
                      Text(
                        a.currentBalance.formatted,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: scheme.onPrimaryContainer),
                      ),
                      if (a.pending || a.balanceEstimated)
                        Text(
                          a.pending ? 'activity2.waitingToSync'.tr() : 'activity2.estimated'.tr(),
                          style: TextStyle(fontSize: 11, color: scheme.onPrimaryContainer.withValues(alpha: 0.8)),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _addAccount(BuildContext context) async {
    final added = await context.push<bool>(Routes.addAccount);
    if (added == true) onAdded();
  }
}

class _AddAccountTile extends StatelessWidget {
  const _AddAccountTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = context.semantic.brandInk;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.card,
      child: Container(
        width: 140,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          borderRadius: AppRadius.card,
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle_outline, color: ink),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'account.add'.tr(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w600, color: ink),
            ),
          ],
        ),
      ),
    );
  }
}
