import 'package:shared_preferences/shared_preferences.dart';

/// Guards offline mode against the phone's clock being wound back to stretch a
/// plan that has run out.
///
/// With no connection the app cannot know the real time, but it can notice when
/// the clock goes *backwards*: it remembers the latest time it has seen (the
/// server's time whenever it is online, otherwise the phone's, which only ever
/// moves this value forward). If the phone now claims an earlier time than that,
/// offline mode pauses until the next time the app reaches the server.
class TrustedClock {
  static const _key = 'trusted_clock_ms';

  /// Normal clock corrections (network time sync, DST) are far smaller than this.
  static const tolerance = Duration(minutes: 10);

  /// Note the phone's time; the remembered value only moves forward.
  static void observeDevice(SharedPreferences prefs, {DateTime? now}) {
    final ms = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final seen = prefs.getInt(_key);
    if (seen == null || ms >= seen) prefs.setInt(_key, ms);
  }

  /// The server's time is the truth, so it replaces whatever was remembered
  /// (even if that was later), which also clears an earlier "clock looks wrong".
  static void recordServerTime(SharedPreferences prefs, DateTime serverNow) {
    prefs.setInt(_key, serverNow.millisecondsSinceEpoch);
  }

  /// True when the phone's clock is earlier than a time it has already seen.
  static bool looksTampered(SharedPreferences prefs, {DateTime? now}) {
    final seen = prefs.getInt(_key);
    if (seen == null) return false;
    final ms = (now ?? DateTime.now()).millisecondsSinceEpoch;
    return ms < seen - tolerance.inMilliseconds;
  }
}
