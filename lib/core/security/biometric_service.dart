import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wraps local_auth + the persisted "enabled" / "prompt dismissed" flags for
/// the biometric app-lock feature.
class BiometricService {
  final LocalAuthentication _auth = LocalAuthentication();

  static const _enabledKey = 'biometric_enabled';
  static const _promptDismissedKey = 'biometric_prompt_dismissed';

  /// The device can do biometric (or device-credential) auth.
  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// At least one biometric is enrolled (fingerprint/face) on the device.
  Future<bool> hasEnrolledBiometrics() async {
    try {
      return (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Prompt for biometrics (with device PIN/pattern fallback). Returns true on
  /// success; false on failure/cancel (never throws).
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }

  Future<bool> promptDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_promptDismissedKey) ?? false;
  }

  Future<void> dismissPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_promptDismissedKey, true);
  }
}

final biometricServiceProvider =
    Provider<BiometricService>((ref) => BiometricService());
