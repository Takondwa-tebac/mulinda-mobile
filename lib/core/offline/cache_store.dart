import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// One saved API response.
class CachedResponse {
  const CachedResponse({required this.body, required this.fetchedAt});

  /// The decoded JSON payload (Map or List).
  final dynamic body;
  final DateTime fetchedAt;
}

/// Where saved responses live. Abstracted so the interceptor can be tested
/// without a database.
abstract class CacheStore {
  Future<void> put(String userId, String key, dynamic body);
  Future<CachedResponse?> get(String userId, String key);

  /// Remove everything saved for [userId] (offline mode turned off).
  Future<void> clearUser(String userId);

  /// Remove everything (sign-out, account deletion).
  Future<void> clearAll();
}

/// Encrypted SQLite (SQLite3 Multiple Ciphers via drift) cache of GET responses.
///
/// Rows are keyed by (user, request) and hold the JSON body and when it was
/// fetched. The database file is encrypted at rest with a random key kept in the
/// platform secure storage, and it is only ever written for users who turned
/// offline mode on.
class EncryptedCacheStore implements CacheStore {
  EncryptedCacheStore._();
  static final EncryptedCacheStore instance = EncryptedCacheStore._();

  static const _keyName = 'mulinda_offline_cache_key';
  static const _maxRowsPerUser = 600;
  static const _maxAge = Duration(days: 30);

  Future<_CacheDb>? _db;

  Future<_CacheDb> get _database => _db ??= _open();

  Future<_CacheDb> _open() async {
    const storage = FlutterSecureStorage();
    var key = await storage.read(key: _keyName);
    if (key == null || key.isEmpty) {
      final rng = Random.secure();
      key = List.generate(32, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await storage.write(key: _keyName, value: key);
    }

    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'offline_cache.db'));
    final hexKey = key;

    return _CacheDb(
      NativeDatabase.createInBackground(
        file,
        setup: (sqlite.Database raw) {
          // Fail loudly in debug builds if the encrypted SQLite was not bundled.
          assert(raw.select('PRAGMA cipher;').isNotEmpty,
              'SQLite3 Multiple Ciphers is not linked — check the hooks block in pubspec.yaml');
          raw.execute("PRAGMA key = '$hexKey';");
        },
      ),
    );
  }

  @override
  Future<void> put(String userId, String key, dynamic body) async {
    final db = await _database;
    await db.customInsert(
      'INSERT OR REPLACE INTO cached_responses (user_id, cache_key, body, fetched_at) VALUES (?, ?, ?, ?)',
      variables: [
        Variable.withString(userId),
        Variable.withString(key),
        Variable.withString(jsonEncode(body)),
        Variable.withInt(DateTime.now().millisecondsSinceEpoch),
      ],
    );
    await _prune(db, userId);
  }

  @override
  Future<CachedResponse?> get(String userId, String key) async {
    final db = await _database;
    final rows = await db
        .customSelect(
          'SELECT body, fetched_at FROM cached_responses WHERE user_id = ? AND cache_key = ?',
          variables: [Variable.withString(userId), Variable.withString(key)],
        )
        .get();
    if (rows.isEmpty) return null;
    final row = rows.first;
    return CachedResponse(
      body: jsonDecode(row.read<String>('body')),
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(row.read<int>('fetched_at')),
    );
  }

  @override
  Future<void> clearUser(String userId) async {
    final db = await _database;
    await db.customStatement('DELETE FROM cached_responses WHERE user_id = ?', [userId]);
  }

  @override
  Future<void> clearAll() async {
    final db = await _database;
    await db.customStatement('DELETE FROM cached_responses');
  }

  /// Keep the cache bounded: drop old entries, then the oldest beyond the cap.
  Future<void> _prune(_CacheDb db, String userId) async {
    final cutoff = DateTime.now().subtract(_maxAge).millisecondsSinceEpoch;
    await db.customStatement('DELETE FROM cached_responses WHERE fetched_at < ?', [cutoff]);
    await db.customStatement(
      'DELETE FROM cached_responses WHERE user_id = ? AND cache_key NOT IN '
      '(SELECT cache_key FROM cached_responses WHERE user_id = ? ORDER BY fetched_at DESC LIMIT ?)',
      [userId, userId, _maxRowsPerUser],
    );
  }
}

/// Hand-written drift database (no code generation): a single key/value table.
class _CacheDb extends GeneratedDatabase {
  _CacheDb(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await customStatement('''
            CREATE TABLE IF NOT EXISTS cached_responses (
              user_id TEXT NOT NULL,
              cache_key TEXT NOT NULL,
              body TEXT NOT NULL,
              fetched_at INTEGER NOT NULL,
              PRIMARY KEY (user_id, cache_key)
            ) WITHOUT ROWID
          ''');
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_cached_responses_fetched ON cached_responses (fetched_at)',
          );
        },
      );
}
