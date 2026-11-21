import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the user is in the first-run journey that follows a sign in:
/// SMS access (Android), the 30-day import, then a first look at Home.
@immutable
class FirstRunState {
  const FirstRunState({
    this.started = false,
    this.smsStepPending = false,
    this.firstVisit = false,
    this.smsSkipped = false,
    this.importedCount = 0,
  });

  /// A sign in happened in this session (not a restored one).
  final bool started;

  /// Just signed in on this phone: show the SMS access step before Home.
  final bool smsStepPending;

  /// Home has not been shown to this user on this phone yet (no "Welcome
  /// back"). Stays true for the rest of the session once Home has opened.
  final bool firstVisit;

  /// The user chose "Not now" (or Android refused) on the SMS step.
  final bool smsSkipped;

  /// Money messages sent by the first-run import (0 when none or skipped).
  final int importedCount;

  FirstRunState copyWith({bool? smsStepPending, bool? firstVisit, bool? smsSkipped, int? importedCount}) =>
      FirstRunState(
        started: started,
        smsStepPending: smsStepPending ?? this.smsStepPending,
        firstVisit: firstVisit ?? this.firstVisit,
        smsSkipped: smsSkipped ?? this.smsSkipped,
        importedCount: importedCount ?? this.importedCount,
      );
}

/// The SMS step and history import exist only where an app may read the SMS
/// inbox: Android.
bool get smsStepSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

String _homeSeenKey(String userId) => 'home_seen_$userId';

class FirstRunController extends Notifier<FirstRunState> {
  String? _markedFor;

  @override
  FirstRunState build() => const FirstRunState();

  /// A sign in or a new account on this phone (not a restored session).
  Future<void> start(String userId) async {
    state = FirstRunState(started: true, smsStepPending: smsStepSupported);
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getBool(_homeSeenKey(userId)) ?? false;
      state = state.copyWith(firstVisit: !seen);
    } catch (_) {
      // Unknown: keep the neutral "returning" greeting.
    }
  }

  /// The SMS step is finished: [granted] or not.
  void smsStepDone({required bool granted}) =>
      state = state.copyWith(smsStepPending: false, smsSkipped: !granted);

  void importDone(int count) => state = state.copyWith(importedCount: count);

  /// Home has been shown; later sessions greet the user as returning.
  Future<void> markHomeSeen(String userId) async {
    if (_markedFor == userId) return;
    _markedFor = userId;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_homeSeenKey(userId), true);
    } catch (_) {}
  }

  /// Signed out: forget this session's journey.
  void reset() => state = const FirstRunState();
}

final firstRunProvider = NotifierProvider<FirstRunController, FirstRunState>(FirstRunController.new);
