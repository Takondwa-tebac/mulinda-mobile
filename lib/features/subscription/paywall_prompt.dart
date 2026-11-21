import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'data/subscription_models.dart';

/// Pseudo-entitlement for the free SMS capture allowance (the server answers
/// `sms_capture_limit_reached` rather than naming an entitlement).
const smsCaptureEntitlement = 'sms.capture';

/// A premium wall the server put up (HTTP 402).
class PaywallTrigger {
  const PaywallTrigger({required this.code, this.entitlement});

  final String code;
  final String? entitlement;

  @override
  bool operator ==(Object other) =>
      other is PaywallTrigger &&
      other.code == code &&
      other.entitlement == entitlement;

  @override
  int get hashCode => Object.hash(code, entitlement);
}

/// Read a 402 response: only `subscription_required` and
/// `sms_capture_limit_reached` mean "show the paywall". Other 402s (such as a
/// records export waiting for its one-time payment) carry their own flow.
PaywallTrigger? paywallTriggerFor(int? statusCode, Object? body) {
  if (statusCode != 402 || body is! Map) return null;
  final code = body['code']?.toString();
  switch (code) {
    case 'subscription_required':
      final entitlement = body['entitlement']?.toString();
      return PaywallTrigger(
        code: code!,
        entitlement: (entitlement?.isEmpty ?? true) ? null : entitlement,
      );
    case 'sms_capture_limit_reached':
      return PaywallTrigger(code: code!, entitlement: smsCaptureEntitlement);
    default:
      return null;
  }
}

/// Translation key of the benefit headline shown for a locked entitlement.
String paywallHeadlineKey(String? entitlement) => switch (entitlement) {
  Entitlements.coachChat => 'paywall.headline.coachChat',
  Entitlements.coachHistory => 'paywall.headline.coachHistory',
  Entitlements.advancedInsights => 'paywall.headline.insights',
  Entitlements.receiptScan => 'paywall.headline.aiCapture',
  Entitlements.offlineMode => 'paywall.headline.offline',
  smsCaptureEntitlement => 'paywall.headline.smsCapture',
  _ => 'paywall.headline.default',
};

/// Decides when a server 402 may open the paywall by itself, so it is helpful
/// rather than intrusive:
///
///  * never while a save the screen is handling is in progress ([guardSave]) —
///    that screen shows its own message;
///  * not more than once per [cooldown], and never on top of an open paywall;
///  * a 402 from a read (GET) opens the sheet; one from a write only offers a
///    "See plans" snackbar, so typing or saving is never interrupted.
class PaywallPrompter {
  PaywallPrompter({
    this.cooldown = const Duration(seconds: 45),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static final instance = PaywallPrompter();

  final Duration cooldown;
  final DateTime Function() _clock;

  int _savesInProgress = 0;
  DateTime? _lastPrompt;
  bool _sheetOpen = false;

  final _events = StreamController<PaywallTrigger>.broadcast();

  /// Every paywall-worthy 402 the app saw (shown or not).
  Stream<PaywallTrigger> get events => _events.stream;

  bool get saveInProgress => _savesInProgress > 0;

  /// Run a save that handles its own 402: the global prompt stays out of the way.
  Future<T> guardSave<T>(Future<T> Function() save) async {
    _savesInProgress++;
    try {
      return await save();
    } finally {
      _savesInProgress--;
    }
  }

  /// Whether a prompt may be shown now (and, if so, starts the cooldown).
  bool claim() {
    if (_savesInProgress > 0 || _sheetOpen) return false;
    final now = _clock();
    final last = _lastPrompt;
    if (last != null && now.difference(last) < cooldown) return false;
    _lastPrompt = now;
    return true;
  }

  /// Keep track of the sheet so a second 402 does not stack another one.
  void sheetOpened() => _sheetOpen = true;
  void sheetClosed() => _sheetOpen = false;

  /// Record a trigger and say how it should be shown, or null to stay quiet.
  PaywallPresentation? handle(
    PaywallTrigger trigger, {
    required String method,
  }) {
    _events.add(trigger);
    if (!claim()) return null;
    return method.toUpperCase() == 'GET'
        ? PaywallPresentation.sheet
        : PaywallPresentation.snackbar;
  }

  /// Show [presentation] for [trigger] using the app's navigator context.
  /// [openPaywall] opens the sheet (injected to keep this file free of UI deps).
  static void present(
    BuildContext context,
    PaywallTrigger trigger,
    PaywallPresentation presentation,
    Future<void> Function(BuildContext context, PaywallTrigger trigger)
    openPaywall,
  ) {
    if (presentation == PaywallPresentation.sheet) {
      unawaited(openPaywall(context, trigger));
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(paywallHeadlineKey(trigger.entitlement).tr()),
          action: SnackBarAction(
            label: 'paywall.seePlans'.tr(),
            onPressed: () => unawaited(openPaywall(context, trigger)),
          ),
        ),
      );
  }
}

enum PaywallPresentation { sheet, snackbar }
