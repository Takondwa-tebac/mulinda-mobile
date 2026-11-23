import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/core/theme/app_theme.dart';
import 'package:mulinda_mobile/features/admin/data/admin_repository.dart';
import 'package:mulinda_mobile/features/admin/data/admin_user.dart';
import 'package:mulinda_mobile/features/admin/data/audit_models.dart';
import 'package:mulinda_mobile/features/admin/screens/audit_trail_screen.dart';
import 'package:mulinda_mobile/features/admin/screens/user_detail_screen.dart';
import 'package:mulinda_mobile/features/admin/widgets/user_detail_format.dart';
import 'package:mulinda_mobile/features/auth/data/user.dart';
import 'package:mulinda_mobile/features/auth/providers/auth_controller.dart';

/// Serves one user and records what the screen asks for.
class _FakeAdmin extends AdminRepository {
  _FakeAdmin(this.user) : super(Dio());

  Map<String, dynamic> user;
  final auditQueries = <AuditQuery>[];
  final grants = <String>[];
  final roleUpdates = <List<String>>[];
  int deletes = 0;

  @override
  Future<Map<String, dynamic>> getUserDetail(String userId) async => user;

  @override
  Future<AuditPage> audits(AuditQuery query, {int page = 1, int perPage = 25}) async {
    auditQueries.add(query);
    return AuditPage.fromJson({
      'data': [
        {
          'id': 9,
          'event': 'updated',
          'icon': 'updated',
          'actor': {'id': user['id'], 'name': user['full_name']},
          'subject': {'type': 'Budget', 'id': 'b1', 'label': 'Food'},
          'platform': 'android',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        },
      ],
      'meta': {'current_page': 1, 'last_page': 1},
    });
  }

  @override
  Future<void> grantCredit({required String userId, required String period, String? reason}) async =>
      grants.add(period);

  @override
  Future<void> updateUserRoles(String userId, List<String> roles) async {
    roleUpdates.add(roles);
    user = {...user, 'roles': roles};
  }

  @override
  Future<void> deleteUser(String userId) async => deletes++;
}

Map<String, dynamic> _user({
  List<String> roles = const ['user'],
  bool screenshots = false,
  Map<String, dynamic>? subscription,
}) => {
  'id': 'u42',
  'first_name': 'Chisomo',
  'full_name': 'Chisomo Banda',
  'username': 'chisomo.b',
  'email': 'chisomo@example.com',
  'phone_number': '+265 99 123 4567',
  'declared_income_bracket': 'middle',
  'sms_capture_count': 27,
  'roles': roles,
  'screenshots_allowed': screenshots,
  'subscription': subscription ?? {'active': false},
  'created_at': '2026-07-14T08:00:00Z',
  'last_active_at': DateTime.now().subtract(const Duration(hours: 2)).toUtc().toIso8601String(),
};

User _me(List<String> roles, {String id = 'me'}) => User(
  id: id,
  firstName: 'Admin',
  lastName: 'User',
  username: 'admin',
  email: 'admin@example.com',
  fullName: 'Admin User',
  roles: roles,
);

