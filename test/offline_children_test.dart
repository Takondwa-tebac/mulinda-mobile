import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/core/money/money_json.dart';
import 'package:mulinda_mobile/core/offline/entity_adapters.dart';
import 'package:mulinda_mobile/core/offline/mutation_store.dart';
import 'package:mulinda_mobile/core/offline/offline_write_interceptor.dart';
import 'package:mulinda_mobile/core/offline/overlay_engine.dart';
import 'package:mulinda_mobile/core/offline/trusted_clock.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/memory_store.dart';

const goalId = '44444444-4444-4444-8444-444444444444';
const loanId = '55555555-5555-4555-8555-555555555555';
const contribId = '66666666-6666-4666-8666-666666666666';

class _Offline implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.none];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

class _DeadNetwork implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      throw DioException(requestOptions: options, type: DioExceptionType.connectionError);

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> goalJson({int current = 100000}) => {
      'id': goalId,
      'name': 'Car',
      'currency': 'MWK',
      'current': moneyJson(current / 100, 'MWK'),
      'target': moneyJson(5000, 'MWK'),
      'updated_at': '2026-10-06T08:00:00Z',
      'contributions': [
        {
          'id': contribId,
          'goal_id': goalId,
          'currency': 'MWK',
          'amount': moneyJson(300, 'MWK'),
          'contributed_at': '2026-10-01',
          'updated_at': '2026-10-02T09:00:00Z',
        },
      ],
    };

PendingMutation childMut(String id, String entity, String op, {int delta = 0, Map<String, dynamic> body = const {}, Map<String, dynamic> effect = const {}, List<String> targets = const []}) =>
    PendingMutation(
      id: id, userId: 'u1', entity: entity, op: op, targetIds: targets,
      method: 'POST', path: '/v1/goals/$goalId/contributions', body: body,
      effect: {'parent_id': goalId, 'delta_minor': delta, ...effect}, createdMs: 1,
    );

