import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/token_storage.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

/// Tracks whether the user is signed in. Drives the router's auth guard.
///
/// Phase 0 uses a placeholder [devSignIn]; real login/register/Google flows
/// arrive in the auth phase.
class AuthController extends Notifier<AuthStatus> {
  @override
  AuthStatus build() => AuthStatus.unknown;

  TokenStorage get _tokens => ref.read(tokenStorageProvider);

  /// Resolve the initial status from any persisted token (called by splash).
  Future<void> bootstrap() async {
    final token = await _tokens.read();
    state = token != null ? AuthStatus.authenticated : AuthStatus.unauthenticated;
  }

  /// Placeholder sign-in for the Phase 0 skeleton.
  Future<void> devSignIn() async {
    await _tokens.save('dev-placeholder-token');
    state = AuthStatus.authenticated;
  }

  Future<void> signOut() async {
    await _tokens.clear();
    state = AuthStatus.unauthenticated;
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthStatus>(AuthController.new);
