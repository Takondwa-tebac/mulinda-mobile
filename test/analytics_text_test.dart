import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/features/analytics/data/analytics_models.dart';
import 'package:mulinda_mobile/features/analytics/presentation/analytics_text.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/analytics_fakes.dart';

class _FileLoader extends AssetLoader {
  const _FileLoader();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('assets/translations/${locale.languageCode}.json').readAsStringSync()) as Map<String, dynamic>;
}

Future<void> _english(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('ny')],
        startLocale: const Locale('en'),
        fallbackLocale: const Locale('en'),
        path: 'assets/translations',
        assetLoader: const _FileLoader(),
        child: Builder(
          builder: (context) => MaterialApp(
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });
  await tester.pumpAndSettle();
}

const _nbsp = ' ';
String _plain(String s) => s.replaceAll(_nbsp, ' ');

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('insight keys and params become the approved sentences', (tester) async {
    await _english(tester);
    final b = fixtureBreakdown(ReportKind.expense);
    final words = {for (final i in b.insights) i.key: insightWords(i, period: b.period)};

    expect(_plain(words['categoryUp']!.title), 'You spent 19% more on Transport than in the previous 30 days.');
    expect(_plain(words['categoryUp']!.body!), 'MK 41,300, up from MK 34,700.');
    expect(words['categoryUp']!.actionLabel, 'See Transport');
    expect(_plain(words['biggestCategory']!.title), 'Food is your biggest expense: 35% of your spending.');
    expect(_plain(words['topThreeShare']!.title), 'Food, Rent and Transport are 70% of your spending.');
    expect(words['topThreeShare']!.actionLabel, isNull);

    // Without show_pct the change is said without a percentage.
    final noPct = Insight.fromJson({
      'key': 'categoryDown',
      'params': {'category': 'Food', 'pct': 8.1, 'show_pct': false, 'days': 30},
    });
    expect(insightWords(noPct, period: b.period)!.title, 'You spent less on Food than in the previous 30 days.');

    final s = fixtureSummary();
    final day = s.insights.firstWhere((i) => i.key == 'biggestDay');
    expect(_plain(insightWords(day)!.title), '1 Nov was your biggest day: MK 64,300.');
    expect(insightWords(day)!.body, 'Most of it was Rent.');
    final typical = s.insights.firstWhere((i) => i.key == 'typicalDay');
    expect(_plain(insightWords(typical)!.title), 'On a typical day you spent MK 5,400.');

    final income = fixtureBreakdown(ReportKind.income).insights.single;
    expect(insightWords(income, kind: ReportKind.income)!.title, 'Most of your income (86%) comes from Salary.');

    // A key this version does not know is left out.
    expect(insightWords(const Insight(key: 'someFutureKey')), isNull);
  });

  testWidgets('comparisons follow the rules for amounts, percentages and words', (tester) async {
    await _english(tester);
    final s = fixtureSummary();
    final c = comparisonWords(s.expenseComparison, s.period)!;
    expect(c.icon, ComparisonIcon.down);
    expect(_plain(c.text), 'MK 27,500 less than the previous 30 days (MK 312,900).');
    expect(_plain(comparisonWords(s.expenseComparison, s.period, hero: true)!.text),
        'You spent MK 27,500 less than the previous 30 days.');

    final today = fixtureSummary('summary_today_empty');
    expect(comparisonWords(today.expenseComparison, today.period)!.text,
        'Today is not over yet, so we do not compare it with other days.');
    expect(comparisonWords(today.expenseComparison, today.period, hero: true), isNull);

    final thin = fixtureBreakdown(ReportKind.income);
    expect(comparisonWords(thin.comparison, thin.period)!.text,
        'Not enough history to compare with the previous 30 days yet.');

    Comparison up(double pct) => Comparison.fromJson({
      'comparable': true,
      'previous': {'from': '2026-11-09', 'to': '2026-11-15', 'amount': {'minor_units': 3590000, 'formatted_whole': 'MK 35,900'}},
      'difference': {'minor_units': 3480000, 'formatted_whole': 'MK 34,800'},
      'direction': 'up',
      'pct': pct,
      'show_pct': true,
    });
    const week = AnalyticsPeriod(key: PeriodKey.thisWeek, days: 7, elapsedDays: 7, inProgress: true);
    expect(_plain(comparisonWords(up(97), week)!.text),
        'Almost twice as much as the same days of last week (MK 35,900): MK 34,800 more.');
    expect(_plain(comparisonWords(up(19), week)!.text), '19% more than the same days of last week (MK 35,900).');
    // A complete month compares with the whole previous month.
    const october = AnalyticsPeriod(key: PeriodKey.thisMonth, days: 31, elapsedDays: 31);
    expect(_plain(comparisonWords(up(19), october)!.text), '19% more than the previous month (MK 35,900).');
  });

  testWidgets('period labels', (tester) async {
    await _english(tester);
    final s = fixtureSummary();
    expect(periodTitle(PeriodSelection.defaultPeriod, s.period), 'Last 30 days');
    expect(periodRange(s.period), '24 Oct to 22 Nov');
    expect(periodWhen(PeriodSelection.defaultPeriod, s.period), 'in the last 30 days');
    final thin = fixtureBreakdown(ReportKind.income).period;
    expect(periodWhen(PeriodSelection.defaultPeriod, thin), 'since 17 Nov');
    final today = fixtureSummary('summary_today_empty').period;
    expect(periodRange(today), startsWith('Sun 22 Nov'));
    expect(periodRange(today), endsWith('not over yet'));
  });

  test('no em or en dashes in the analytics strings', () {
    for (final lang in ['en', 'ny']) {
      final json = jsonDecode(File('assets/translations/$lang.json').readAsStringSync()) as Map<String, dynamic>;
      final text = jsonEncode(json['analytics']);
      expect(text.contains('—') || text.contains('–'), isFalse, reason: lang);
    }
  });
}
