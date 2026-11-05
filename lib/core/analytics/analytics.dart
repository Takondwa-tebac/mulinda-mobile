import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sends a batch of events to the API. Throws on failure.
typedef AnalyticsSender = Future<void> Function(Map<String, dynamic> body);

/// Product-funnel analytics (onboarding finished, paywall seen / plan picked /
/// dismissed). Events are queued on the phone and sent in batches to
/// `POST /v1/analytics/events`, so they survive being offline or signed out
/// (onboarding happens before sign-in) and never slow the UI down.
///
/// Only allow-listed names and property keys are kept, values are short scalars,
/// and nothing personal (names, numbers, message text, amounts) is ever sent.
class Analytics {
  Analytics._();

  /// Event names the server accepts from the app.
  static const allowedEvents = {
    'onboarding_completed',
    'upgrade_prompt_viewed',
    'paywall_plan_selected',
    'paywall_dismissed',
  };

  /// Property keys the server keeps (see ProductAnalytics::CLIENT_PROPERTIES).
  static const allowedProperties = {
    'feature',
    'entitlement',
    'surface',
    'code',
    'period',
    'days',
    'step',
    'reason',
    'trial_active',
    'plans_shown',
    'locale',
  };

  static const queueKey = 'analytics_queue_v1';

  /// The server takes at most 50 events per request.
  static const batchSize = 50;

  /// Oldest events are dropped past this, so a phone that is never online
  /// cannot grow the queue without bound.
  static const maxQueued = 500;

  static const _maxString = 64;

  static AnalyticsSender? _sender;
  static bool Function() _canSend = () => false;
  static Future<SharedPreferences> Function() _prefs =
      SharedPreferences.getInstance;
  static Timer? _flushTimer;
  static Future<int>? _flushing;
  static String? _appVersion;

  /// Wire the network side (done once the API client exists). [canSend] says
  /// whether a signed-in session is available — events wait until it is.
  static void configure({
    required AnalyticsSender sender,
    required bool Function() canSend,
    Future<SharedPreferences> Function()? prefs,
  }) {
    _sender = sender;
    _canSend = canSend;
    if (prefs != null) _prefs = prefs;
    _scheduleFlush(const Duration(seconds: 5));
  }

  /// Reset everything (tests).
  @visibleForTesting
  static void resetForTest() {
    _sender = null;
    _canSend = () => false;
    _prefs = SharedPreferences.getInstance;
    _flushTimer?.cancel();
    _flushTimer = null;
    _flushing = null;
    _appVersion = 'test';
  }

  /// Queue an event. Never throws and never waits on the network.
  static Future<void> track(
    String name, [
    Map<String, Object?> props = const {},
  ]) async {
    if (!allowedEvents.contains(name)) return;
    try {
      final prefs = await _prefs();
      final queue = _read(prefs)
        ..add({
          'name': name,
          'properties': sanitize(props),
          'occurred_at': DateTime.now().toUtc().toIso8601String(),
        });
      final trimmed = queue.length > maxQueued
          ? queue.sublist(queue.length - maxQueued)
          : queue;
      await prefs.setString(queueKey, jsonEncode(trimmed));
      _scheduleFlush(
        trimmed.length >= batchSize
            ? Duration.zero
            : const Duration(seconds: 10),
      );
    } catch (_) {
      // Analytics must never break the app.
    }
  }

  /// How many events are waiting to be sent.
  static Future<int> pendingCount() async {
    try {
      return _read(await _prefs()).length;
    } catch (_) {
      return 0;
    }
  }

  /// Send queued events in batches of [batchSize]. Stops at the first failure
  /// and keeps what was not sent; a batch the server rejects as invalid (422 or
  /// another 4xx that retrying cannot fix) is dropped so it cannot block the
  /// queue forever. Returns how many events were sent.
  static Future<int> flush() {
    return _flushing ??= _flush().whenComplete(() => _flushing = null);
  }

  static Future<int> _flush() async {
    final sender = _sender;
    if (sender == null || !_canSend()) return 0;

    var sent = 0;
    try {
      final prefs = await _prefs();
      while (true) {
        final queue = _read(prefs);
        if (queue.isEmpty) break;
        final batch = queue.take(batchSize).toList();
        try {
          await sender({
            'platform': _platform(),
            'app_version': await _version(),
            'events': batch,
          });
          sent += batch.length;
        } on DioException catch (e) {
          final status = e.response?.statusCode;
          // Offline, 5xx, 401, 429: keep the batch and try later.
          if (!_isPermanentRejection(status)) {
            break;
          }
        }
        // Re-read: events may have been added while the request was in flight.
        final latest = _read(prefs);
        await prefs.setString(
          queueKey,
          jsonEncode(latest.skip(batch.length).toList()),
        );
      }
    } catch (_) {
      // Keep the queue for the next attempt.
    }
    return sent;
  }

  static bool _isPermanentRejection(int? status) =>
      status != null &&
      status >= 400 &&
      status < 500 &&
      status != 401 &&
      status != 408 &&
      status != 429;

  /// Keep allow-listed keys with short scalar values only.
  @visibleForTesting
  static Map<String, Object> sanitize(Map<String, Object?> props) {
    final clean = <String, Object>{};
    props.forEach((key, value) {
      if (!allowedProperties.contains(key) || value == null) return;
      if (value is bool || value is int || value is double) {
        clean[key] = value;
      } else if (value is String && value.isNotEmpty) {
        clean[key] = value.length > _maxString
            ? value.substring(0, _maxString)
            : value;
      }
    });
    return clean;
  }

  static List<Map<String, dynamic>> _read(SharedPreferences prefs) {
    final raw = prefs.getString(queueKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((m) => m.cast<String, dynamic>())
          .toList();
    } catch (_) {
      return [];
    }
  }

  static void _scheduleFlush(Duration delay) {
    if (_sender == null) return;
    _flushTimer?.cancel();
    _flushTimer = Timer(delay, () => unawaited(flush()));
  }

  static String _platform() {
    if (kIsWeb) return 'web';
    try {
      return Platform.isIOS ? 'ios' : 'android';
    } catch (_) {
      return 'android';
    }
  }

  static Future<String?> _version() async {
    if (_appVersion != null) return _appVersion;
    try {
      _appVersion = (await PackageInfo.fromPlatform()).version;
    } catch (_) {
      _appVersion = null;
    }
    return _appVersion;
  }
}
