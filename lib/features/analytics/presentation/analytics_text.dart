import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/money/money.dart';
import '../data/analytics_models.dart';

// Every sentence on the report screens is built here from what the API sent:
// rule keys and parameters in, translated text out. No figure is computed.

/// Keeps "MK 285,400" on one line inside a sentence.
String nb(String text) => text.replaceAll(' ', ' ');

/// A money amount for a sentence: whole kwacha, never split across lines.
String moneyWords(Money? m) => m == null ? '' : nb(m.whole);

String _tr(String key, [Map<String, String>? args]) => key.tr(namedArgs: args);

/// `key.plural(count)` with named arguments that never throws (widget tests
/// run without localization started).
String trPlural(String key, int count, [Map<String, String> args = const {}]) {
  final named = {'count': '$count', ...args};
  try {
    return key.plural(count, namedArgs: named);
  } catch (_) {
    return key.tr(namedArgs: named);
  }
}

/// `24 Oct` (plus the year when it is not this year).
String fmtDay(DateTime d, {DateTime? now}) {
  final year = d.year == (now ?? DateTime.now()).year ? '' : ' ${d.year}';
  return '${d.day} ${'common.monthShort.${d.month}'.tr()}$year';
}

/// `Sun 22 Nov`.
String fmtWeekday(DateTime d, {DateTime? now}) => '${'common.weekdayShort.${d.weekday}'.tr()} ${fmtDay(d, now: now)}';

/// `Oct`.
String fmtMonthShort(DateTime d) => 'common.monthShort.${d.month}'.tr();

/// `October` (plus the year when it is not this year).
String fmtMonthLong(DateTime d, {DateTime? now}) {
  final year = d.year == (now ?? DateTime.now()).year ? '' : ' ${d.year}';
  return '${'common.monthLong.${d.month}'.tr()}$year';
}

/// "Uncategorised" for a row without a name.
String categoryName(String? name) => (name == null || name.trim().isEmpty) ? 'analytics.uncategorised'.tr() : name;

/// "Food, Rent and Transport".
String listAnd(List<String> items) {
  if (items.isEmpty) return '';
  if (items.length == 1) return items.first;
  return _tr('analytics.listAnd', {'a': items.sublist(0, items.length - 1).join(', '), 'b': items.last});
}

/// Short name of a period for the stepper title ("Last 30 days", "This
/// month so far", "October").
String periodTitle(PeriodSelection sel, [AnalyticsPeriod? p]) {
  final from = p?.from;
  final inProgress = p?.inProgress ?? sel.offset == 0;
  switch (sel.key) {
    case PeriodKey.today:
      if (sel.offset == 0) return 'analytics.label.todaySoFar'.tr();
      return from == null ? 'analytics.period.today'.tr() : fmtWeekday(from);
    case PeriodKey.thisWeek:
      if (sel.offset == 0 && inProgress) return 'analytics.label.weekSoFar'.tr();
      return from == null ? 'analytics.period.this_week'.tr() : _tr('analytics.label.weekOf', {'date': fmtDay(from)});
    case PeriodKey.thisMonth:
      if (sel.offset == 0 && inProgress) return 'analytics.label.monthSoFar'.tr();
      return from == null ? 'analytics.period.this_month'.tr() : fmtMonthLong(from);
    case PeriodKey.lastMonth:
      return from == null ? 'analytics.period.last_month'.tr() : fmtMonthLong(from);
    case PeriodKey.last30Days:
      return sel.offset == 0 ? 'analytics.label.last30'.tr() : 'analytics.label.thirtyDays'.tr();
    case PeriodKey.custom:
      return 'analytics.period.custom'.tr();
  }
}

