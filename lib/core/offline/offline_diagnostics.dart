import 'package:flutter/foundation.dart';

/// The last few things that went wrong while saving or reading offline data.
///
/// Offline code never lets a failure interrupt the user (a screen still loads,
/// the app keeps working), which also makes failures invisible. This keeps a short
/// list so the Offline screen can show what happened instead of just "nothing
/// saved". Kept in memory only and never sent anywhere.
class OfflineDiagnostics {
  static const _max = 10;
  static final List<String> _entries = [];

  /// Notifies the screen when something new is recorded.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static List<String> get entries => List.unmodifiable(_entries);

  static void record(String where, Object error) {
    final text = error.toString().replaceAll(RegExp(r'\s+'), ' ');
    final message = text.length > 240 ? '${text.substring(0, 240)}...' : text;
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');

    _entries.insert(0, '$hh:$mm:$ss  $where: $message');
    if (_entries.length > _max) _entries.removeLast();
    changes.value++;
    debugPrint('[offline] $where: $message');
  }

  static void clear() {
    _entries.clear();
    changes.value++;
  }
}
