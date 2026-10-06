import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../../../core/offline/mutation_sync.dart';
import 'sms_auto_capture.dart' show smsCaptureLog;
import 'sms_outbox.dart';

const _taskName = 'mulinda_sms_outbox_sync';
const _periodicName = 'mulinda_sms_outbox_periodic';
const _oneOffName = 'mulinda_sms_outbox_oneoff';

/// Entry point the OS invokes (even with the app closed) when a scheduled sync
/// is due. Must be top-level and annotated so it survives tree-shaking.
@pragma('vm:entry-point')
void smsSyncCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      // Changes made offline first (they may depend on each other), then SMS.
      await MutationSync.instance.flush();
      final result = await SmsOutbox.instance.flush();
      smsCaptureLog(
        'background sync: created=${result.created} dup=${result.duplicates} '
        'pending=${result.pending}',
      );
      return true;
    } catch (e) {
      smsCaptureLog('background sync failed: $e');
      return false; // let the OS retry with backoff
    }
  });
}

/// Schedules the OS-level sync that drains the SMS outbox when the phone is
/// offline and the app is closed:
///
/// * a one-off job, constrained to "network connected", queued whenever an SMS
///   had to be saved offline — it runs as soon as a connection is available;
/// * a periodic safety net (every 30 min while enabled) for anything the
///   one-off missed.
///
/// All calls are best-effort: unsupported platforms are ignored.
class SmsBackgroundSync {
  SmsBackgroundSync._();

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  /// Register the dispatcher. Call once at app start.
  static Future<void> init() async {
    if (!_supported) return;
    try {
      await Workmanager().initialize(smsSyncCallbackDispatcher);
    } catch (e) {
      smsCaptureLog('workmanager init failed: $e');
    }
  }

  /// Start the periodic safety net (auto-capture enabled).
  static Future<void> startPeriodic() async {
    if (!_supported) return;
    try {
      await Workmanager().registerPeriodicTask(
        _periodicName,
        _taskName,
        frequency: const Duration(minutes: 30),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } catch (e) {
      smsCaptureLog('workmanager periodic failed: $e');
    }
  }

  /// Stop all background sync (auto-capture turned off).
  static Future<void> stop() async {
    if (!_supported) return;
    try {
      await Workmanager().cancelByUniqueName(_periodicName);
      await Workmanager().cancelByUniqueName(_oneOffName);
    } catch (_) {}
  }

  /// Run a sync as soon as the device is online. Safe to call repeatedly: a
  /// pending request is kept rather than duplicated.
  static Future<void> syncWhenOnline() async {
    if (!_supported) return;
    try {
      // The headless SMS isolate may not have initialised the plugin yet.
      await Workmanager().initialize(smsSyncCallbackDispatcher);
      await Workmanager().registerOneOffTask(
        _oneOffName,
        _taskName,
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingWorkPolicy.keep,
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(minutes: 1),
      );
    } catch (e) {
      smsCaptureLog('workmanager one-off failed: $e');
    }
  }
}
