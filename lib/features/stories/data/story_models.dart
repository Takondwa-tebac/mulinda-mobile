import 'package:flutter/material.dart';

import '../../../core/money/money.dart';

/// The two stories: "My month in money" and "My year in money".
enum StoryKind {
  month,
  year;

  /// `month` or `year` (as in push data and analytics), null for anything else.
  static StoryKind? fromName(String? name) => switch (name) {
    'month' => StoryKind.month,
    'year' => StoryKind.year,
    _ => null,
  };
}

/// Whether [key] is a valid period key for [kind]: `2026-10` for a month,
/// `2026` for a year.
bool isValidStoryKey(StoryKind kind, String key) => switch (kind) {
  StoryKind.month => RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(key),
  StoryKind.year => RegExp(r'^\d{4}$').hasMatch(key),
};

/// The money style a story ends with. The API sends the slug; the app owns
/// the title and the one-line description (en and ny).
enum MoneyStyle {
  steadyPlanner('steady_planner', Icons.star_rounded),
  saver('saver', Icons.savings_rounded),
  familyBuilder('family_builder', Icons.home_rounded),
  foodie('foodie', Icons.restaurant_rounded),
  explorer('explorer', Icons.explore_rounded),
  everydayManager('everyday_manager', Icons.account_balance_wallet_rounded);

  const MoneyStyle(this.slug, this.icon);

  final String slug;
  final IconData icon;

  /// Translation key of the title ("The Steady Planner").
  String get titleKey => 'stories.style.$slug.title';

  /// Translation key of the one-line description.
  String get descriptionKey => 'stories.style.$slug.body';

  /// The style for an API slug; null when the slug is missing or unknown (the
  /// slide is then left out rather than showing a style the API did not pick).
  static MoneyStyle? fromSlug(String? slug) {
    for (final s in values) {
      if (s.slug == slug) return s;
    }
    return null;
  }
}

Money? _money(Object? v) => v is Map ? Money.fromJson(v.cast<String, dynamic>()) : null;