/// The dates of a period ("24 Oct to 22 Nov", "Sun 22 Nov, not over yet",
/// "1 Nov to 30 Nov, 22 of 30 days so far").
String periodRange(AnalyticsPeriod p) {
  final from = p.from;
  final to = p.to;
  if (from == null || to == null) return '';
  if (from == to) {
    final day = fmtWeekday(from);
    return p.inProgress ? _tr('analytics.range.notOver', {'day': day}) : day;
  }
  final span = _tr('analytics.range.span', {'from': fmtDay(from), 'to': fmtDay(to)});
  if (p.inProgress && p.elapsedDays > 0 && p.elapsedDays < p.days) {
    return _tr('analytics.range.daysSoFar', {'range': span, 'elapsed': '${p.elapsedDays}', 'days': '${p.days}'});
  }
  return span;
}

/// "Last 30 days, 24 Oct to 22 Nov": a period named in full, for chips.
String periodChipLabel(PeriodSelection sel, [AnalyticsPeriod? p]) {
  final range = p == null ? '' : periodRange(p);
  final title = periodTitle(sel, p);
  return range.isEmpty ? title : '$title, $range';
}

/// When the figure happened, for the line under a headline ("in the last 30
/// days", "this month so far", "since 17 Nov").
String periodWhen(PeriodSelection sel, AnalyticsPeriod p) {
  if (p.partlyCovered) return _tr('analytics.when.since', {'date': fmtDay(p.coverageFrom!)});
  final from = p.from;
  final to = p.to;
  String range() =>
      from == null || to == null ? '' : _tr('analytics.when.range', {'from': fmtDay(from), 'to': fmtDay(to)});
  if (sel.offset == 0) {
    switch (sel.key) {
      case PeriodKey.today:
        return 'analytics.when.today'.tr();
      case PeriodKey.thisWeek:
        return 'analytics.when.thisWeek'.tr();
      case PeriodKey.thisMonth:
        return 'analytics.when.thisMonth'.tr();
      case PeriodKey.last30Days:
        return 'analytics.when.last30'.tr();
      case PeriodKey.lastMonth:
        return from == null ? range() : _tr('analytics.when.month', {'month': fmtMonthLong(from)});
      case PeriodKey.custom:
        return range();
    }
  }
  if ((sel.key == PeriodKey.thisMonth || sel.key == PeriodKey.lastMonth) && from != null) {
    return _tr('analytics.when.month', {'month': fmtMonthLong(from)});
  }
  if (sel.key == PeriodKey.today && from != null) return _tr('analytics.when.on', {'date': fmtWeekday(from)});
  return range();
}

/// What a period is compared with ("the previous 30 days", "the same days of
/// last month").
String previousPhrase(AnalyticsPeriod p, {int? days}) {
  switch (p.key) {
    case PeriodKey.thisWeek:
      return (p.inProgress ? 'analytics.prev.weekSameDays' : 'analytics.prev.week').tr();
    case PeriodKey.thisMonth:
      return (p.inProgress ? 'analytics.prev.monthSameDays' : 'analytics.prev.month').tr();
    case PeriodKey.lastMonth:
      return 'analytics.prev.month'.tr();
    case PeriodKey.today:
      return 'analytics.prev.day'.tr();
    case PeriodKey.last30Days:
    case PeriodKey.custom:
    case null:
      final n = days ?? p.days;
      return _tr('analytics.prev.days', {'days': '$n'});
  }
}

/// Which arrow a comparison line shows. Up and down share one neutral colour:
/// spending more is not marked as bad.
enum ComparisonIcon { up, down, same, info }

class ComparisonWords {
  const ComparisonWords(this.icon, this.text);

  final ComparisonIcon icon;
  final String text;
}

