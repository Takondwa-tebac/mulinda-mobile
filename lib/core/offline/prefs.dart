import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the per-account offline-mode switch is kept.
String offlineModePrefKey(String userId) => 'offline_mode_enabled_$userId';

/// App preferences, loaded once before the first frame so settings (like the
/// offline-mode switch) are known synchronously. Overridden in `main()`.
///
/// Reading these lazily caused a startup race: the first requests (the
/// dashboard, accounts…) were sent before the switch had been read, so they were
/// neither saved for offline use nor answered from the saved copy.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider must be overridden in main()'),
);
