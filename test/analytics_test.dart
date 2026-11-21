import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/core/analytics/analytics.dart';
import 'package:shared_preferences/shared_preferences.dart';

DioException _http(int status) => DioException(
  requestOptions: RequestOptions(path: '/v1/analytics/events'),
  response: Response(
    requestOptions: RequestOptions(path: '/v1/analytics/events'),
    statusCode: status,
  ),
  type: DioExceptionType.badResponse,
);

DioException _offline() => DioException(
  requestOptions: RequestOptions(path: '/v1/analytics/events'),
  type: DioExceptionType.connectionError,
);

void main() {
  late SharedPreferences prefs;
  late List<Map<String, dynamic>> sent;
  Object? failWith;
  var signedIn = true;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    sent = [];
    failWith = null;
    signedIn = true;
    Analytics.resetForTest();
    Analytics.configure(
      prefs: () async => prefs,
      canSend: () => signedIn,
      sender: (body) async {
        if (failWith != null) throw failWith!;
        sent.add(body);
      },
    );
  });

  tearDown(Analytics.resetForTest);

  test('events are queued on the phone and sent in batches of 50', () async {
    for (var i = 0; i < 120; i++) {
      await Analytics.track('upgrade_prompt_viewed', {'surface': 'test'});
    }
    expect(await Analytics.pendingCount(), 120);

    final count = await Analytics.flush();

    expect(count, 120);
    expect(sent.map((b) => (b['events'] as List).length), [50, 50, 20]);
    expect(sent.first['app_version'], 'test');
    expect(await Analytics.pendingCount(), 0);
  });

  test(
    'nothing is lost while offline; the queue is sent once back online',
    () async {
      await Analytics.track('paywall_dismissed', {'surface': 'trial_banner'});
      failWith = _offline();

      expect(await Analytics.flush(), 0);
      expect(await Analytics.pendingCount(), 1);

      failWith = _http(503);
      expect(await Analytics.flush(), 0);
      expect(await Analytics.pendingCount(), 1);

      failWith = null;
      expect(await Analytics.flush(), 1);
      expect(await Analytics.pendingCount(), 0);
    },
  );

  test(
    'events wait until someone is signed in (onboarding happens before sign-in)',
    () async {
      signedIn = false;
      await Analytics.track('onboarding_completed', {'step': 4});

      expect(await Analytics.flush(), 0);
      expect(sent, isEmpty);

      signedIn = true;
      expect(await Analytics.flush(), 1);
    },
  );

  test(
    'a batch the server rejects as invalid is dropped instead of blocking the queue',
    () async {
      await Analytics.track('paywall_dismissed');
      failWith = _http(422);

      await Analytics.flush();

      expect(await Analytics.pendingCount(), 0);
    },
  );

  test('a signed-out (401) answer keeps the events for later', () async {
    await Analytics.track('paywall_dismissed');
    failWith = _http(401);

    await Analytics.flush();

    expect(await Analytics.pendingCount(), 1);
  });

  test(
    'only allow-listed names and short scalar properties are kept',
    () async {
      await Analytics.track('made_up_event');
      await Analytics.track('paywall_plan_selected', {
        'period': 'week',
        'days': 7,
        'trial_active': true,
        'email': 'someone@example.com',
        'phone': '+265999',
        'surface': 'x' * 200,
        'entitlement': null,
      });

      await Analytics.flush();

      final events = sent.single['events'] as List;
      expect(events, hasLength(1));
      final props = (events.single as Map)['properties'] as Map;
      expect(
        props.keys,
        unorderedEquals(['period', 'days', 'trial_active', 'surface']),
      );
      expect((props['surface'] as String).length, 64);
    },
  );

  test('the queue never grows without bound', () async {
    signedIn = false;
    for (var i = 0; i < Analytics.maxQueued + 20; i++) {
      await Analytics.track('paywall_dismissed');
    }
    expect(await Analytics.pendingCount(), Analytics.maxQueued);
  });
}