Future<_FakeAdmin> _pump(
  WidgetTester tester, {
  required Map<String, dynamic> user,
  List<String> myRoles = const ['super-admin'],
  String myId = 'me',
  ThemeData? theme,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fake = _FakeAdmin(user);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        adminRepositoryProvider.overrideWithValue(fake),
        currentUserProvider.overrideWithValue(_me(myRoles, id: myId)),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light,
        home: const UserDetailScreen(userId: 'u42'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

Future<void> _openTab(WidgetTester tester, String tab) async {
  final finder = find.byKey(ValueKey('user-tab-$tab'));
  await tester.scrollUntilVisible(finder, 200);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('each tab shows its own content', (tester) async {
    await _pump(tester, user: _user());

    // Overview: account details with copy buttons.
    expect(find.text('Chisomo Banda'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('copy-phone')), 200);
    expect(find.byKey(const ValueKey('copy-email')), findsOneWidget);
    expect(find.byKey(const ValueKey('plan-gift')), findsNothing);

    await _openTab(tester, 'plan');
    await tester.scrollUntilVisible(find.byKey(const ValueKey('plan-gift')), 200);
    expect(find.byKey(const ValueKey('copy-phone')), findsNothing);

    await _openTab(tester, 'access');
    await tester.scrollUntilVisible(find.byKey(const ValueKey('edit-roles')), 200);
    expect(find.byKey(const ValueKey('delete-user')), findsOneWidget);
  });

  testWidgets('activity lists what the person did via the actor filter', (tester) async {
    final fake = await _pump(tester, user: _user());

    await tester.tap(find.byKey(const ValueKey('qa-activity')));
    await tester.pumpAndSettle();

    expect(fake.auditQueries.single.actor, 'u42');
    await tester.scrollUntilVisible(find.byType(AuditTile), 200);
    expect(find.byType(AuditTile), findsOneWidget);
    expect(find.byKey(const ValueKey('open-audit-trail')), findsOneWidget);
  });

  testWidgets('an ordinary admin sees no screenshot chip, summary or switch', (tester) async {
    await _pump(tester, user: _user(screenshots: true), myRoles: ['admin']);

    expect(find.text('admin.user.screenshotsChip'), findsNothing);
    expect(find.text('admin.user.shotsAllowedLine', skipOffstage: false), findsNothing);
    await _openTab(tester, 'access');
    expect(find.byType(SwitchListTile, skipOffstage: false), findsNothing);
  });

  testWidgets('a super-admin sees the screenshot chip and summary', (tester) async {
    await _pump(tester, user: _user(screenshots: true));

    expect(find.text('admin.user.screenshotsChip'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('admin.user.shotsAllowedLine'), 200);
  });

  testWidgets('delete is disabled with a reason for a super-admin', (tester) async {
    await _pump(tester, user: _user(roles: ['user', 'super-admin']));
    await _openTab(tester, 'access');
    await tester.scrollUntilVisible(find.byKey(const ValueKey('delete-user')), 200);

    final button = tester.widget<ButtonStyleButton>(find.byKey(const ValueKey('delete-user')));
    expect(button.onPressed, isNull);
    expect(find.text('admin.user.deleteSuper'), findsOneWidget);
  });

  testWidgets('delete is disabled on your own account', (tester) async {
    await _pump(tester, user: _user(), myId: 'u42');
    await _openTab(tester, 'access');
    await tester.scrollUntilVisible(find.text('admin.user.deleteSelf'), 200);
  });

  testWidgets('deleting asks first and then tells the API', (tester) async {
    final fake = await _pump(tester, user: _user());
    await _openTab(tester, 'access');
    await tester.scrollUntilVisible(find.byKey(const ValueKey('delete-user')), 200);

    await tester.tap(find.byKey(const ValueKey('delete-user')));
    await tester.pumpAndSettle();
    expect(find.text('admin.deleteTitle'), findsOneWidget);
    expect(fake.deletes, 0);

    await tester.tap(find.widgetWithText(FilledButton, 'admin.deleteAction'));
    await tester.pumpAndSettle();
    expect(fake.deletes, 1);
  });

  testWidgets('gift from the quick action sends the chosen period', (tester) async {
    final fake = await _pump(tester, user: _user());

    await tester.tap(find.byKey(const ValueKey('qa-gift')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('admin.period.week'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'admin.giftAction'));
    await tester.pumpAndSettle();

    expect(fake.grants, ['week']);
  });

  testWidgets('roles sheet warns before adding super-admin and saves', (tester) async {
    final fake = await _pump(tester, user: _user());

    await tester.tap(find.byKey(const ValueKey('qa-roles')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('super-admin-warning')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('role-admin')));
    await tester.tap(find.byKey(const ValueKey('role-super-admin')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('super-admin-warning')), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'admin.rolesSave'));
    await tester.pumpAndSettle();
    expect(fake.roleUpdates.single, containsAll(['user', 'admin', 'super-admin']));
  });

  testWidgets('a trial and its end show in the header and tiles', (tester) async {
    final ends = DateTime.now().add(const Duration(days: 3));
    await _pump(
      tester,
      user: _user(
        subscription: {
          'active': true,
          'plan_label': '3-Day Pass',
          'source': 'trial',
          'is_trial': true,
          'ends_at': ends.toUtc().toIso8601String(),
        },
      ),
    );

    expect(
      find.descendant(of: find.byKey(const ValueKey('user-plan-chip')), matching: find.text('admin.user.trialPlan')),
      findsOneWidget,
    );
    expect(find.text('admin.user.trialEnds'), findsOneWidget);
    expect(find.text('admin.user.daysLeft.other'), findsOneWidget);
  });

  testWidgets('works in the dark theme without overflow', (tester) async {
    await _pump(
      tester,
      user: _user(roles: ['user', 'admin'], screenshots: true),
      theme: AppTheme.dark,
    );
    await _openTab(tester, 'access');
    expect(tester.takeException(), isNull);
  });

  test('parses the API user and names', () {
    final u = AdminUser.fromJson(_user(roles: ['user', 'admin']));
    expect(u.initials, 'CB');
    expect(u.shortName, 'Chisomo');
    expect(u.isAdmin, isTrue);
    expect(u.isSubscribed, isFalse);
    expect(u.smsCaptureCount, 27);
    expect(adminLeft(DateTime(2026, 11, 23), now: DateTime(2026, 11, 23, 9)), 'admin.user.endsToday');
  });
}
