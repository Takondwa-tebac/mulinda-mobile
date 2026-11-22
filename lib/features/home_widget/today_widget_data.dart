import '../../core/money/currencies.dart';
import '../dashboard/data/dashboard_models.dart';
import '../plan/data/plan_models.dart';
import '../summary/data/summary_models.dart';

/// Translates a key under `homeWidget.` (easy_localization in the app, a fake
/// in tests).
typedef WidgetTranslator = String Function(String key, {Map<String, String>? args});

/// Everything the "Lero / Today" home-screen widget shows, already formatted
/// and translated. The native widget only lays these strings out.
class TodayWidgetData {
  const TodayWidgetData({
    required this.title,
    required this.spent,
    required this.left,
    required this.streak,
    required this.lastTxn,
    required this.lastAmount,
    required this.challengeLabel,
    required this.challengeText,
    required this.challengeStatus,
    required this.bars,
    required this.warn,
  });

  final String title;
  final String spent;
  final String left;
  final String streak;
  final String lastTxn;
  final String lastAmount;
  final String challengeLabel;
  final String challengeText;
  final String challengeStatus;

  /// Five bar segments, filled from the left as today's spending approaches
  /// the daily allowance.
  final List<bool> bars;

  /// True once spending reaches 80% of the allowance: the bar and the
  /// challenge status turn orange.
  final bool warn;
}

/// Share of the allowance at which the widget starts warning.
const warnRatio = 0.8;

/// Builds the widget snapshot from data the API already serves.
///
/// * Spent today: `GET /v1/daily-summaries/today` → `expense`.
/// * Daily allowance (derived, see [dailyAllowanceMinor]): what is left of
///   the active budgets before today, each spread over the days left in its
///   own period. Without budgets it falls back to this month's income minus
///   what was spent before today. Used-up budgets give an allowance of 0.
/// * Streak (derived): consecutive days with at least one logged transaction,
///   from the daily-summary history, counted up to today (or yesterday when
///   nothing is logged yet today).
/// * Last transaction: `GET /v1/dashboard` → `recent_transactions[0]`.
TodayWidgetData buildTodayWidgetData({
  required DateTime now,
  required WidgetTranslator t,
  DailySummary? today,
  DashboardSummary? dashboard,
  List<BudgetItem> budgets = const [],
  List<DailySummary> history = const [],
}) {
  final currency = today?.expense.currency ?? dashboard?.thisMonth.expense.currency ?? 'MWK';
  final spentMinor = today?.expense.minorUnits.abs() ?? 0;
  final allowanceMinor = dailyAllowanceMinor(
    now: now,
    currency: currency,
    spentTodayMinor: spentMinor,
    budgets: budgets,
    dashboard: dashboard,
  );

  final streakDays = loggingStreak(now: now, today: today, history: history);
  final last = (dashboard?.recent.isNotEmpty ?? false) ? dashboard!.recent.first : null;

  String money(int minor) => formatWholeMoney(minor, currency);

  var bars = List<bool>.filled(5, false);
  var warn = false;
  String leftText;
  String challengeText;
  String challengeStatus;

  if (allowanceMinor == null) {
    leftText = t('noAllowance');
    challengeText = t('challengeLog');
    challengeStatus = t('loggedCount', args: {'count': '${today?.transactionCount ?? 0}'});
  } else if (allowanceMinor <= 0) {
    // Budgets exist but nothing is left in them: say so, don't ask for one.
    bars = List<bool>.filled(5, true);
    warn = true;
    leftText = t('budgetUsedUp');
    challengeText = t('challengeNoSpend');
    challengeStatus = spentMinor > 0 ? t('overBy', args: {'amount': money(spentMinor)}) : t('onTrack');
  } else {
    final ratio = spentMinor / allowanceMinor;
    final filled = (ratio * 5).ceil().clamp(0, 5);
    bars = List<bool>.generate(5, (i) => i < filled);
    warn = ratio >= warnRatio;
    final remaining = allowanceMinor - spentMinor;
    leftText = remaining >= 0
        ? t('left', args: {'amount': money(remaining)})
        : t('over', args: {'amount': money(-remaining)});
    challengeText = t('challengeStayUnder', args: {'amount': money(allowanceMinor)});
    challengeStatus = ratio < warnRatio
        ? t('onTrack')
        : remaining >= 0
            ? t('left', args: {'amount': money(remaining)})
            : t('overBy', args: {'amount': money(-remaining)});
  }

  return TodayWidgetData(
    title: t('title'),
    spent: money(spentMinor),
    left: leftText,
    streak: streakDays >= 2 ? '🔥 $streakDays' : '',
    lastTxn: last == null ? t('noTransactions') : _ellipsize(last.merchant ?? last.category ?? t('transaction'), 22),
    lastAmount: last == null ? '' : _signedAmount(last),
    challengeLabel: t('challengeLabel').toUpperCase(),
    challengeText: challengeText,
    challengeStatus: challengeStatus,
    bars: bars,
    warn: warn,
  );
}

