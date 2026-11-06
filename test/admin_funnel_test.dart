import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/features/admin/data/funnel_models.dart';
import 'package:mulinda_mobile/features/admin/widgets/funnel_section.dart';

final _json = {
  'new_users_only': true,
  'steps': [
    {'name': 'registration_completed', 'users': 120, 'events': 120, 'conversion': null},
    {'name': 'trial_started', 'users': 110, 'events': 110, 'conversion': 0.9167},
    {'name': 'first_transaction_captured', 'users': 60, 'events': 300, 'conversion': 0.5455},
    {'name': 'subscription_completed', 'users': 9, 'events': 9, 'conversion': 0.15},
  ],
  'secondary': [
    {'name': 'payment_failed', 'users': 3, 'events': 4},
  ],
  'conversion': {'trial_users': 110, 'paid_users': 9, 'rate': 0.0818},
};

Future<void> _pump(WidgetTester tester, Future<FunnelReport> Function() load) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [funnelProvider.overrideWith((ref, q) => load())],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: FunnelSection())),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  test('the funnel response is read as ordered steps with conversions', () {
    final r = FunnelReport.fromJson(_json);
    expect(r.steps.map((s) => s.name).first, 'registration_completed');
    expect(r.steps.first.conversion, isNull);
    expect(r.steps[1].conversion, closeTo(0.9167, 1e-9));
    expect(r.top, 120);
    expect(r.trialUsers, 110);
    expect(r.paidUsers, 9);
    expect(r.secondary.single.name, 'payment_failed');
    expect(FunnelReport.fromJson(const {}).isEmpty, isTrue);
  });

  testWidgets('shows each step with its users and conversion', (tester) async {
    await _pump(tester, () async => FunnelReport.fromJson(_json));
    expect(find.byType(FunnelStepRow), findsNWidgets(4));
    expect(find.text('120'), findsOneWidget);
    expect(find.text('92%'), findsOneWidget);
    expect(find.text('admin2.funnel.trialToPaid'), findsOneWidget);
  });

  testWidgets('an empty range says so', (tester) async {
    await _pump(tester, () async => FunnelReport.fromJson(const {'steps': []}));
    expect(find.text('admin2.funnel.emptyTitle'), findsOneWidget);
  });

  testWidgets('an error offers a retry', (tester) async {
    await _pump(tester, () async => throw Exception('down'));
    expect(find.text('admin2.funnel.loadError'), findsOneWidget);
    expect(find.text('common.retry'), findsOneWidget);
  });
}