double? _double(Object? v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');

int? _int(Object? v) => v is num ? v.toInt() : int.tryParse(v?.toString() ?? '');

String? _str(Object? v) {
  final s = v?.toString();
  return s == null || s.isEmpty ? null : s;
}

DateTime? _date(Object? v) {
  final s = _str(v);
  return s == null ? null : DateTime.tryParse(s);
}

Map<String, dynamic>? _map(Object? v) => v is Map ? v.cast<String, dynamic>() : null;

/// The days a story covers.
class StoryPeriod {
  const StoryPeriod({required this.type, required this.key, this.startsOn, this.endsOn});

  final StoryKind type;

  /// `2026-10` for a month, `2026` for a year.
  final String key;
  final DateTime? startsOn;
  final DateTime? endsOn;

  /// The year the period is in.
  int get year => int.tryParse(key.split('-').first) ?? startsOn?.year ?? 0;

  /// The month (1 to 12) of a month period; null for a year.
  int? get month => type == StoryKind.month && key.length >= 7 ? int.tryParse(key.substring(5, 7)) : null;

  factory StoryPeriod.fromJson(Map<String, dynamic> json) => StoryPeriod(
    type: StoryKind.fromName(_str(json['type'])) ?? StoryKind.month,
    key: _str(json['key']) ?? '',
    startsOn: _date(json['starts_on']),
    endsOn: _date(json['ends_on']),
  );
}

/// One of the biggest spending categories.
class StoryCategory {
  const StoryCategory({required this.slug, required this.name, required this.amount, required this.share});

  final String? slug;
  final String name;
  final Money amount;

  /// Of all spending in the period (0..1).
  final double share;

  factory StoryCategory.fromJson(Map<String, dynamic> json) => StoryCategory(
    slug: _str(json['slug']),
    name: _str(json['name']) ?? '',
    amount: Money.parse(json['amount']),
    share: (_double(json['share']) ?? 0).clamp(0.0, 1.0),
  );
}

/// The day with the most spending.
class StoryDay {
  const StoryDay({required this.date, required this.amount, required this.share});

  final DateTime date;
  final Money amount;
  final double share;

  static StoryDay? fromJson(Map<String, dynamic>? json) {
    final date = _date(json?['date']);
    if (json == null || date == null) return null;
    return StoryDay(date: date, amount: Money.parse(json['amount']), share: (_double(json['share']) ?? 0).clamp(0.0, 1.0));
  }
}

/// Spending against the period before. A negative ratio means less was spent.
class StoryChange {
  const StoryChange({required this.previousKey, required this.ratio});

  final String? previousKey;
  final double ratio;

  /// The change in whole percent, without the sign.
  int get percent => (ratio.abs() * 100).round();

  bool get isLess => ratio < 0 && percent > 0;
  bool get isMore => ratio > 0 && percent > 0;

  static StoryChange? fromJson(Map<String, dynamic>? json) {
    final ratio = _double(json?['ratio']);
    if (json == null || ratio == null) return null;
    return StoryChange(previousKey: _str(json['previous_key']), ratio: ratio);
  }
}

/// Budgets kept within their limit in the period.
class StoryBudgets {
  const StoryBudgets({required this.kept, required this.total});

  final int kept;
  final int total;

  static StoryBudgets? fromJson(Map<String, dynamic>? json) {
    final total = _int(json?['total']) ?? 0;
    if (json == null || total <= 0) return null;
    return StoryBudgets(kept: _int(json['kept']) ?? 0, total: total);
  }
}

/// A person or a place, and how many times.
class StoryNamedCount {
  const StoryNamedCount({required this.name, required this.count, this.topWeekday});

  final String name;
  final int count;

  /// The weekday with the most visits (`saturday`); year story merchants only.
  final String? topWeekday;

  static StoryNamedCount? fromJson(Map<String, dynamic>? json) {
    final name = _str(json?['name']);
    if (json == null || name == null) return null;
    return StoryNamedCount(name: name, count: _int(json['count']) ?? 0, topWeekday: _str(json['top_weekday']));
  }
}

/// Goals completed in the period.
class StoryGoals {
  const StoryGoals({required this.count, required this.names, this.saved});

  final int count;
  final List<String> names;
  final Money? saved;

  static StoryGoals? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final names = json['names'] is List ? [for (final n in json['names'] as List) ?n?.toString()] : <String>[];
    return StoryGoals(count: _int(json['count']) ?? 0, names: names, saved: _money(json['saved']));
  }
}

/// One month's column in the year story.
class StoryMonthBar {
  const StoryMonthBar({required this.key, required this.spending, required this.shareOfMax});

  final String key;
  final Money spending;

  /// Height next to the biggest month (which is 1).
  final double shareOfMax;

  int get month => int.tryParse(key.length >= 7 ? key.substring(5, 7) : '') ?? 1;

  factory StoryMonthBar.fromJson(Map<String, dynamic> json) => StoryMonthBar(
    key: _str(json['key']) ?? '',
    spending: Money.parse(json['spending']),
    shareOfMax: (_double(json['share_of_max']) ?? 0).clamp(0.0, 1.0),
  );
}

/// `GET stories/month` and `GET stories/year`: the figures a story shows.
/// Every field but [period] and [available] may be null; a slide whose data
/// is null is left out.
class MoneyStory {
  const MoneyStory({
    required this.period,
    required this.available,
    this.messagesRecorded,
    this.transactionsCount,
    this.income,
    this.spending,
    this.keptRatio,
    this.topCategories = const [],
    this.biggestDay,
    this.changeVsPrevious,
    this.budgets,
    this.moneyStyle,
    this.topCounterparty,
    this.topMerchant,
    this.goalsReached,
    this.months = const [],
    this.biggestMonth,
    this.messagesPerDay,
  });

  final StoryPeriod period;

