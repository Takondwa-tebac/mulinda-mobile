import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/activity/data/activity_repository.dart';
import '../../features/capture/data/inbox_repository.dart';
import '../../features/dashboard/data/dashboard_repository.dart';
import '../../features/insights/data/insights_repository.dart';
import '../../features/plan/data/plan_repository.dart';
import '../../features/summary/data/summary_repository.dart';
import '../network/dio_client.dart';
import 'offline_mode.dart';
import 'prefs.dart';

/// One screen's worth of data to save for offline use.
class PrefetchStep {
  const PrefetchStep(this.label, this.run, {this.dependsOn});

  final String label;
  final Future<void> Function() run;

  /// What this screen shows, by the names the change feed uses (transactions,
  /// accounts, goals, loans, budgets, investments, projects). It is refreshed
  /// when any of them changed. Null: always refreshed (the feed does not cover
  /// it). Empty: only on a full refresh.
  final Set<String>? dependsOn;

  /// Whether a smart refresh has to reload this screen.
  bool needsRefresh(Set<String> changed) => dependsOn == null || dependsOn!.any(changed.contains);
}

class PrefetchResult {
  const PrefetchResult({this.saved = 0, this.failed = 0, this.offline = false});

  final int saved;
  final int failed;

  /// There was no connection, so nothing was attempted.
  final bool offline;
}

/// Saves the data the main screens need so they open with no connection.
///
/// Saved data only exists for screens the user has actually opened while online
/// with offline mode on, so a user who turns the mode on and immediately goes
/// offline would find nothing. This fetches each screen's data up front, through
/// the normal providers, so the requests are exactly the ones the screens make
/// (the saved copy is keyed by request) and the cache interceptor stores them.
class OfflinePrefetcher {
  static const lastKey = 'offline_prefetch_last_ms';

  /// How old saved data may get before it is refreshed on the next opportunity.
  static const maxAge = Duration(hours: 2);

  static DateTime? lastSaved(SharedPreferences prefs) {
    final ms = prefs.getInt(lastKey);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static bool isStale(SharedPreferences prefs, {DateTime? now}) {
    final last = lastSaved(prefs);
    return last == null || (now ?? DateTime.now()).difference(last) > maxAge;
  }

  /// Runs [steps] in order. One failing screen never stops the others.
  static Future<PrefetchResult> run({
    required List<PrefetchStep> steps,
    required Future<bool> Function() isOnline,
    required SharedPreferences prefs,
    void Function(int done, int total, String label)? onProgress,
  }) async {
    if (!await isOnline()) return const PrefetchResult(offline: true);

    var saved = 0, failed = 0;
    for (var i = 0; i < steps.length; i++) {
      onProgress?.call(i, steps.length, steps[i].label);
      try {
        await steps[i].run();
        saved++;
      } catch (_) {
        failed++;
        // If the connection dropped mid-way there is no point carrying on.
        if (!await isOnline()) {
          onProgress?.call(steps.length, steps.length, '');
          return PrefetchResult(saved: saved, failed: failed + (steps.length - i - 1), offline: true);
        }
      }
    }
    onProgress?.call(steps.length, steps.length, '');
    if (saved > 0) await prefs.setInt(lastKey, DateTime.now().millisecondsSinceEpoch);
    return PrefetchResult(saved: saved, failed: failed);
  }

  /// Fetch a provider fresh from the server and keep it alive until it arrives.
  static Future<void> _load<T>(
    ProviderContainer c,
    ProviderListenable<AsyncValue<T>> provider,
    Refreshable<Future<T>> future,
  ) async {
    final sub = c.listen(provider, (_, _) {});
    try {
      await c.refresh(future);
    } finally {
      sub.close();
    }
  }

  static const _everything = {'transactions', 'accounts', 'goals', 'loans', 'budgets', 'investments', 'projects'};

  /// Where the last change-feed position is kept (the server's `server_time`).
  static const cursorKey = 'offline_changes_cursor';

  /// Asks the server what changed since the last refresh and returns only the
  /// steps that need to run. Everything runs the first time, when forced, when
  /// the server says too much time has passed, or when the feed is unavailable.
  /// `nextCursor` is stored by the caller once the refresh has succeeded.
  static Future<({List<PrefetchStep> steps, String? nextCursor})> plan({
    required List<PrefetchStep> all,
    required String? cursor,
    required bool force,
    required Future<Map<String, dynamic>?> Function(String since) fetchSummary,
  }) async {
    if (force || cursor == null) {
      // Take the server's clock now, so the next run asks about changes after this point.
      final first = await fetchSummary(DateTime.now().toUtc().toIso8601String());
      return (steps: all, nextCursor: first?['server_time']?.toString());
    }
    final summary = await fetchSummary(cursor);
    if (summary == null) return (steps: all, nextCursor: null);

    final next = summary['server_time']?.toString();
    if (summary['full_refresh_required'] == true) return (steps: all, nextCursor: next);

    final changed = <String>{
      for (final e in ((summary['changed'] as Map?) ?? const {}).entries)
        if (e.value == true) e.key.toString(),
    };
    return (steps: all.where((s) => s.needsRefresh(changed)).toList(), nextCursor: next);
  }

  /// The screens worth having offline.
  static List<PrefetchStep> defaultSteps(ProviderContainer c) => [
        PrefetchStep('Dashboard', () => _load(c, dashboardProvider, dashboardProvider.future),
            dependsOn: _everything),
        PrefetchStep('Accounts', () => _load(c, accountsProvider, accountsProvider.future),
            dependsOn: {'accounts', 'transactions'}),
        PrefetchStep('Categories', () => _load(c, categoriesProvider, categoriesProvider.future), dependsOn: {}),
        PrefetchStep('Transactions', () => _load(c, transactionsProvider, transactionsProvider.future),
            dependsOn: {'transactions'}),
        PrefetchStep('Account activity', () async {
          final accounts = await c.read(accountsProvider.future);
          for (final a in accounts.take(6)) {
            final p = accountTransactionsProvider(a.id);
            await _load(c, p, p.future);
          }
        }, dependsOn: {'accounts', 'transactions'}),
        PrefetchStep('Goals', () => _load(c, goalsProvider, goalsProvider.future), dependsOn: {'goals'}),
        PrefetchStep('Goal details', () async {
          for (final g in (await c.read(goalsProvider.future)).take(15)) {
            final p = goalDetailProvider(g.id);
            await _load(c, p, p.future);
          }
        }, dependsOn: {'goals'}),
        PrefetchStep('Budgets', () => _load(c, budgetsProvider, budgetsProvider.future),
            dependsOn: {'budgets', 'transactions'}),
        PrefetchStep('Loans', () => _load(c, loansProvider, loansProvider.future), dependsOn: {'loans'}),
        PrefetchStep('Loan details', () async {
          for (final l in (await c.read(loansProvider.future)).take(15)) {
            final p = loanDetailProvider(l.id);
            await _load(c, p, p.future);
          }
        }, dependsOn: {'loans'}),
        PrefetchStep('Investments', () => _load(c, investmentsListProvider, investmentsListProvider.future),
            dependsOn: {'investments'}),
        PrefetchStep('Projects', () => _load(c, projectsProvider, projectsProvider.future),
            dependsOn: {'projects', 'transactions'}),
        PrefetchStep('Notifications', () => _load(c, insightsProvider, insightsProvider.future)),
        PrefetchStep('Unread count', () => _load(c, unreadInsightsCountProvider, unreadInsightsCountProvider.future)),
        PrefetchStep('Inbox', () => _load(c, pendingReceiptsProvider, pendingReceiptsProvider.future)),
        PrefetchStep('Daily summaries', () => _load(c, dailySummariesProvider, dailySummariesProvider.future),
            dependsOn: {'transactions'}),
      ];
}

class PrefetchState {
  const PrefetchState({this.running = false, this.done = 0, this.total = 0, this.label = '', this.lastSaved});

