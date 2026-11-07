import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/core/network/api_exception.dart';
import 'package:mulinda_mobile/features/auth/data/user.dart';
import 'package:mulinda_mobile/features/auth/providers/auth_controller.dart';
import 'package:mulinda_mobile/features/plan/data/plan_models.dart';
import 'package:mulinda_mobile/features/plan/data/plan_repository.dart';
import 'package:mulinda_mobile/features/plan/screens/plan_detail_screens.dart';
import 'package:mulinda_mobile/features/plan/widgets/budget_spending.dart';
import 'package:mulinda_mobile/features/activity/data/activity_models.dart';
import 'package:mulinda_mobile/features/profile/screens/preferences_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Signed in as [user]; records what Preferences saves, or fails with [fail].
class _FakeAuth extends AuthController {
  _FakeAuth(this.user, {this.fail});

  final User user;
  final ApiException? fail;
  final saved = <Map<String, bool>>[];

  @override
  AuthState build() => AuthState(status: AuthStatus.authenticated, user: user);

  @override
  Future<void> updateProfile({
    String? firstName,
    String? middleName,
    String? lastName,
    String? phoneNumber,
    String? displayCurrency,
    bool? dailySummaryEnabled,
    String? dailySummaryTime,
    bool? notifyBudgetAlerts,
    bool? notifySpendingSpikes,
  }) async {
    if (fail != null) throw fail!;
    saved.add({'notify_budget_alerts': ?notifyBudgetAlerts, 'notify_spending_spikes': ?notifySpendingSpikes});
    final j = {
      'id': 'u1',
      'notify_budget_alerts': notifyBudgetAlerts ?? state.user!.notifyBudgetAlerts,
      'notify_spending_spikes': notifySpendingSpikes ?? state.user!.notifySpendingSpikes,
    };
    state = AuthState(status: AuthStatus.authenticated, user: User.fromJson(j));
  }
}

class _FileLoader extends AssetLoader {
  const _FileLoader();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('assets/translations/${locale.languageCode}.json').readAsStringSync()) as Map<String, dynamic>;
}

Future<void> _pump(WidgetTester tester, _FakeAuth auth, Widget screen, {List overrides = const []}) async {
  tester.view.physicalSize = const Size(360 * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.runAsync(() async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('ny')],
        startLocale: const Locale('en'),
        fallbackLocale: const Locale('en'),
        path: 'assets/translations',
        assetLoader: const _FileLoader(),
        child: ProviderScope(
          overrides: [authControllerProvider.overrideWith(() => auth), ...overrides.cast()],
          child: Builder(
            builder: (context) => MaterialApp(
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              home: screen,
            ),
          ),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

bool _on(WidgetTester tester, String key) => tester.widget<SwitchListTile>(find.byKey(ValueKey(key))).value;

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  test('the user reads both alert settings, on unless the server says false', () {
    final none = User.fromJson({'id': 'u'});
    expect(none.notifyBudgetAlerts, isTrue);
    expect(none.notifySpendingSpikes, isTrue);
    final off = User.fromJson({'id': 'u', 'notify_budget_alerts': false, 'notify_spending_spikes': false});
    expect(off.notifyBudgetAlerts, isFalse);
    expect(off.notifySpendingSpikes, isFalse);
  });

  testWidgets('Preferences shows both switches and saves each one', (tester) async {
    final auth = _FakeAuth(User.fromJson({'id': 'u1', 'notify_spending_spikes': false}));
    await _pump(tester, auth, const PreferencesScreen());

    expect(find.text('Budget alerts'), findsOneWidget);
    expect(find.text('Spending spikes'), findsOneWidget);
    expect(_on(tester, 'pref-budget-alerts'), isTrue);
    expect(_on(tester, 'pref-spending-spikes'), isFalse);

    await tester.tap(find.byKey(const ValueKey('pref-budget-alerts')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(auth.saved.last, {'notify_budget_alerts': false});
    expect(_on(tester, 'pref-budget-alerts'), isFalse);
    expect(find.text('profile.saved'.tr()), findsOneWidget);

    // Turning one on asks for notification permission first (a platform call).
    await tester.tap(find.byKey(const ValueKey('pref-spending-spikes')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(auth.saved.last, {'notify_spending_spikes': true});
    expect(_on(tester, 'pref-spending-spikes'), isTrue);
  });

  testWidgets('a failed save shows the message and leaves the switch as it was', (tester) async {
    final auth = _FakeAuth(User.fromJson({'id': 'u1'}), fail: ApiException('Could not save', statusCode: 500));
    await _pump(tester, auth, const PreferencesScreen());
    await tester.tap(find.byKey(const ValueKey('pref-budget-alerts')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_on(tester, 'pref-budget-alerts'), isTrue);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('budget detail shows the remaining amount with thousands separators', (tester) async {
    Map<String, dynamic> m(int major) => {
      'minor_units': major * 100,
      'currency': 'MWK',
      'amount': major,
      'formatted': 'MK $major',
    };
    final b = BudgetItem.fromJson({
      'id': 'b1',
      'name': 'Transport',
      'period': 'monthly',
      'limit': m(35000),
      'status': {'spent': m(29750), 'percentage': 85},
    });
    await _pump(
      tester,
      _FakeAuth(User.fromJson({'id': 'u1'})),
      BudgetDetailScreen(budget: b),
      overrides: [
        budgetsProvider.overrideWith((ref) async => [b]),
        budgetSpendProvider.overrideWith((ref, key) async => const <Txn>[]),
      ],
    );
    expect(find.text('MK 5,250.00'), findsOneWidget);
    expect(find.text('MK 5250.00'), findsNothing);
  });
}
