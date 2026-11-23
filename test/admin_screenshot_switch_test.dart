import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/features/admin/data/admin_repository.dart';
import 'package:mulinda_mobile/features/admin/screens/user_detail_screen.dart';
import 'package:mulinda_mobile/features/auth/data/user.dart';
import 'package:mulinda_mobile/features/auth/providers/auth_controller.dart';

/// Serves one user's details and records screenshot changes.
class _FakeAdmin extends AdminRepository {
  _FakeAdmin() : super(Dio());

  bool allowed = false;
  final calls = <(String, bool)>[];

  @override
  Future<Map<String, dynamic>> getUserDetail(String userId) async => {
        'id': userId,
        'full_name': 'Chiso Banda',
        'username': 'chiso',
        'email': 'chiso@example.com',
        'roles': ['user'],
        'screenshots_allowed': allowed,
        'subscription': {'active': true},
      };

  @override
  Future<void> setScreenshotsAllowed(String userId, {required bool allowed}) async {
    calls.add((userId, allowed));
    this.allowed = allowed;
  }
}

User _me(List<String> roles) => User(
      id: 'me',
      firstName: 'Admin',
      lastName: 'User',
      username: 'admin',
      email: 'admin@example.com',
      fullName: 'Admin User',
      roles: roles,
    );

Future<_FakeAdmin> _pump(WidgetTester tester, List<String> myRoles) async {
  final fake = _FakeAdmin();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      adminRepositoryProvider.overrideWithValue(fake),
      currentUserProvider.overrideWithValue(_me(myRoles)),
    ],
    child: const MaterialApp(home: UserDetailScreen(userId: 'u42')),
  ));
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  testWidgets('a super-admin sees the switch, confirms, and the API is told', (tester) async {
    final fake = await _pump(tester, ['super-admin']);

    await tester.scrollUntilVisible(find.byType(SwitchListTile), 200);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isFalse);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    // The confirmation sheet: nothing changes until it is confirmed.
    expect(fake.calls, isEmpty);
    await tester.tap(find.byType(FilledButton).last);
    await tester.pumpAndSettle();

    expect(fake.calls, [('u42', true)]);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);
  });

  testWidgets('cancelling the confirmation changes nothing', (tester) async {
    final fake = await _pump(tester, ['super-admin']);

    await tester.scrollUntilVisible(find.byType(SwitchListTile), 200);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextButton).last);
    await tester.pumpAndSettle();

    expect(fake.calls, isEmpty);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isFalse);
  });

  testWidgets('an ordinary admin does not see the switch', (tester) async {
    await _pump(tester, ['admin']);

    expect(find.byType(SwitchListTile, skipOffstage: false), findsNothing);
  });
}
