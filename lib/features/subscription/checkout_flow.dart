import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../auth/providers/auth_controller.dart';
import 'data/subscription_models.dart';
import 'data/subscription_repository.dart';
import 'screens/checkout_webview_screen.dart';

/// How the person left the hosted checkout page.
enum CheckoutExit {
  /// The payment page sent them back to our return URL (any result).
  returned,

  /// They closed the page themselves before it finished.
  closed,
}

/// What actually happened to the invoice, according to the server.
enum CheckoutOutcome {
  /// Paid and the plan is active.
  paid,

  /// Not confirmed yet (mobile-money approval can take a moment); it will
  /// switch on by itself once the payment is confirmed.
  pending,

  /// The payment was declined or did not go through.
  failed,

  /// The person left checkout; the open invoice was cancelled.
  cancelled,
}

/// Turn a checkout exit into an outcome by asking the server — the URL the
/// payment page returns to is never trusted.
///
/// After a return the invoice is re-checked a few times (a confirmation can lag
/// a few seconds). After a close it is checked once: a payment that already went
/// through still counts, and an invoice that is still open is cancelled so it
/// does not linger as "pending".
Future<CheckoutOutcome> resolveCheckout({
  required CheckoutExit exit,
  required Future<InvoiceModel> Function() verify,
  required Future<InvoiceModel> Function() cancel,
  int attempts = 3,
  Duration retryDelay = const Duration(seconds: 2),
}) async {
  final tries = exit == CheckoutExit.returned ? attempts : 1;

  for (var i = 0; i < tries; i++) {
    if (i > 0) await Future<void>.delayed(retryDelay);
    try {
      final invoice = await verify();
      if (invoice.isPaid) return CheckoutOutcome.paid;
      if (invoice.status == 'failed') return CheckoutOutcome.failed;
      if (invoice.status == 'cancelled') return CheckoutOutcome.cancelled;
    } on ApiException catch (_) {
      // The gateway could not be reached; treat as not confirmed yet.
    }
  }

  if (exit == CheckoutExit.closed) {
    try {
      final cancelled = await cancel();
      if (cancelled.isPaid) return CheckoutOutcome.paid;
      return cancelled.status == 'cancelled'
          ? CheckoutOutcome.cancelled
          : CheckoutOutcome.pending;
    } on ApiException catch (_) {
      return CheckoutOutcome.pending;
    }
  }

  return CheckoutOutcome.pending;
}

/// Open the checkout page for [invoice], then resolve and announce the result.
/// Refreshes the signed-in user when the plan became active.
Future<CheckoutOutcome?> runCheckout(
  BuildContext context,
  WidgetRef ref,
  InvoiceModel invoice,
) async {
  final url = invoice.checkoutUrl;
  if (url == null) return null;

  final exit = await Navigator.of(context).push<CheckoutExit>(
    MaterialPageRoute(builder: (_) => CheckoutWebViewScreen(checkoutUrl: url)),
  );

  final repo = ref.read(subscriptionRepositoryProvider);
  final outcome = await resolveCheckout(
    exit: exit ?? CheckoutExit.closed,
    verify: () => repo.verify(invoice.id),
    cancel: () => repo.cancel(invoice.id),
  );

  if (outcome == CheckoutOutcome.paid) {
    await ref.read(authControllerProvider.notifier).refresh();
  }
  return outcome;
}

/// Translation key describing [outcome] to the person.
String checkoutOutcomeMessageKey(CheckoutOutcome outcome) => switch (outcome) {
  CheckoutOutcome.paid => 'paywall.checkout.paid',
  CheckoutOutcome.pending => 'paywall.checkout.pending',
  CheckoutOutcome.failed => 'paywall.checkout.failed',
  CheckoutOutcome.cancelled => 'paywall.checkout.cancelled',
};

/// Show the outcome as a snackbar; failures offer [onRetry].
void announceCheckoutOutcome(
  BuildContext context,
  CheckoutOutcome outcome, {
  VoidCallback? onRetry,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final scheme = Theme.of(context).colorScheme;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(checkoutOutcomeMessageKey(outcome).tr()),
        duration: const Duration(seconds: 6),
        backgroundColor: outcome == CheckoutOutcome.failed
            ? scheme.error
            : null,
        action: outcome == CheckoutOutcome.failed && onRetry != null
            ? SnackBarAction(
                label: 'paywall.checkout.retry'.tr(),
                onPressed: onRetry,
              )
            : null,
      ),
    );
}
