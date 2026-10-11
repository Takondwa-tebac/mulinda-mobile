import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/features/activity/data/activity_repository.dart';
import 'package:mulinda_mobile/features/plan/data/plan_models.dart';

class _Recorder implements HttpClientAdapter {
  RequestOptions? last;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    last = o;
    return ResponseBody.fromString(jsonEncode({'data': []}), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('a budget knows its category and the period the server is measuring', () {
    final b = BudgetItem.fromJson({
      'id': 'b1',
      'name': 'Groceries',
      'category_id': 'c1',
      'category': {'id': 'c1', 'name': 'Food'},
      'period': 'monthly',
      'limit': {'minor_units': 100000, 'currency': 'MWK', 'amount': 1000, 'formatted': 'MK 1,000'},
      'status': {
        'from': '2026-10-01',
        'to': '2026-10-31',
        'spent': {'minor_units': 25000, 'currency': 'MWK', 'amount': 250, 'formatted': 'MK 250'},
        'percentage': 25,
      },
    });

    expect(b.categoryName, 'Food');
    expect(b.periodFrom, '2026-10-01');
    expect(b.periodTo, '2026-10-31');
  });

  test('the spend list asks for expenses in the period, to the end of the last day', () async {
    final adapter = _Recorder();
    final repo = ActivityRepository(Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = adapter);

    await repo.expensesForPeriod(categoryId: 'c1', from: '2026-10-01', to: '2026-10-31');

    final q = adapter.last!.queryParameters;
    expect(q['type'], 'expense');
    expect(q['category_id'], 'c1');
    expect(q['from'], '2026-10-01');
    expect(q['to'], '2026-10-31T23:59:59');
    expect(q['include_children'], 1);
  });

  test('a budget without a category asks for all expenses', () async {
    final adapter = _Recorder();
    final repo = ActivityRepository(Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = adapter);

    await repo.expensesForPeriod(from: '2026-10-01', to: '2026-10-31');

    expect(adapter.last!.queryParameters.containsKey('category_id'), false);
  });
}
