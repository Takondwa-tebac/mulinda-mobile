import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mulinda_mobile/features/activity/data/activity_models.dart';
import 'package:mulinda_mobile/features/analytics/data/analytics_models.dart';
import 'package:mulinda_mobile/features/analytics/data/analytics_repository.dart';

/// The `data` object of a contract fixture in `test/fixtures/analytics`.
Map<String, dynamic> analyticsFixture(String name) {
  final json = jsonDecode(File('test/fixtures/analytics/$name.json').readAsStringSync()) as Map<String, dynamic>;
  return (json['data'] as Map).cast<String, dynamic>();
}

AnalyticsSummary fixtureSummary([String name = 'summary_last_30_days']) =>
    AnalyticsSummary.fromJson(analyticsFixture(name));

CategoryBreakdown fixtureBreakdown(ReportKind kind) =>
    CategoryBreakdown.fromJson(analyticsFixture(kind == ReportKind.income ? 'categories_income' : 'categories_expense'));

CategoryDetail fixtureDetail([String name = 'category_detail_food']) => CategoryDetail.fromJson(analyticsFixture(name));

Txn fixtureTxn(String id, {String type = 'expense', int major = 1500, String merchant = 'Shoprite'}) => Txn.fromJson({
  'id': id,
  'type': type,
  'amount': {'minor_units': major * 100, 'currency': 'MWK', 'amount': major, 'formatted': 'MK $major.00'},
  'merchant': merchant,
  'occurred_at': '2026-11-21T10:00:00Z',
  'category': {'id': 'c-food', 'name': 'Food', 'icon': 'restaurant', 'color': '#E67E22', 'is_spending': true},
});

/// Every analytics provider answered from fixtures (or the given values), so
/// screens render without a network. Records the queries the payment lists
/// asked for in [queries].
List<Override> analyticsOverrides({
  AnalyticsSummary Function(PeriodSelection p)? summary,
  CategoryBreakdown Function(BreakdownKey k)? categories,
  CategoryDetail Function(CategoryDetailKey k)? detail,
  TxnContext? context,
  List<TxnQuery>? queries,
}) => [
  analyticsSummaryProvider.overrideWith((ref, p) async => summary?.call(p) ?? fixtureSummary()),
  analyticsCategoriesProvider.overrideWith((ref, k) async => categories?.call(k) ?? fixtureBreakdown(k.kind)),
  analyticsCategoryDetailProvider.overrideWith((ref, k) async => detail?.call(k) ?? fixtureDetail()),
  transactionContextProvider.overrideWith(
    (ref, k) async => context ?? TxnContext.parse(analyticsFixture('transaction_context')['context']),
  ),
  reportTransactionsProvider.overrideWith((ref, q) async {
    queries?.add(q);
    return TxnPage(items: [fixtureTxn('t1'), fixtureTxn('t2', major: 2500)], page: 1, hasMore: false);
  }),
];