void main() {
  group('adapters for the newer records', () {
    test('contributions and repayments are recognised under their parent', () {
      final create = matchWrite('POST', '/v1/goals/$goalId/contributions', {'id': contribId})!;
      expect(create.entity, 'goal_contribution');
      expect(create.op, 'create');
      expect(create.parentId, goalId);

      final edit = matchWrite('PUT', '/v1/goals/$goalId/contributions/$contribId', {})!;
      expect(edit.op, 'update');
      expect(edit.targetIds, [contribId]);

      expect(matchWrite('DELETE', '/v1/loans/$loanId/repayments/$contribId', null)!.entity, 'loan_repayment');
      // A goal itself is still the goal adapter, not a contribution.
      expect(matchWrite('PUT', '/v1/goals/$goalId', {})!.entity, 'goal');
    });

    test('budgets, investments and projects are recognised and build API-shaped records', () async {
      expect(matchWrite('POST', '/v1/budgets', {})!.entity, 'budget');
      expect(matchWrite('POST', '/v1/investments', {})!.entity, 'investment');
      expect(matchWrite('DELETE', '/v1/projects/$goalId', null)!.entity, 'project');

      final investment = await const InvestmentAdapter().buildRecord(
        {'id': goalId, 'name': 'FD', 'type': 'fixed_deposit', 'amount_invested': 1000, 'current_value': 1100}, (_, _) async => null);
      expect(investment['gain']['formatted'], 'MK 100.00');
      expect(investment['value_source'], 'recorded');

      final budget = await const BudgetAdapter().buildRecord(
        {'id': goalId, 'period': 'monthly', 'limit': 50000, 'category_id': contribId},
        (path, id) async => {'id': id, 'name': 'Food', 'kind': 'expense'});
      expect(budget['name'], 'Food');
      expect(budget['limit']['formatted'], 'MK 50,000.00');

      final project = await const ProjectAdapter().buildRecord({'id': goalId, 'name': 'House', 'budget': 900000}, (_, _) async => null);
      expect(project['budget']['formatted'], 'MK 900,000.00');
      expect(project['remaining']['formatted'], 'MK 900,000.00');
    });

    test('the change in a parent total is worked out from the old amount', () {
      const a = GoalContributionAdapter();
      final existing = {'amount': moneyJson(300, 'MWK')};

      expect(a.deltaMinor('create', {'amount': 500}, null), 50000);
      expect(a.deltaMinor('update', {'amount': 450}, existing), 15000); // 300 -> 450
      expect(a.deltaMinor('update', {'amount': 100}, existing), -20000);
      expect(a.deltaMinor('delete', {}, existing), -30000);
    });
  });

  group('overlay of contributions and repayments', () {
    late MemoryStore store;
    late OverlayEngine overlay;

    setUp(() {
      store = MemoryStore();
      overlay = OverlayEngine(mutations: store, cache: store);
    });

    test('a queued contribution shows in the goal detail and raises the saved total', () async {
      await store.enqueue(childMut('c1', 'goal_contribution', 'create', delta: 50000, targets: ['new-c'], effect: {
        'record': {'id': 'new-c', 'amount': moneyJson(500, 'MWK'), 'currency': 'MWK'},
      }));

      final result = await overlay.apply(RequestOptions(path: '/v1/goals/$goalId'), 'u1', {'data': goalJson()}) as Map;
      final goal = result['data'] as Map;

      expect((goal['contributions'] as List).first['id'], 'new-c');
      expect((goal['contributions'] as List), hasLength(2));
      expect(goal['current']['minor_units'], 150000); // 1,000 + 500
      expect(goal['_pending'], true);
    });

    test('an edit and a delete of saved contributions adjust the total by the difference', () async {
      await store.enqueue(childMut('c1', 'goal_contribution', 'update', delta: 15000, targets: [contribId], body: {'amount': 450}));

      var goal = (await overlay.apply(RequestOptions(path: '/v1/goals/$goalId'), 'u1', {'data': goalJson()}) as Map)['data'] as Map;
      expect(goal['current']['minor_units'], 115000);
      expect(((goal['contributions'] as List).single as Map)['amount']['formatted'], 'MK 450.00');

      await store.enqueue(childMut('c2', 'goal_contribution', 'delete', delta: -45000, targets: [contribId]));
      goal = (await overlay.apply(RequestOptions(path: '/v1/goals/$goalId'), 'u1', {'data': goalJson()}) as Map)['data'] as Map;
      expect(goal['contributions'], isEmpty);
      expect(goal['current']['minor_units'], 70000);
    });

    test('the goals list moves its totals too, without needing the contributions list', () async {
      await store.enqueue(childMut('c1', 'goal_contribution', 'create', delta: 50000, effect: {
        'record': {'id': 'new-c'},
      }));
      final list = {'data': [Map.of(goalJson())..remove('contributions')]};

      final goal = ((await overlay.apply(RequestOptions(path: '/v1/goals'), 'u1', list) as Map)['data'] as List).single as Map;

      expect(goal['current']['minor_units'], 150000);
      expect(goal.containsKey('contributions'), false);
    });

    test('a repayment lowers what is still owed on the loan', () async {
      await store.enqueue(PendingMutation(
        id: 'r1', userId: 'u1', entity: 'loan_repayment', op: 'create', targetIds: const ['rp'],
        method: 'POST', path: '/v1/loans/$loanId/repayments', body: const {},
        effect: {'parent_id': loanId, 'delta_minor': 200000, 'record': {'id': 'rp', 'amount': moneyJson(2000, 'MWK')}}, createdMs: 1,
      ));
      final loan = {
        'id': loanId,
        'currency': 'MWK',
        'progress': {'outstanding': moneyJson(10000, 'MWK')},
        'repayments': <dynamic>[],
      };

      final result = (await overlay.apply(RequestOptions(path: '/v1/loans/$loanId'), 'u1', {'data': loan}) as Map)['data'] as Map;

      expect(result['progress']['outstanding']['formatted'], 'MK 8,000.00');
      expect((result['repayments'] as List).single['id'], 'rp');
    });

    test('a goal created offline opens with its contributions already included', () async {
      const pendingGoal = '77777777-7777-4777-8777-777777777777';
      await store.enqueue(PendingMutation(
        id: 'g1', userId: 'u1', entity: 'goal', op: 'create', targetIds: const [pendingGoal],
        method: 'POST', path: '/v1/goals', body: const {},
        effect: {'record': {'id': pendingGoal, 'name': 'New', 'currency': 'MWK', 'current': moneyJson(0, 'MWK'), 'contributions': <dynamic>[]}}, createdMs: 1,
      ));
      await store.enqueue(PendingMutation(
        id: 'c1', userId: 'u1', entity: 'goal_contribution', op: 'create', targetIds: const ['cc'],
        method: 'POST', path: '/v1/goals/$pendingGoal/contributions', body: const {},
        effect: {'parent_id': pendingGoal, 'delta_minor': 25000, 'record': {'id': 'cc'}}, createdMs: 2,
      ));

      final detail = await overlay.pendingDetail(RequestOptions(path: '/v1/goals/$pendingGoal'), 'u1');

      expect(detail!['data']['current']['minor_units'], 25000);
      expect((detail['data']['contributions'] as List).single['id'], 'cc');
    });

    test('versions of nested contributions are picked up from a goal detail', () {
      final v = OverlayEngine.childVersionsIn('/v1/goals/$goalId', {'data': goalJson()});
      expect(v, {
        'goal_contribution': {contribId: '2026-10-02T09:00:00Z'},
      });
      expect(OverlayEngine.childVersionsIn('/v1/goals', {'data': []}), isEmpty);
    });
  });

  group('queuing a contribution offline', () {
    late MemoryStore store;
    late Dio dio;

    setUp(() {
      store = MemoryStore();
      final overlay = OverlayEngine(mutations: store, cache: store);
      dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
        ..httpClientAdapter = _DeadNetwork()
        ..interceptors.add(OfflineWriteInterceptor(
          store: store,
          cache: store,
          overlay: overlay,
          isActive: () => true,
          currentUserId: () => 'u1',
          onQueued: () {},
          connectivity: _Offline(),
        ));
    });

    test('a new contribution is queued with its parent and the amount it adds', () async {
      await store.put('u1', 'GET /v1/goals', {'data': [goalJson()]});

      final res = await dio.post('/v1/goals/$goalId/contributions', data: {'amount': 500});

      expect(res.statusCode, 201);
      final m = store.queue.single;
      expect(m.entity, 'goal_contribution');
      expect(m.effect['parent_id'], goalId);
      expect(m.effect['delta_minor'], 50000);
      expect(m.targetIds.single, res.data['data']['id']); // got its own id
      expect(res.data['data']['amount']['formatted'], 'MK 500.00');
    });

    test('editing a saved contribution queues the difference, using its base version', () async {
      await store.put('u1', 'GET /v1/goals/$goalId', {'data': goalJson()});
      await store.putVersions('u1', 'goal_contribution', {contribId: '2026-10-02T09:00:00Z'});

      await dio.put('/v1/goals/$goalId/contributions/$contribId', data: {'amount': 450});

      final m = store.queue.single;
      expect(m.effect['delta_minor'], 15000);
      expect(m.baseUpdatedAt, '2026-10-02T09:00:00Z');
    });

    test('deleting a saved contribution queues the negative amount', () async {
      await store.put('u1', 'GET /v1/goals/$goalId', {'data': goalJson()});

      final res = await dio.delete('/v1/goals/$goalId/contributions/$contribId');

      expect(res.statusCode, 204);
      expect(store.queue.single.effect['delta_minor'], -30000);
    });
  });

  group('trusted clock', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    final t0 = DateTime(2026, 10, 6, 12);

    test('a normal clock is trusted, and winding it back is noticed', () {
      TrustedClock.observeDevice(prefs, now: t0);
      expect(TrustedClock.looksTampered(prefs, now: t0.add(const Duration(hours: 1))), false);
      expect(TrustedClock.looksTampered(prefs, now: t0.subtract(const Duration(days: 2))), true);
    });

    test('small corrections (network time sync) are tolerated', () {
      TrustedClock.observeDevice(prefs, now: t0);
      expect(TrustedClock.looksTampered(prefs, now: t0.subtract(const Duration(minutes: 3))), false);
    });

    test('the remembered time only moves forward from the phone, so a rollback cannot lower it', () {
      TrustedClock.observeDevice(prefs, now: t0);
      TrustedClock.observeDevice(prefs, now: t0.subtract(const Duration(days: 5))); // ignored
      expect(TrustedClock.looksTampered(prefs, now: t0.subtract(const Duration(days: 5))), true);
    });

    test('hearing from the server resets it, which clears the warning', () {
      TrustedClock.observeDevice(prefs, now: t0.add(const Duration(days: 30))); // far in the future
      expect(TrustedClock.looksTampered(prefs, now: t0), true);

      TrustedClock.recordServerTime(prefs, t0); // the server says it is really t0
      expect(TrustedClock.looksTampered(prefs, now: t0), false);
    });

    test('with nothing remembered yet there is nothing to compare against', () {
      expect(TrustedClock.looksTampered(prefs, now: t0), false);
    });
  });
}
