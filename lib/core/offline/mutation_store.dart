import 'dart:convert';

/// One change made while offline (or queued behind others), waiting to be sent
/// to the server. Its [id] doubles as the `Idempotency-Key`, so replaying it —
/// even if the first attempt secretly succeeded — never applies it twice.
class PendingMutation {
  const PendingMutation({
    required this.id,
    required this.userId,
    required this.entity,
    required this.op,
    required this.targetIds,
    required this.method,
    required this.path,
    required this.body,
    this.baseUpdatedAt,
    this.effect = const {},
    required this.createdMs,
    this.attempts = 0,
    this.nextRetryMs = 0,
    this.lastError,
    this.seq,
  });

  final String id;
  final String userId;

  /// transaction | goal | loan
  final String entity;

  /// create | update | delete
  final String op;

  /// The record(s) this change is about (bulk delete has several).
  final List<String> targetIds;

  final String method;
  final String path;
  final Map<String, dynamic> body;

  /// `updated_at` of the record when it was last seen, for the server's
  /// "was it changed elsewhere?" check (server wins on a clash).
  final String? baseUpdatedAt;

  /// What the UI should show meanwhile: for a create the full local record.
  final Map<String, dynamic> effect;

  final int createdMs;
  final int attempts;
  final int nextRetryMs;
  final String? lastError;

  /// Insertion order, assigned by the store.
  final int? seq;

  PendingMutation copyWith({int? attempts, int? nextRetryMs, String? lastError}) => PendingMutation(
        id: id,
        userId: userId,
        entity: entity,
        op: op,
        targetIds: targetIds,
        method: method,
        path: path,
        body: body,
        baseUpdatedAt: baseUpdatedAt,
        effect: effect,
        createdMs: createdMs,
        attempts: attempts ?? this.attempts,
        nextRetryMs: nextRetryMs ?? this.nextRetryMs,
        lastError: lastError ?? this.lastError,
        seq: seq,
      );

  String get bodyJson => jsonEncode(body);
  String get effectJson => jsonEncode(effect);

  static Map<String, dynamic> decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    final v = jsonDecode(raw);
    return v is Map ? v.cast<String, dynamic>() : {};
  }
}

/// The queue of changes waiting to sync, plus the "last seen version" of each
/// record (for conflict detection).
abstract class MutationStore {
  Future<void> enqueue(PendingMutation m);

  /// Every waiting change for [userId], oldest first (used to show them in the
  /// UI and to decide whether new writes must queue behind them).
  Future<List<PendingMutation>> all(String userId);

  /// Every waiting change, oldest first. Not user scoped: the bearer token
  /// decides whose data a replay touches. Replays must follow this order, so a
  /// change that is backing off holds back the ones queued after it.
  Future<List<PendingMutation>> allPending();

  Future<int> count({String? userId});
  Future<void> remove(String id);
  Future<void> reschedule(String id, {required int attempts, required int nextRetryMs, String? error});
  Future<void> clearMutations({String? userId});

  Future<void> putVersions(String userId, String entity, Map<String, String> updatedAtById);
  Future<String?> version(String userId, String entity, String id);
}