/// The sentence for a comparison, or null when nothing should be said.
///
/// [hero] is the short Home form ("You spent MK 27,500 less than the previous
/// 30 days."), which says nothing when the figure is not comparable.
ComparisonWords? comparisonWords(Comparison c, AnalyticsPeriod p, {bool hero = false}) {
  final prev = previousPhrase(p);
  if (!c.comparable) {
    if (hero) return null;
    if (c.dayInProgress) return ComparisonWords(ComparisonIcon.info, 'analytics.cmp.dayInProgress'.tr());
    if (c.insufficientHistory) {
      return ComparisonWords(ComparisonIcon.info, _tr('analytics.cmp.notEnoughHistory', {'prev': prev}));
    }
    return null;
  }
  final direction = c.direction ?? ComparisonDirection.same;
  // Nothing recorded before: say so rather than "(MK 0)" or a percentage.
  if (c.previousAmount != null && c.previousAmount!.minorUnits == 0) {
    if (direction == ComparisonDirection.same) {
      return hero ? null : ComparisonWords(ComparisonIcon.same, _tr('analytics.cmp.bothNothing', {'prev': prev}));
    }
    return ComparisonWords(
      ComparisonIcon.info,
      _tr('analytics.cmp.fromNothing', {'prev': prev}),
    );
  }
  final previous = moneyWords(c.previousAmount);
  final difference = moneyWords(c.difference);
  final pct = c.pct?.abs().round();
  final icon = switch (direction) {
    ComparisonDirection.up => ComparisonIcon.up,
    ComparisonDirection.down => ComparisonIcon.down,
    ComparisonDirection.same => ComparisonIcon.same,
  };
  final args = {'prev': prev, 'previous': previous, 'difference': difference, 'pct': '${pct ?? ''}'};
  if (direction == ComparisonDirection.same) {
    return ComparisonWords(icon, _tr(hero ? 'analytics.cmp.heroSame' : 'analytics.cmp.same', args));
  }
  final up = direction == ComparisonDirection.up;
  final usePct = c.showPct && pct != null;
  if (hero) {
    final key = usePct
        ? (up ? 'analytics.cmp.heroMorePct' : 'analytics.cmp.heroLessPct')
        : (up ? 'analytics.cmp.heroMore' : 'analytics.cmp.heroLess');
    return ComparisonWords(icon, _tr(key, args));
  }
  // Above 90% a percentage reads badly: say it in words, with both amounts.
  if (usePct && up && pct >= 90) {
    final key = pct < 100
        ? 'analytics.cmp.almostTwice'
        : (pct < 150 ? 'analytics.cmp.aboutTwice' : 'analytics.cmp.moreThanTwice');
    return ComparisonWords(icon, _tr(key, args));
  }
  final key = usePct ? (up ? 'analytics.cmp.morePct' : 'analytics.cmp.lessPct') : (up ? 'analytics.cmp.more' : 'analytics.cmp.less');
  return ComparisonWords(icon, _tr(key, args));
}

/// An insight ready to show.
class InsightWords {
  const InsightWords({required this.icon, required this.title, this.body, this.actionLabel});

  final IconData icon;
  final String title;
  final String? body;

  /// Set when the insight leads somewhere (its target).
  final String? actionLabel;
}

String _param(Insight i, String key) {
  final v = i.params[key];
  if (v is Map) return moneyWords(Money.parse(v));
  if (v is num) return '${v.round()}';
  return v?.toString() ?? '';
}

bool _isZeroMoney(Object? v) => v is Map && Money.parse(v).minorUnits == 0;

/// What a category insight compares with. Calendar periods are named
/// ("the previous month", "the previous week", "the day before") whatever
/// day count the insight carries; only the last 30 days and a custom range
/// say "the previous N days".
String insightPreviousPhrase(AnalyticsPeriod? period, int? days) {
  switch (period?.key) {
    case PeriodKey.today:
    case PeriodKey.thisWeek:
    case PeriodKey.thisMonth:
    case PeriodKey.lastMonth:
      return previousPhrase(period!);
    case PeriodKey.last30Days:
    case PeriodKey.custom:
    case null:
      final n = days ?? period?.days;
      return n == null ? 'analytics.prev.before'.tr() : _tr('analytics.prev.days', {'days': '$n'});
  }
}

bool _has(Insight i, String key) => i.params[key] != null && '${i.params[key]}'.isNotEmpty;

