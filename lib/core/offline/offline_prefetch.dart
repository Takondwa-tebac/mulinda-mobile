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
import 'offline_mode.dart';
import 'prefs.dart';

/// One screen's worth of data to save for offline use.
class PrefetchStep {
  const PrefetchStep(this.label, this.run);

  final String label;
  final Future<void> Function() run;
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

  /// The screens worth having offline.
  static List<PrefetchStep> defaultSteps(ProviderContainer c) => [
        PrefetchStep('Dashboard', () => _load(c, dashboardProvider, dashboardProvider.future)),
        PrefetchStep('Accounts', () => _load(c, accountsProvider, accountsProvider.future)),
        PrefetchStep('Categories', () => _load(c, categoriesProvider, categoriesProvider.future)),
        PrefetchStep('Transactions', () => _load(c, transactionsProvider, transactionsProvider.future)),
        PrefetchStep('Account activity', () async {
          final accounts = await c.read(accountsProvider.future);
          for (final a in accounts.take(6)) {
            final p = accountTransactionsProvider(a.id);
            await _load(c, p, p.future);
          }
        }),
        PrefetchStep('Goals', () => _load(c, goalsProvider, goalsProvider.future)),
        PrefetchStep('Budgets', () => _load(c, budgetsProvider, budgetsProvider.future)),
        PrefetchStep('Loans', () => _load(c, loansProvider, loansProvider.future)),
        PrefetchStep('Investments', () => _load(c, investmentsListProvider, investmentsListProvider.future)),
        PrefetchStep('Projects', () => _load(c, projectsProvider, projectsProvider.future)),
        PrefetchStep('Notifications', () => _load(c, insightsProvider, insightsProvider.future)),
        PrefetchStep('Unread count', () => _load(c, unreadInsightsCountProvider, unreadInsightsCountProvider.future)),
        PrefetchStep('Inbox', () => _load(c, pendingReceiptsProvider, pendingReceiptsProvider.future)),
        PrefetchStep('Daily summaries', () => _load(c, dailySummariesProvider, dailySummariesProvider.future)),
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
    final result = await OfflinePrefetcher.run(
      steps: OfflinePrefetcher.defaultSteps(container),
      isOnline: _online,
      prefs: prefs,
      onProgress: (done, total, label) => state = state.copyWith(running: true, done: done, total: total, label: label),
    );
    state = PrefetchState(lastSaved: OfflinePrefetcher.lastSaved(prefs));
    return result;
  }
}

final offlinePrefetchProvider =
    NotifierProvider<OfflinePrefetchController, PrefetchState>(OfflinePrefetchController.new);
