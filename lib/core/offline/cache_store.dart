import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'mutation_store.dart';

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

  /// Every saved response whose key starts with [keyPrefix] (e.g. all cached
  /// `GET /v1/accounts…` pages) — used to look up names for locally built records.
  Future<List<CachedResponse>> getByPrefix(String userId, String keyPrefix);

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
class EncryptedCacheStore implements CacheStore, MutationStore {
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
          // The app and the background sync job may both open this file.
          raw.execute('PRAGMA journal_mode = WAL;');
          raw.execute('PRAGMA busy_timeout = 5000;');
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
  Future<List<CachedResponse>> getByPrefix(String userId, String keyPrefix) async {
    final db = await _database;
    final rows = await db
        .customSelect(
          'SELECT body, fetched_at FROM cached_responses WHERE user_id = ? AND cache_key LIKE ?',
          variables: [Variable.withString(userId), Variable.withString('$keyPrefix%')],
        )
        .get();
    return rows
        .map((r) => CachedResponse(
              body: jsonDecode(r.read<String>('body')),
              fetchedAt: DateTime.fromMillisecondsSinceEpoch(r.read<int>('fetched_at')),
            ))
        .toList();
  }

  @override
  Future<void> clearUser(String userId) async {
    final db = await _database;
    await db.customStatement('DELETE FROM cached_responses WHERE user_id = ?', [userId]);
    await db.customStatement('DELETE FROM record_versions WHERE user_id = ?', [userId]);
    await db.customStatement('DELETE FROM pending_mutations WHERE user_id = ?', [userId]);
  }

  @override
  Future<void> clearAll() async {
    final db = await _database;
    await db.customStatement('DELETE FROM cached_responses');
    await db.customStatement('DELETE FROM record_versions');
    await db.customStatement('DELETE FROM pending_mutations');
  }

  // ---- MutationStore ---------------------------------------------------------

  PendingMutation _row(QueryRow r) => PendingMutation(
        seq: r.read<int>('seq'),
        id: r.read<String>('id'),
        userId: r.read<String>('user_id'),
        entity: r.read<String>('entity'),
        op: r.read<String>('op'),
        targetIds: (jsonDecode(r.read<String>('target_ids')) as List).map((e) => e.toString()).toList(),
        method: r.read<String>('method'),
        path: r.read<String>('path'),
        body: PendingMutation.decodeMap(r.read<String>('body')),
        baseUpdatedAt: r.readNullable<String>('base_updated_at'),
        effect: PendingMutation.decodeMap(r.readNullable<String>('effect')),
        createdMs: r.read<int>('created_ms'),
        attempts: r.read<int>('attempts'),
        nextRetryMs: r.read<int>('next_retry_ms'),
        lastError: r.readNullable<String>('last_error'),
      );

  @override
  Future<void> enqueue(PendingMutation m) async {
    final db = await _database;
    await db.customInsert(
      'INSERT OR IGNORE INTO pending_mutations '
      '(id, user_id, entity, op, target_ids, method, path, body, base_updated_at, effect, created_ms, attempts, next_retry_ms) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0)',
      variables: [
        Variable.withString(m.id),
        Variable.withString(m.userId),
        Variable.withString(m.entity),
        Variable.withString(m.op),
        Variable.withString(jsonEncode(m.targetIds)),
        Variable.withString(m.method),
        Variable.withString(m.path),
        Variable.withString(m.bodyJson),
        Variable<String>(m.baseUpdatedAt),
        Variable.withString(m.effectJson),
        Variable.withInt(m.createdMs),
      ],
    );
  }

  @override
  Future<List<PendingMutation>> all(String userId) async {
    final db = await _database;
    final rows = await db
        .customSelect('SELECT * FROM pending_mutations WHERE user_id = ? ORDER BY seq ASC',
            variables: [Variable.withString(userId)])
        .get();
    return rows.map(_row).toList();
  }

  @override
  Future<List<PendingMutation>> allPending() async {
    final db = await _database;
    final rows = await db.customSelect('SELECT * FROM pending_mutations ORDER BY seq ASC').get();
    return rows.map(_row).toList();
  }

  @override
  Future<int> count({String? userId}) async {
    final db = await _database;
    final rows = await db
        .customSelect(
          userId == null
              ? 'SELECT COUNT(*) AS c FROM pending_mutations'
              : 'SELECT COUNT(*) AS c FROM pending_mutations WHERE user_id = ?',
          variables: userId == null ? const [] : [Variable.withString(userId)],
        )
        .get();
    return rows.first.read<int>('c');
  }

  @override
  Future<void> remove(String id) async {
    final db = await _database;
    await db.customStatement('DELETE FROM pending_mutations WHERE id = ?', [id]);
  }

  @override
  Future<void> reschedule(String id, {required int attempts, required int nextRetryMs, String? error}) async {
    final db = await _database;
    await db.customStatement(
      'UPDATE pending_mutations SET attempts = ?, next_retry_ms = ?, last_error = ? WHERE id = ?',
      [attempts, nextRetryMs, error, id],
    );
  }

  @override
  Future<void> clearMutations({String? userId}) async {
    final db = await _database;
    if (userId == null) {
      await db.customStatement('DELETE FROM pending_mutations');
    } else {
      await db.customStatement('DELETE FROM pending_mutations WHERE user_id = ?', [userId]);
    }
  }

  @override
  Future<void> putVersions(String userId, String entity, Map<String, String> updatedAtById) async {
    if (updatedAtById.isEmpty) return;
    final db = await _database;
    await db.transaction(() async {
      for (final e in updatedAtById.entries) {
        await db.customStatement(
          'INSERT OR REPLACE INTO record_versions (user_id, entity, record_id, updated_at) VALUES (?, ?, ?, ?)',
          [userId, entity, e.key, e.value],
        );
      }
    });
  }

  @override
  Future<String?> version(String userId, String entity, String id) async {
    final db = await _database;
    final rows = await db
        .customSelect(
          'SELECT updated_at FROM record_versions WHERE user_id = ? AND entity = ? AND record_id = ?',
          variables: [Variable.withString(userId), Variable.withString(entity), Variable.withString(id)],
        )
        .get();
    return rows.isEmpty ? null : rows.first.read<String>('updated_at');
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
  int get schemaVersion => 2;

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await _createCacheTables();
          await _createOfflineWriteTables();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) await _createOfflineWriteTables();
        },
      );

  Future<void> _createCacheTables() async {
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
  }

  /// v2: the queue of changes made offline, and the last-seen version of each
  /// record (so the server can tell whether an edit is based on stale data).
  Future<void> _createOfflineWriteTables() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS pending_mutations (
        seq INTEGER PRIMARY KEY AUTOINCREMENT,
        id TEXT NOT NULL UNIQUE,
        user_id TEXT NOT NULL,
        entity TEXT NOT NULL,
        op TEXT NOT NULL,
        target_ids TEXT NOT NULL,
        method TEXT NOT NULL,
        path TEXT NOT NULL,
        body TEXT NOT NULL,
        base_updated_at TEXT,
        effect TEXT NOT NULL,
        created_ms INTEGER NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        next_retry_ms INTEGER NOT NULL DEFAULT 0,
        last_error TEXT
      )
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_pending_mutations_user ON pending_mutations (user_id, seq)',
    );
    await customStatement('''
      CREATE TABLE IF NOT EXISTS record_versions (
        user_id TEXT NOT NULL,
        entity TEXT NOT NULL,
        record_id TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (user_id, entity, record_id)
      ) WITHOUT ROWID
    ''');
  }
}
