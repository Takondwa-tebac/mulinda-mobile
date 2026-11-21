import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/storage/token_storage.dart';
import 'user.dart';

/// Talks to the API's auth endpoints and persists the bearer token on success.
class AuthRepository {
  AuthRepository(this._dio, this._tokens);

  final Dio _dio;
  final TokenStorage _tokens;

  static const _userCacheKey = 'mulinda_cached_user';
  static const _secure = FlutterSecureStorage();

  /// Parses the API user and remembers it (secure storage) so the app can start
  /// with the right name, plan and entitlements even with no connection.
  User _parse(dynamic data) {
    final json = (data as Map).cast<String, dynamic>();
    _secure.write(key: _userCacheKey, value: jsonEncode(json)).catchError((_) {});
    return User.fromJson(json);
  }

  /// The last user the API returned, or null (never signed in / signed out).
  Future<User?> cachedUser() async {
    try {
      final raw = await _secure.read(key: _userCacheKey);
      if (raw == null) return null;
      return User.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  Future<void> clearCachedUser() async {
    try {
      await _secure.delete(key: _userCacheKey);
    } catch (_) {}
  }

  Future<User> login(String username, String password) {
    return _authRequest('/v1/auth/login', {
      'username': username,
      'password': password,
    });
  }

  Future<User> register({
    required String phoneNumber,
    required String email,
    required String password,
    String? username,
    bool acceptedTerms = false,
    String? referralCode,
  }) {
    return _authRequest(
      '/v1/auth/register',
      registerBody(
        phoneNumber: phoneNumber,
        email: email,
        password: password,
        username: username,
        acceptedTerms: acceptedTerms,
        referralCode: referralCode,
      ),
    );
  }

  /// The sign-up request: only what the API requires (phone, email,
  /// password), plus the username when one was chosen and the Terms
  /// acceptance. Names and income are asked later, in context. A friend's
  /// invite code, when one is waiting, rides along as `referral_code`.
  static Map<String, dynamic> registerBody({
    required String phoneNumber,
    required String email,
    required String password,
    String? username,
    bool acceptedTerms = false,
    String? referralCode,
  }) {
    final name = username?.trim() ?? '';
    return {
      'phone_number': phoneNumber.trim(),
      'email': email.trim(),
      'password': password,
      if (name.isNotEmpty) 'username': name,
      if (acceptedTerms) 'accepted_terms': true,
      if (referralCode != null && referralCode.isNotEmpty) 'referral_code': referralCode,
    };
  }

  Future<User> googleToken(String accessToken, {String? referralCode}) {
    return _authRequest('/v1/auth/google/token', {
      'access_token': accessToken,
      if (referralCode != null && referralCode.isNotEmpty) 'referral_code': referralCode,
    });
  }

  /// Exchange a Sign in with Apple identity token (bound to [nonce]) for a
  /// Mulinda session. Apple only shares the name on the first sign-in.
  Future<User> appleToken({
    required String identityToken,
    required String nonce,
    String? authorizationCode,
    String? firstName,
    String? lastName,
    String? referralCode,
  }) {
    return _authRequest('/v1/auth/apple/token', {
      if (referralCode != null && referralCode.isNotEmpty) 'referral_code': referralCode,
      'identity_token': identityToken,
      'nonce': nonce,
      // Lets the server keep Apple's token so it can revoke it on account deletion.
      if (authorizationCode != null && authorizationCode.isNotEmpty)
        'authorization_code': authorizationCode,
      if (firstName != null && firstName.isNotEmpty) 'first_name': firstName,
      if (lastName != null && lastName.isNotEmpty) 'last_name': lastName,
    });
  }

  /// Record acceptance of the latest Terms version.
  Future<User> acceptTerms() async {
    try {
      final res = await _dio.post('/v1/auth/accept-terms');
      return _parse(res.data['data']);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<User> updateIncomeBracket(String bracket) => updateProfile({'income_bracket': bracket});

  Future<User> updateProfile(Map<String, dynamic> fields) async {
    try {
      final res = await _dio.patch('/v1/auth/profile', data: fields);
      return _parse(res.data['data']);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Upload a new profile picture (multipart) and return the refreshed user.
  Future<User> uploadAvatar(String filePath) async {
    try {
      final form = FormData.fromMap({
        'avatar': await MultipartFile.fromFile(filePath),
      });
      final res = await _dio.post('/v1/auth/avatar', data: form);
      return _parse(res.data['data']);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<User> me() async {
    try {
      final res = await _dio.get('/v1/auth/me');
      return _parse(res.data['data']);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Permanently delete the signed-in user's account. [confirmation] must equal
  /// the username (verified server-side).
  Future<void> deleteAccount(String confirmation) async {
    try {
      await _dio.delete('/v1/auth/account', data: {'confirmation': confirmation});
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> logout() async {
    try {
      await _dio.post('/v1/auth/logout');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Requests a password-reset email. (Backend route: POST /v1/auth/forgot-password.)
  Future<void> forgotPassword(String email) async {
    try {
      await _dio.post('/v1/auth/forgot-password', data: {'email': email});
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Completes a reset using the token from the emailed deep link.
  Future<void> resetPassword({
    required String token,
    required String email,
    required String password,
  }) async {
    try {
      await _dio.post('/v1/auth/reset-password', data: {
        'token': token,
        'email': email,
        'password': password,
        'password_confirmation': password,
      });
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Posts credentials, saves the returned token, and returns the user.
  Future<User> _authRequest(String path, Map<String, dynamic> body) async {
    try {
      final res = await _dio.post(path, data: body);
      final token = res.data['token'] as String;
      await _tokens.save(token);
      return _parse(res.data['data']);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.read(dioProvider), ref.read(tokenStorageProvider)),
);
