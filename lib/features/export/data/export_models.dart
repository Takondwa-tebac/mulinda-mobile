import '../../../core/money/money.dart';

/// A financial-records export request and its lifecycle.
class ExportModel {
  const ExportModel({
    required this.id,
    required this.format,
    required this.status,
    this.amount,
    this.checkoutUrl,
    this.downloadable = false,
    this.rowCount,
    this.failureReason,
  });

  final String id;
  final String format; // csv | pdf
  final String status; // pending_payment | processing | ready | failed
  final Money? amount;
  final String? checkoutUrl;
  final bool downloadable;
  final int? rowCount;
  final String? failureReason;

  bool get isReady => status == 'ready';
  bool get needsPayment => status == 'pending_payment';
  bool get isFailed => status == 'failed';

  factory ExportModel.fromJson(Map<String, dynamic> json) {
    return ExportModel(
      id: json['id'].toString(),
      format: json['format']?.toString() ?? 'csv',
      status: json['status']?.toString() ?? 'processing',
      amount: json['amount'] is Map ? Money.parse(json['amount']) : null,
      checkoutUrl: json['checkout_url']?.toString(),
      downloadable: json['downloadable'] == true,
      rowCount: json['row_count'] is int ? json['row_count'] as int : null,
      failureReason: json['failure_reason']?.toString(),
    );
  }
}