/// The wording of a server insight (`analytics.insight.<key>`). Null for a
/// key this version of the app does not know, so it is left out.
InsightWords? insightWords(Insight i, {AnalyticsPeriod? period, ReportKind kind = ReportKind.expense}) {
  String t(String suffix, [Map<String, String> extra = const {}]) => _tr('analytics.insight.${i.key}.$suffix', extra);
  final category = categoryName(i.params['category']?.toString());
  final hasTarget = i.target != null;
  switch (i.key) {
    case 'biggestCategory':
      return InsightWords(
        icon: Icons.donut_large,
        title: t('title', {'category': category, 'pct': _param(i, 'share_pct')}),
        body: _has(i, 'amount') ? t('body', {'amount': _param(i, 'amount')}) : null,
        actionLabel: hasTarget ? _tr('analytics.insight.seeCategory', {'category': category}) : null,
      );
    case 'topThreeShare':
      final names = (i.params['categories'] as List?)?.map((e) => categoryName(e?.toString())).toList() ?? const [];
      if (names.isEmpty) return null;
      return InsightWords(
        icon: Icons.pie_chart_outline,
        title: t('title', {'categories': listAnd(names), 'pct': _param(i, 'share_pct')}),
        body: t('body'),
      );
    case 'categoryUp':
    case 'categoryDown':
      final up = i.key == 'categoryUp';
      final prev = insightPreviousPhrase(period, int.tryParse(_param(i, 'days')));
      // Nothing before: a percentage means nothing and "(MK 0)" reads badly.
      final fromNothing = _isZeroMoney(i.params['previous']);
      final showPct = i.params['show_pct'] == true && _has(i, 'pct') && !fromNothing;
      final income = kind == ReportKind.income ? 'Income' : '';
      final args = {'category': category, 'pct': '${(num.tryParse(_param(i, 'pct')) ?? 0).abs().round()}', 'prev': prev};
      return InsightWords(
        icon: up ? Icons.trending_up : Icons.trending_down,
        title: t(showPct ? 'title${income}Pct' : 'title$income', args),
        body: !_has(i, 'amount') || !_has(i, 'previous')
            ? null
            : fromNothing
                ? _tr('analytics.insight.bodyFromNothing', {'amount': _param(i, 'amount'), 'prev': prev})
                : t('body', {'amount': _param(i, 'amount'), 'previous': _param(i, 'previous')}),
        actionLabel: hasTarget ? _tr('analytics.insight.seeCategory', {'category': category}) : null,
      );
    case 'biggestDay':
      final day = parseDay(i.params['date']);
      final top = i.params['top_category']?.toString();
      return InsightWords(
        icon: Icons.flag_outlined,
        title: t('title', {'date': day == null ? _param(i, 'date') : fmtDay(day), 'amount': _param(i, 'amount')}),
        body: top == null || top.isEmpty ? null : t('body', {'category': top}),
        actionLabel: day != null ? 'analytics.insight.seeDay'.tr() : null,
      );
    case 'typicalDay':
      return InsightWords(
        icon: Icons.insights,
        title: t('title', {'median': _param(i, 'median')}),
        body: _has(i, 'mean') ? t('body', {'mean': _param(i, 'mean')}) : null,
      );
    case 'mostIncomeFrom':
      return InsightWords(
        icon: Icons.payments_outlined,
        title: t('title', {'source': _param(i, 'source'), 'pct': _param(i, 'share_pct')}),
      );
    case 'incomeNew':
      return InsightWords(
        icon: Icons.fiber_new_outlined,
        title: t('title', {'source': _param(i, 'source'), 'amount': _param(i, 'amount')}),
        body: t('body'),
      );
    case 'aboveTypicalToday':
      return InsightWords(
        icon: Icons.insights,
        title: t('title'),
        body: _has(i, 'median') ? t('body', {'median': _param(i, 'median')}) : null,
      );
  }
  return null;
}
