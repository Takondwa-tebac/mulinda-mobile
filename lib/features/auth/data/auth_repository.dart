import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/storage/token_storage.dart';
import 'user.dart';

/// Talks to the API's auth endpoints and persists the bearer token on success.
class AuthRepository {
  AuthRepository(this._dio, this._tokens);

  final Dio _dio;
  final TokenStorage _tokens;

  Future<User> login(String username, String password) {
    return _authRequest('/v1/auth/login', {
      'username': username,
      'password': password,
    });
  }

  Future<User> register({
    required String firstName,
    String? middleName,
    required String lastName,
    required String username,
    required String phoneNumber,
    required String email,
    required String password,
    required String passwordConfirmation,
    String? incomeBracket,
  }) {
    final body = <String, dynamic>{
      'first_name': firstName,
      'last_name': lastName,
      'username': username,
      'phone_number': phoneNumber,
      'email': email,
      'password': password,
      'password_confirmation': passwordConfirmation,
    };
    if (middleName != null && middleName.isNotEmpty) body['middle_name'] = middleName;
    if (incomeBracket != null) body['income_bracket'] = incomeBracket;

    return _authRequest('/v1/auth/register', body);
  }

  Future<User> googleToken(String accessToken) {
    return _authRequest('/v1/auth/google/token', {'access_token': accessToken});
  }

  Future<User> updateIncomeBracket(String bracket) async {
    try {
      final res = await _dio.patch('/v1/auth/profile', data: {'income_bracket': bracket});
      return User.fromJson((res.data['data'] as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<User> me() async {
    try {
      final res = await _dio.get('/v1/auth/me');
      return User.fromJson((res.data['data'] as Map).cast<String, dynamic>());
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

  /// Posts credentials, saves the returned token, and returns the user.
  Future<User> _authRequest(String path, Map<String, dynamic> body) async {
    try {
      final res = await _dio.post(path, data: body);
      final token = res.data['token'] as String;
      await _tokens.save(token);
      return User.fromJson((res.data['data'] as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.read(dioProvider), ref.read(tokenStorageProvider)),
);
