import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/core/security/screenshot_protection.dart';
import 'package:mulinda_mobile/features/admin/data/admin_repository.dart';
import 'package:mulinda_mobile/features/auth/data/user.dart';
import 'package:mulinda_mobile/features/auth/providers/auth_controller.dart';

User _user({bool screenshotsAllowed = false, List<String> roles = const []}) => User(
      id: 'u1',
      firstName: 'Test',
      lastName: 'User',
      username: 'test',
      email: 't@example.com',
      fullName: 'Test User',
      roles: roles,
      screenshotsAllowed: screenshotsAllowed,
    );

/// Records screenshot changes; fails when told to.
class _FakeAdmin extends AdminRepository {
  _FakeAdmin({this.fail = false}) : super(Dio());

  final bool fail;
  final calls = <(String, bool)>[];

  @override
  Future<void> setScreenshotsAllowed(String userId, {required bool allowed}) async {
    calls.add((userId, allowed));
    if (fail) throw StateError('server refused');
  }
}

ProviderContainer _container(User? user, _FakeAdmin admin) {
  final container = ProviderContainer(overrides: [
    currentUserProvider.overrideWithValue(user),
    adminRepositoryProvider.overrideWithValue(admin),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('the profile carries the screenshots setting, blocked when absent', () {
    final base = {'id': 1, 'first_name': 'A', 'last_name': 'B', 'username': 'ab', 'email': 'a@b.c', 'full_name': 'A B'};

    expect(User.fromJson(base).screenshotsAllowed, isFalse);
    expect(User.fromJson({...base, 'screenshots_allowed': true}).screenshotsAllowed, isTrue);
    expect(User.fromJson({...base, 'screenshots_allowed': false}).screenshotsAllowed, isFalse);
  });

  test('screenshots are blocked by default and while signed out', () {
    expect(_container(null, _FakeAdmin()).read(screenshotProtectionProvider), isTrue);
    expect(_container(_user(), _FakeAdmin()).read(screenshotProtectionProvider), isTrue);
  });

  test('an account an admin allowed is not protected, on any phone it signs in on', () {
    final container = _container(_user(screenshotsAllowed: true), _FakeAdmin());

    expect(container.read(screenshotProtectionProvider), isFalse);
    expect(container.read(effectiveScreenshotProtectionProvider), isFalse);
  });

  test('only a super-admin can use the Profile switch', () async {
    final admin = _FakeAdmin();
    final container = _container(_user(roles: ['admin']), admin);

    await container.read(screenshotProtectionProvider.notifier).setProtected(false);

    expect(admin.calls, isEmpty);
    expect(container.read(screenshotProtectionProvider), isTrue);
  });

  test('if the server refuses, the Profile switch goes back and the error is reported', () async {
    final admin = _FakeAdmin(fail: true);
    final container = _container(_user(roles: ['super-admin']), admin);

    await expectLater(
      container.read(screenshotProtectionProvider.notifier).setProtected(false),
      throwsA(isA<StateError>()),
    );

    expect(admin.calls, [('u1', true)]);
    expect(container.read(screenshotProtectionProvider), isTrue);
  });
}