  /// Enough transactions in the period for a story (10 or more).
  final bool available;
  final int? messagesRecorded;
  final int? transactionsCount;
  final Money? income;
  final Money? spending;

  /// (income - spending) / income, from -1 to 1; null with no income.
  final double? keptRatio;
  final List<StoryCategory> topCategories;
  final StoryDay? biggestDay;
  final StoryChange? changeVsPrevious;
  final StoryBudgets? budgets;
  final MoneyStyle? moneyStyle;
  final StoryNamedCount? topCounterparty;
  final StoryNamedCount? topMerchant;
  final StoryGoals? goalsReached;

  /// Year story: spending per covered month.
  final List<StoryMonthBar> months;

  /// Year story: `2026-03`.
  final String? biggestMonth;

  /// Year story: money messages per day, on average.
  final double? messagesPerDay;

  StoryKind get kind => period.type;

  factory MoneyStory.fromJson(Map<String, dynamic> json) {
    final cats = json['top_categories'];
    final months = json['months'];
    return MoneyStory(
      period: StoryPeriod.fromJson(_map(json['period']) ?? const {}),
      available: json['available'] == true,
      messagesRecorded: _int(json['messages_recorded']),
      transactionsCount: _int(json['transactions_count']),
      income: _money(json['income']),
      spending: _money(json['spending']),
      keptRatio: _double(json['kept_ratio'])?.clamp(-1.0, 1.0),
      topCategories: cats is List
          ? [
              for (final c in cats)
                if (c is Map) StoryCategory.fromJson(c.cast<String, dynamic>()),
            ].where((c) => c.name.isNotEmpty).toList()
          : const [],
      biggestDay: StoryDay.fromJson(_map(json['biggest_day'])),
      changeVsPrevious: StoryChange.fromJson(_map(json['change_vs_previous'])),
      budgets: StoryBudgets.fromJson(_map(json['budgets'])),
      moneyStyle: MoneyStyle.fromSlug(_str(json['money_style'])),
      topCounterparty: StoryNamedCount.fromJson(_map(json['top_counterparty'])),
      topMerchant: StoryNamedCount.fromJson(_map(json['top_merchant'])),
      goalsReached: StoryGoals.fromJson(_map(json['goals_reached'])),
      months: months is List
          ? [
              for (final m in months)
                if (m is Map) StoryMonthBar.fromJson(m.cast<String, dynamic>()),
            ]
          : const [],
      biggestMonth: _str(json['biggest_month']),
      messagesPerDay: _double(json['messages_per_day']),
    );
  }
}

/// `GET stories/year/status`: the countdown to the year story.
class YearStoryStatus {
  const YearStoryStatus({
    required this.year,
    required this.releaseAt,
    required this.countdownFrom,
    required this.daysLeft,
    required this.ready,
    required this.viewed,
    required this.remindersEnabled,
  });

  final int year;
  final DateTime? releaseAt;
  final DateTime? countdownFrom;
  final int daysLeft;
  final bool ready;
  final bool viewed;
  final bool remindersEnabled;

  YearStoryStatus copyWith({bool? viewed, bool? remindersEnabled}) => YearStoryStatus(
    year: year,
    releaseAt: releaseAt,
    countdownFrom: countdownFrom,
    daysLeft: daysLeft,
    ready: ready,
    viewed: viewed ?? this.viewed,
    remindersEnabled: remindersEnabled ?? this.remindersEnabled,
  );

  factory YearStoryStatus.fromJson(Map<String, dynamic> json) => YearStoryStatus(
    year: _int(json['year']) ?? 0,
    // The release moment in Blantyre time; shown as that calendar day.
    releaseAt: _date(json['release_at']),
    countdownFrom: _date(json['countdown_from']),
    daysLeft: (_int(json['days_left']) ?? 0).clamp(0, 366),
    ready: json['ready'] == true,
    viewed: json['viewed'] == true,
    remindersEnabled: json['reminders_enabled'] != false,
  );
}
