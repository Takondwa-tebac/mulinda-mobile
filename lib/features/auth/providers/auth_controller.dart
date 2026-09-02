import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/storage/token_storage.dart';
import '../../onboarding/onboarding_prefs.dart';
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
    const minSplash = Duration(milliseconds: 1200);
    final stopwatch = Stopwatch()..start();

    String? token;
    try {
      token = await _tokens.read().timeout(const Duration(seconds: 3));
    } catch (_) {
      token = null; // storage slow/unavailable → treat as signed out
    }

    final remaining = minSplash - stopwatch.elapsed;
    if (remaining > Duration.zero) {
      await Future.delayed(remaining);
    }

    // Decide auth purely from token presence — the splash never waits on the
    // network. The profile is fetched in the background afterwards.
    if (token == null) {
      state = const AuthState(status: AuthStatus.unauthenticated);
      return;
    }
    state = const AuthState(status: AuthStatus.authenticated);
    unawaited(_loadUser());
  }

  /// Fetch the signed-in user's profile without blocking the splash. A 401
  /// signs out; other (offline) errors leave them in with the profile pending.
  Future<void> _loadUser() async {
    try {
      final user = await _repo.me().timeout(const Duration(seconds: 10));
      state = AuthState(status: AuthStatus.authenticated, user: user);
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await _tokens.clear();
        state = const AuthState(status: AuthStatus.unauthenticated);
      }
    } catch (_) {
      // Network/timeout — stay signed in; the profile loads on next try.
    }
  }

  /// Re-fetch the signed-in user's profile (e.g. after a subscription purchase
  /// so refreshed entitlements take effect). Silent on failure.
  Future<void> refresh() async {
    try {
      final user = await _repo.me();
      state = AuthState(status: AuthStatus.authenticated, user: user);
    } catch (_) {
      // Keep current state; entitlements refresh on the next successful load.
    }
  }

  /// Once a user has authenticated they should never see onboarding again,
  /// regardless of how they signed in or that they later log out.
  void _markOnboardingSeen() {
    OnboardingPrefs.markSeen();
    ref.read(onboardingSeenProvider.notifier).state = true;
  }

  Future<void> login(String username, String password) async {
    final user = await _repo.login(username, password);
    _markOnboardingSeen();
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
    bool acceptedTerms = false,
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
      acceptedTerms: acceptedTerms,
    );
    _markOnboardingSeen();
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
    _markOnboardingSeen();
    state = AuthState(status: AuthStatus.authenticated, user: user);
    return true;
  }

  /// Declare the user's income bracket (first-run setup) and refresh the user.
  Future<void> setIncomeBracket(String bracket) async {
    final user = await _repo.updateIncomeBracket(bracket);
    state = AuthState(status: AuthStatus.authenticated, user: user);
  }

  /// Upload a new avatar and refresh the user.
  Future<void> uploadAvatar(String filePath) async {
    final user = await _repo.uploadAvatar(filePath);
    state = AuthState(status: AuthStatus.authenticated, user: user);
  }

  /// Update editable profile fields and refresh the user.
  Future<void> updateProfile({
    String? firstName,
    String? middleName,
    String? lastName,
    String? phoneNumber,
    String? displayCurrency,
    bool? dailySummaryEnabled,
    String? dailySummaryTime,
  }) async {
    final fields = <String, dynamic>{};
    if (firstName != null) fields['first_name'] = firstName;
    if (middleName != null) fields['middle_name'] = middleName;
    if (lastName != null) fields['last_name'] = lastName;
    if (phoneNumber != null) fields['phone_number'] = phoneNumber;
    if (displayCurrency != null) fields['display_currency'] = displayCurrency;
    if (dailySummaryEnabled != null) fields['daily_summary_enabled'] = dailySummaryEnabled;
    if (dailySummaryTime != null) fields['daily_summary_time'] = dailySummaryTime;

    final user = await _repo.updateProfile(fields);
    state = AuthState(status: AuthStatus.authenticated, user: user);
  }

  /// Permanently delete the account, then clear local session.
  Future<void> deleteAccount(String confirmation) async {
    await _repo.deleteAccount(confirmation);
    await _tokens.clear();
    state = const AuthState(status: AuthStatus.unauthenticated);
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
