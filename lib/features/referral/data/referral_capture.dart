import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_install_referrer/play_install_referrer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_exception.dart';
import '../../auth/providers/auth_controller.dart';
import 'referral_repository.dart';

/// Invite codes are 6 characters from this alphabet (no 0, O, 1 or I).
const referralCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
final _codePattern = RegExp('^[$referralCodeAlphabet]{6}\$');

/// [raw] as a valid invite code (trimmed, upper case), or null.
String? normalizeReferralCode(String? raw) {
  final code = raw?.trim().toUpperCase() ?? '';
  return _codePattern.hasMatch(code) ? code : null;
}

/// The code in an invite link `https://<domain>/i/{code}`, or null.
String? referralCodeFromUri(Uri uri) {
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.length < 2 || segments.first != 'i') return null;
  return normalizeReferralCode(segments[1]);
}

/// The code in a Play Install Referrer string (`ref=CODE`, possibly still
/// URL-encoded as `ref%3DCODE`), or null.
String? referralCodeFromInstallReferrer(String? referrer) {
  if (referrer == null || referrer.isEmpty) return null;
  var raw = referrer;
  // Decode at most twice: Play may hand back the value still encoded.
  for (var i = 0; i < 2 && raw.contains('%'); i++) {
    try {
      raw = Uri.decodeComponent(raw);
    } catch (_) {
      break;
    }
  }
  try {
    final params = Uri.splitQueryString(raw);
    return normalizeReferralCode(params['ref'] ?? params['referral_code']);
  } catch (_) {
    return null;
  }
}

/// A code waiting to be sent: with the sign-up request, or to
/// `POST /referral/claim` when the person is already signed in.
class PendingReferralStore {
  PendingReferralStore(this._prefs);

  final SharedPreferences _prefs;

  static const _codeKey = 'referral.pending_code';
  static const _installCheckedKey = 'referral.install_referrer_checked';

  String? read() => normalizeReferralCode(_prefs.getString(_codeKey));

  /// Keep [code] if it is valid. The latest invite the person opened wins.
  Future<bool> save(String? code) async {
    final valid = normalizeReferralCode(code);
    if (valid == null) return false;
    await _prefs.setString(_codeKey, valid);
    return true;
  }

  Future<void> clear() => _prefs.remove(_codeKey);

  bool get installReferrerChecked => _prefs.getBool(_installCheckedKey) ?? false;

  Future<void> markInstallReferrerChecked() => _prefs.setBool(_installCheckedKey, true);
}

/// Catches invite codes (app links and the Play Install Referrer) and hands
/// them to the API once there is an account to attach them to.
class ReferralCapture {
  ReferralCapture._();

  /// Read the Play Install Referrer once, on the first launch after install.
  static Future<void> checkInstallReferrer(
    PendingReferralStore store, {
    Future<String?> Function()? readReferrer,
  }) async {
    if (store.installReferrerChecked) return;
    if (readReferrer == null && !Platform.isAndroid) {
      await store.markInstallReferrerChecked();
      return;
    }
    try {
      final referrer = await (readReferrer ?? _playReferrer)();
      final code = referralCodeFromInstallReferrer(referrer);
      // An invite link opened before this keeps priority.
      if (code != null && store.read() == null) await store.save(code);
      await store.markInstallReferrerChecked();
    } catch (_) {
      // Play services unavailable right now: try again on the next launch.
    }
  }

  static Future<String?> _playReferrer() async =>
      (await PlayInstallReferrer.installReferrer).installReferrer;

  /// When signed in, send a waiting code to `POST /referral/claim`. A code the
  /// server answered (accepted or refused) is forgotten; a network failure
  /// keeps it for the next try.
  static Future<void> claimPending(ProviderContainer container, PendingReferralStore store) async {
    final code = store.read();
    if (code == null) return;
    if (container.read(authControllerProvider).status != AuthStatus.authenticated) return;
    try {
      await container.read(referralRepositoryProvider).claim(code);
      await store.clear();
    } on ApiException catch (e) {
      final status = e.statusCode;
      if (status != null && status >= 400 && status < 500 && status != 401) await store.clear();
    } catch (_) {}
  }
}
