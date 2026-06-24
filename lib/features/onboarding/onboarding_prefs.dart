import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kKey = 'onboarding_seen';

/// Persists whether the user has already seen the onboarding carousel.
class OnboardingPrefs {
  static Future<bool> hasSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kKey) ?? false;
  }

  static Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kKey, true);
  }
}

/// Riverpod provider: true once we know the user has seen onboarding.
/// Starts false until [OnboardingPrefs.hasSeen] resolves in the splash.
final onboardingSeenProvider = StateProvider<bool>((ref) => false);
