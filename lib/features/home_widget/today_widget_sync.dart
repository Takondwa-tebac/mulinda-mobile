import 'dart:async';
import 'dart:io' show Platform;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers/auth_controller.dart';
import '../dashboard/data/dashboard_models.dart';
import '../dashboard/data/dashboard_repository.dart';
import '../plan/data/plan_models.dart';
import '../plan/data/plan_repository.dart';
import '../summary/data/summary_models.dart';
import '../summary/data/summary_repository.dart';
import 'mulinda_today.home_widget.dart';
import 'today_widget_data.dart';

/// Keeps the "Lero / Today" home-screen widget in step with the account.
///
/// The widget never calls the API itself: the app works out the snapshot and
/// saves it through home_widget, then asks the launcher to redraw. Refreshes
/// are debounced so a burst of writes (an SMS batch, an offline sync) costs one
/// round of requests.
class TodayWidgetSync {
  TodayWidgetSync(this._ref);

  final Ref _ref;
  Timer? _debounce;
  bool _running = false;
  bool _again = false;

  /// Only Android has the native widget for now. The iOS WidgetKit extension
  /// needs the iOS project (feat/ios-support) and a Mac to add the target.
  static bool get supported => !kIsWeb && Platform.isAndroid;

  /// Refresh shortly, folding repeated calls into one.
  void schedule([Duration delay = const Duration(seconds: 2)]) {
    if (!supported) return;
    _debounce?.cancel();
    _debounce = Timer(delay, () => unawaited(refresh()));
  }

  Future<void> refresh() async {
    if (!supported) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      if (_ref.read(currentUserProvider) == null) {
        await clear();
        return;
      }

      final todayF = _safe<DailySummary?>(() => _ref.read(summaryRepositoryProvider).today());
      final dashboardF = _safe<DashboardSummary>(() => _ref.read(dashboardRepositoryProvider).fetch());
      final budgetsF = _safe<List<BudgetItem>>(() => _ref.read(planRepositoryProvider).budgets());
      final historyF = _safe<List<DailySummary>>(() => _ref.read(summaryRepositoryProvider).history());
      final today = await todayF;
      final dashboard = await dashboardF;
      final budgets = await budgetsF;
      final history = await historyF;
      // Nothing reachable (offline without a saved copy): keep what the widget
      // already shows rather than blanking it.
      if (today == null && dashboard == null) return;

      final data = buildTodayWidgetData(
        now: DateTime.now(),
        t: _t,
        today: today,
        dashboard: dashboard,
        budgets: budgets ?? const [],
        history: history ?? const [],
      );
      await MulindaTodayHomeWidget.saveData(
        hasData: true,
        title: data.title,
        spent: data.spent,
        left: data.left,
        streak: data.streak,
        lastTxn: data.lastTxn,
        lastAmount: data.lastAmount,
        challengeLabel: data.challengeLabel,
        challengeText: data.challengeText,
        challengeStatus: data.challengeStatus,
        over: data.warn,
        bar1: data.bars[0],
        bar2: data.bars[1],
        bar3: data.bars[2],
        bar4: data.bars[3],
        bar5: data.bars[4],
      );
      await MulindaTodayHomeWidget.updateWidget();
    } catch (e) {
      debugPrint('Today widget refresh failed: $e');
    } finally {
      _running = false;
      if (_again) {
        _again = false;
        schedule();
      }
    }
  }

  /// Signed out: hide every amount and show the "open Mulinda" prompt.
  Future<void> clear() async {
    if (!supported) return;
    try {
      await MulindaTodayHomeWidget.saveData(
        hasData: false,
        title: _t('title'),
        emptyText: _t('signedOut'),
        spent: '',
        left: '',
        streak: '',
        lastTxn: '',
        lastAmount: '',
      );
      await MulindaTodayHomeWidget.updateWidget();
    } catch (e) {
      debugPrint('Today widget clear failed: $e');
    }
  }

  void dispose() => _debounce?.cancel();

  static String _t(String key, {Map<String, String>? args}) => 'homeWidget.$key'.tr(namedArgs: args);

  static Future<T?> _safe<T>(Future<T> Function() load) async {
    try {
      return await load();
    } catch (_) {
      return null;
    }
  }
}

final todayWidgetSyncProvider = Provider<TodayWidgetSync>((ref) {
  final sync = TodayWidgetSync(ref);
  ref.onDispose(sync.dispose);
  return sync;
});

/// API paths whose writes change what the Today widget shows.
final _widgetRelevantWrite = RegExp(r'^/?v1/(transactions|sms|receipt|budgets|sync|goals|loans|investments|accounts)');

/// True for a successful write the widget should react to.
bool isWidgetRelevantWrite(String method, String path) =>
    method.toUpperCase() != 'GET' && _widgetRelevantWrite.hasMatch(path);
