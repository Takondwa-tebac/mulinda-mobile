import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/storage/token_storage.dart';
import '../data/auth_repository.dart';
import '../data/user.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

/// Auth status plus the current user (when known). The router guards on
/// [status]; screens read [user].
class AuthState {
  const AuthState({required this.status, this.user});

  final AuthStatus status;
  final User? user;
}

class AuthController extends Notifier<AuthState> {
  AuthRepository get _repo => ref.read(authRepositoryProvider);
  TokenStorage get _tokens => ref.read(tokenStorageProvider);

  @override
  AuthState build() => const AuthState(status: AuthStatus.unknown);

  /// Resolve the initial status from any persisted token (called by splash).
  /// Holds a minimum duration so the splash is visible, and never hangs: the
  /// reads are time-boxed and failures fall back to signed-out.
  Future<void> bootstrap() async {
    const minSplash = Duration(milliseconds: 1600);
    final stopwatch = Stopwatch()..start();

    String? token;
    User? user;
    try {
      token = await _tokens.read().timeout(const Duration(seconds: 4));
      if (token != null) {
        try {
          user = await _repo.me().timeout(const Duration(seconds: 6));
        } catch (_) {
          // A 401 makes the Dio interceptor clear the token; re-read to confirm.
          // Other (network) errors keep the token so offline users stay in.
          token = await _tokens.read();
        }
      }
    } catch (_) {
      token = null;
    }

    final remaining = minSplash - stopwatch.elapsed;
    if (remaining > Duration.zero) {
      await Future.delayed(remaining);
    }

    state = token != null
        ? AuthState(status: AuthStatus.authenticated, user: user)
        : const AuthState(status: AuthStatus.unauthenticated);
  }

  Future<void> login(String username, String password) async {
    final user = await _repo.login(username, password);
    state = AuthState(status: AuthStatus.authenticated, user: user);
  }

  Future<void> register({
    required String firstName,
    String? middleName,
    required String lastName,
    required String username,
    required String phoneNumber,
    required String email,
    required String password,
    required String passwordConfirmation,
    String? incomeBracket,
  }) async {
    final user = await _repo.register(
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
      username: username,
      phoneNumber: phoneNumber,
      email: email,
      password: password,
      passwordConfirmation: passwordConfirmation,
      incomeBracket: incomeBracket,
    );
    state = AuthState(status: AuthStatus.authenticated, user: user);
  }

  /// Native Google sign-in → exchange the access token for a Mulinda token.
  /// Returns false if the user cancelled.
  Future<bool> signInWithGoogle() async {
    final account = await GoogleSignIn(scopes: const ['email', 'profile']).signIn();
    if (account == null) return false; // cancelled

    final auth = await account.authentication;
    final accessToken = auth.accessToken;
    if (accessToken == null) {
      throw ApiException('Could not obtain a Google access token.');
    }

    final user = await _repo.googleToken(accessToken);
    state = AuthState(status: AuthStatus.authenticated, user: user);
    return true;
  }

  /// Declare the user's income bracket (first-run setup) and refresh the user.
  Future<void> setIncomeBracket(String bracket) async {
    final user = await _repo.updateIncomeBracket(bracket);
    state = AuthState(status: AuthStatus.authenticated, user: user);
  }

  /// Update editable profile fields and refresh the user.
  Future<void> updateProfile({
    String? firstName,
    String? middleName,
    String? lastName,
    String? phoneNumber,
  }) async {
    final fields = <String, dynamic>{};
    if (firstName != null) fields['first_name'] = firstName;
    if (middleName != null) fields['middle_name'] = middleName;
    if (lastName != null) fields['last_name'] = lastName;
    if (phoneNumber != null) fields['phone_number'] = phoneNumber;

    final user = await _repo.updateProfile(fields);
    state = AuthState(status: AuthStatus.authenticated, user: user);
  }

  Future<void> signOut() async {
    try {
      await _repo.logout();
    } catch (_) {
      // Even if the API call fails, clear locally.
    }
    await _tokens.clear();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

/// Convenience accessor for the current user.
final currentUserProvider = Provider<User?>((ref) => ref.watch(authControllerProvider).user);