  final bool running;
  final int done;
  final int total;
  final String label;
  final DateTime? lastSaved;

  PrefetchState copyWith({bool? running, int? done, int? total, String? label, DateTime? lastSaved}) => PrefetchState(
        running: running ?? this.running,
        done: done ?? this.done,
        total: total ?? this.total,
        label: label ?? this.label,
        lastSaved: lastSaved ?? this.lastSaved,
      );
}

/// Runs the saving and exposes its progress to the UI.
class OfflinePrefetchController extends Notifier<PrefetchState> {
  @override
  PrefetchState build() =>
      PrefetchState(lastSaved: OfflinePrefetcher.lastSaved(ref.read(sharedPreferencesProvider)));

  Future<bool> _online() async {
    try {
      final r = await Connectivity().checkConnectivity();
      return r.isNotEmpty && r.any((e) => e != ConnectivityResult.none);
    } catch (_) {
      return true;
    }
  }

  /// Save the main screens' data. Ignored while a run is already going or when
  /// offline mode is not in effect (nothing is stored for users who have it off).
  Future<PrefetchResult> start({bool force = false}) async {
    if (state.running) return const PrefetchResult();
    final prefs = ref.read(sharedPreferencesProvider);
    if (!ref.read(offlineModeProvider).active) return const PrefetchResult();
    if (!force && !OfflinePrefetcher.isStale(prefs)) return const PrefetchResult();

    state = state.copyWith(running: true, done: 0, total: 0, label: '');
    final container = ref.container;
    final plan = await OfflinePrefetcher.plan(
      all: OfflinePrefetcher.defaultSteps(container),
      cursor: prefs.getString(OfflinePrefetcher.cursorKey),
      force: force,
      fetchSummary: _fetchSummary,
    );
    final result = await OfflinePrefetcher.run(
      steps: plan.steps,
      isOnline: _online,
      prefs: prefs,
      onProgress: (done, total, label) => state = state.copyWith(running: true, done: done, total: total, label: label),
    );
    // Only move the position forward when every screen that needed it was saved,
    // otherwise the next run would skip what failed.
    if (plan.nextCursor != null && result.failed == 0 && !result.offline) {
      await prefs.setString(OfflinePrefetcher.cursorKey, plan.nextCursor!);
      if (plan.steps.isEmpty) await prefs.setInt(OfflinePrefetcher.lastKey, DateTime.now().millisecondsSinceEpoch);
    }
    state = PrefetchState(lastSaved: OfflinePrefetcher.lastSaved(prefs));
    return result;
  }

  Future<Map<String, dynamic>?> _fetchSummary(String since) async {
    try {
      final res = await ref.read(dioProvider).get<dynamic>(
        '/v1/sync/changes',
        queryParameters: {'summary': 1, 'since': since},
      );
      final data = res.data is Map ? (res.data as Map)['data'] : null;
      return data is Map ? data.cast<String, dynamic>() : null;
    } catch (_) {
      return null; // older server, rate limited or offline: refresh everything
    }
  }
}

final offlinePrefetchProvider =
    NotifierProvider<OfflinePrefetchController, PrefetchState>(OfflinePrefetchController.new);
