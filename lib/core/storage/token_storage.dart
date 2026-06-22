import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the Sanctum bearer token in platform secure storage.
class TokenStorage {
  TokenStorage(this._storage);

  final FlutterSecureStorage _storage;
  static const _tokenKey = 'mulinda_auth_token';

  Future<String?> read() => _storage.read(key: _tokenKey);

  Future<void> save(String token) => _storage.write(key: _tokenKey, value: token);

  Future<void> clear() => _storage.delete(key: _tokenKey);
}

final tokenStorageProvider = Provider<TokenStorage>(
  (ref) => TokenStorage(const FlutterSecureStorage()),
);
