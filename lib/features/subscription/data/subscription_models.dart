// Models mirroring the backend subscription/billing payloads.

/// Premium entitlement tokens — must match App\Enums\Entitlement on the API.
abstract class Entitlements {
  static const coachChat = 'coach.chat';
  static const coachHistory = 'coach.history';
  static const advancedInsights = 'insights.advanced';
  static const receiptScan = 'capture.ai';
}

/// A monetary amount as serialized by the API's Money value object.
class MoneyView {
  const MoneyView({
    required this.minorUnits,
    required this.currency,
    required this.amount,
    required this.formatted,
  });

  final int minorUnits;
  final String currency;
  final double amount;
  final String formatted;

  factory MoneyView.fromJson(Map<String, dynamic> json) {
    return MoneyView(
      minorUnits: (json['minor_units'] as num?)?.toInt() ?? 0,
      currency: json['currency']?.toString() ?? 'MWK',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      formatted: json['formatted']?.toString() ?? '',
    );
  }
}

/// The user's current subscription state + entitlements (folded into /auth/me).
class SubscriptionInfo {
  const SubscriptionInfo({
    required this.active,
    this.period,
    this.planLabel,
    this.source,
    this.endsAt,
    this.isTrial = false,
    this.entitlements = const [],
  });

  final bool active;
  final String? period;
  final String? planLabel;
  final String? source;
  final DateTime? endsAt;
  final bool isTrial;
  final List<String> entitlements;

  bool can(String entitlement) => entitlements.contains(entitlement);

  const SubscriptionInfo.none()
      : active = false,
        period = null,
        planLabel = null,
        source = null,
        endsAt = null,
        isTrial = false,
        entitlements = const [];

  factory SubscriptionInfo.fromJson(Map<String, dynamic> json) {
    return SubscriptionInfo(
      active: json['active'] == true,
      period: json['period']?.toString(),
      planLabel: json['plan_label']?.toString(),
      source: json['source']?.toString(),
      endsAt: json['ends_at'] != null
          ? DateTime.tryParse(json['ends_at'].toString())
          : null,
      isTrial: json['is_trial'] == true,
      entitlements: (json['entitlements'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }
}

/// A purchasable plan in the catalogue.
class PlanOption {
  const PlanOption({
    required this.period,
    required this.label,
    required this.days,
    required this.amount,
  });

  final String period;
  final String label;
  final int days;
  final MoneyView amount;

  /// Per-day price in major units — used to surface "best value".
  double get perDay => days > 0 ? amount.amount / days : amount.amount;

  factory PlanOption.fromJson(Map<String, dynamic> json) {
    return PlanOption(
      period: json['period']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      days: (json['days'] as num?)?.toInt() ?? 1,
      amount: MoneyView.fromJson(
          (json['amount'] as Map?)?.cast<String, dynamic>() ?? const {}),
    );
  }
}

/// An invoice — the bill for one subscription purchase, and the source of a
/// receipt once paid.
class InvoiceModel {
  const InvoiceModel({
    required this.id,
    required this.period,
    required this.periodLabel,
    required this.amount,
    required this.currency,
    required this.status,
    required this.txRef,
    required this.isResumable,
    this.provider,
    this.checkoutUrl,
    this.paidAt,
    this.failureReason,
    this.createdAt,
  });

  final String id;
  final String period;
  final String periodLabel;
  final MoneyView amount;
  final String currency;
  final String status; // pending | paid | failed | cancelled | comped
  final String txRef;
  final bool isResumable;
  final String? provider;
  final String? checkoutUrl;
  final DateTime? paidAt;
  final String? failureReason;
  final DateTime? createdAt;

  bool get isPaid => status == 'paid' || status == 'comped';

  factory InvoiceModel.fromJson(Map<String, dynamic> json) {
    return InvoiceModel(
      id: json['id'].toString(),
      period: json['period']?.toString() ?? '',
      periodLabel: json['period_label']?.toString() ?? '',
      amount: MoneyView.fromJson(
          (json['amount'] as Map?)?.cast<String, dynamic>() ?? const {}),
      currency: json['currency']?.toString() ?? 'MWK',
      status: json['status']?.toString() ?? 'pending',
      txRef: json['tx_ref']?.toString() ?? '',
      isResumable: json['is_resumable'] == true,
      provider: json['provider']?.toString(),
      checkoutUrl: json['checkout_url']?.toString(),
      paidAt: json['paid_at'] != null
          ? DateTime.tryParse(json['paid_at'].toString())
          : null,
      failureReason: json['failure_reason']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }
}