/// Today's spending allowance in minor units.
///
/// * null: nothing to derive it from (no active budget covering today and no
///   income recorded this month).
/// * 0: budgets exist but are used up for their period.
///
/// Each active budget (any period: weekly, monthly, ...) contributes what is
/// left of it before today, spread over the days left in its own period.
/// Budget spending already includes today's, so today's spending is taken back
/// out, shared across budgets by how much each has spent, so the allowance
/// stays put while the user spends during the day.
int? dailyAllowanceMinor({
  required DateTime now,
  required String currency,
  required int spentTodayMinor,
  required List<BudgetItem> budgets,
  DashboardSummary? dashboard,
}) {
  final day = DateTime(now.year, now.month, now.day);
  final monthEnd = DateTime(now.year, now.month + 1, 0);
  int daysUntil(DateTime end) => end.difference(day).inDays + 1;

  final active = budgets.where((b) {
    if (!b.isActive || b.limit.currency != currency || b.limit.minorUnits <= 0) return false;
    final from = DateTime.tryParse(b.periodFrom ?? '');
    final to = DateTime.tryParse(b.periodTo ?? '');
    if (from != null && day.isBefore(from)) return false;
    if (to != null && day.isAfter(to)) return false;
    return true;
  }).toList();

  if (active.isNotEmpty) {
    final totalSpent = active.fold(0, (sum, b) => sum + b.spent.minorUnits.clamp(0, 1 << 62));
    final todayShare = spentTodayMinor.clamp(0, totalSpent);
    var allowance = 0.0;
    for (final b in active) {
      final spent = b.spent.minorUnits.clamp(0, 1 << 62);
      final spentToday = totalSpent == 0 ? 0.0 : todayShare * spent / totalSpent;
      final remaining = b.limit.minorUnits - (spent - spentToday);
      final days = daysUntil(DateTime.tryParse(b.periodTo ?? '') ?? monthEnd);
      if (remaining > 0 && days > 0) allowance += remaining / days;
    }
    return allowance.round();
  }

  final month = dashboard?.thisMonth;
  if (month == null || month.income.minorUnits <= 0 || month.income.currency != currency) return null;
  final spent = month.expense.minorUnits.abs();
  final remaining = month.income.minorUnits - (spent - spentTodayMinor).clamp(0, spent);
  if (remaining <= 0) return 0;
  return remaining ~/ daysUntil(monthEnd);
}

/// Consecutive days, ending today (or yesterday if nothing is logged yet
/// today), with at least one logged transaction.
int loggingStreak({required DateTime now, DailySummary? today, List<DailySummary> history = const []}) {
  String key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  final active = <String>{
    for (final s in history)
      if (s.transactionCount > 0 && s.date.length >= 10) s.date.substring(0, 10),
    if (today != null && today.transactionCount > 0) key(now),
  };

  var cursor = DateTime(now.year, now.month, now.day);
  if (!active.contains(key(cursor))) cursor = cursor.subtract(const Duration(days: 1));
  var streak = 0;
  while (active.contains(key(cursor))) {
    streak++;
    cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
  }
  return streak;
}

/// `MK 9,850`: currency symbol and whole units (the widget has no room for
/// tambala).
String formatWholeMoney(int minorUnits, String currency) {
  final symbol = currencyInfo(currency).symbol;
  final negative = minorUnits < 0;
  return '${negative ? '-' : ''}$symbol ${_group((minorUnits.abs() / 100).round())}';
}

String _signedAmount(RecentTxn txn) {
  final whole = _group((txn.amount.minorUnits.abs() / 100).round());
  return txn.isIncome ? '+$whole' : '-$whole';
}

String _group(int value) =>
    value.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

String _ellipsize(String text, int max) =>
    text.length <= max ? text : '${text.substring(0, max - 1).trimRight()}…';
