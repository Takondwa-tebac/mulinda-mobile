import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'activity_models.dart';
import 'activity_repository.dart';

/// The filters of the Activity list. Not auto-disposed, so another screen
/// (e.g. Home's "Needs your attention") can set it before switching tabs.
class ActivityFilterController extends Notifier<TxnQuery> {
  @override
  TxnQuery build() => TxnQuery.none;

  void set(TxnQuery query) => state = query;
  void reset() => state = TxnQuery.none;

  /// Only rows whose category needs a look.
  void showNeedsCategory() => state = const TxnQuery(needsCategory: true);
}

final activityFilterProvider = NotifierProvider<ActivityFilterController, TxnQuery>(ActivityFilterController.new);

/// The loaded part of the Activity list.
class ActivityFeed {
  const ActivityFeed({
    required this.items,
    required this.page,
    required this.hasMore,
    this.loadingMore = false,
    this.loadMoreFailed = false,
  });

  final List<Txn> items;
  final int page;
  final bool hasMore;
  final bool loadingMore;
  final bool loadMoreFailed;

  ActivityFeed copyWith({List<Txn>? items, int? page, bool? hasMore, bool? loadingMore, bool? loadMoreFailed}) =>
      ActivityFeed(
        items: items ?? this.items,
        page: page ?? this.page,
        hasMore: hasMore ?? this.hasMore,
        loadingMore: loadingMore ?? this.loadingMore,
        loadMoreFailed: loadMoreFailed ?? this.loadMoreFailed,
      );
}

/// Pages through `GET /v1/transactions` for the current filters. The first
/// unfiltered page is [transactionsProvider] itself, so every place that
/// invalidates it (new transaction, sync, review) refreshes this list too, and
/// it works from the offline cache.
class ActivityFeedController extends AutoDisposeAsyncNotifier<ActivityFeed> {
  @override
  Future<ActivityFeed> build() async {
    final query = ref.watch(activityFilterProvider);
    if (query.isDefault) {
      final first = await ref.watch(transactionsProvider.future);
      return ActivityFeed(items: first, page: 1, hasMore: first.length >= ActivityRepository.pageSize);
    }
    final page = await ref.read(activityRepositoryProvider).transactionsPage(query);
    return ActivityFeed(items: page.items, page: 1, hasMore: page.hasMore);
  }

  /// Fetch the next page (no-op while one is loading or when there is none).
  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(current.copyWith(loadingMore: true, loadMoreFailed: false));
    try {
      final next = await ref
          .read(activityRepositoryProvider)
          .transactionsPage(ref.read(activityFilterProvider), page: current.page + 1);
      final seen = current.items.map((t) => t.id).toSet();
      state = AsyncData(
        current.copyWith(
          items: [...current.items, ...next.items.where((t) => !seen.contains(t.id))],
          page: current.page + 1,
          hasMore: next.hasMore,
          loadingMore: false,
        ),
      );
    } catch (_) {
      state = AsyncData(current.copyWith(loadingMore: false, loadMoreFailed: true));
    }
  }

  /// Replace one row in place (optimistic update or server echo). A row that no
  /// longer matches the "Needs category" filter drops out of the list.
  void patch(Txn updated) {
    final current = state.valueOrNull;
    if (current == null) return;
    final dropFixed = ref.read(activityFilterProvider).needsCategory && !updated.needsCategory;
    final items = <Txn>[
      for (final t in current.items)
        if (t.id != updated.id) t else if (!dropFixed) updated,
    ];
    state = AsyncData(current.copyWith(items: items));
  }

  /// Put a row back exactly as it was (when a change failed).
  void restore(Txn original, int index) {
    final current = state.valueOrNull;
    if (current == null) return;
    final items = [...current.items];
    final at = items.indexWhere((t) => t.id == original.id);
    if (at >= 0) {
      items[at] = original;
    } else {
      items.insert(index.clamp(0, items.length), original);
    }
    state = AsyncData(current.copyWith(items: items));
  }
}

final activityFeedProvider = AsyncNotifierProvider.autoDispose<ActivityFeedController, ActivityFeed>(
  ActivityFeedController.new,
);
