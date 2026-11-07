import 'package:easy_localization/easy_localization.dart';

import '../../../core/money/money_json.dart';
import '../../../core/widgets/transaction_tile.dart';
import '../data/activity_models.dart';
import '../data/day_grouping.dart';

/// `14:05` local time of an ISO timestamp, or null.
String? timeOfDay(DateTime? local) {
  if (local == null) return null;
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

/// `Tue 3 Nov` (plus the year when it is not this year), with weekday and
/// month names from the translations so Chichewa reads naturally.
String shortDate(DateTime day, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final weekday = 'common.weekdayShort.${day.weekday}'.tr();
  final month = 'common.monthShort.${day.month}'.tr();
  final year = day.year == ref.year ? '' : ' ${day.year}';
  return '$weekday ${day.day} $month$year';
}

/// "Today", "Yesterday" or a short date for a day header.
String dayHeaderLabel(DateTime? day, {DateTime? now}) {
  final at = now ?? DateTime.now();
  return switch (dayKind(day, at)) {
    DayKind.today => 'common.today'.tr(),
    DayKind.yesterday => 'common.yesterday'.tr(),
    DayKind.other => shortDate(day!, now: at),
    DayKind.unknown => 'activity2.noDate'.tr(),
  };
}

/// A minor-unit total formatted like the server's amounts.
String formatMinor(int minor, String currency) => formatMoney(minor / 100, currency);

// Bank "FT" transfer codes: FT + 6 or more capitals/digits, including a digit.
final _ftRef = RegExp(r'FT(?=[A-Z0-9]*\d)[A-Z0-9]{6,}');
final _dottedNumber = RegExp(r'\d+\.\d+');
final _word = RegExp(r'[A-Za-z]{3,}');

/// Whether a "merchant" is really a bank reference (e.g.
/// `375870.1005120443.FT26278T9Q7Y.2.70`): an FT… code, dotted numbers, no
/// word of 3+ letters, or mostly digits. Such text is kept as the reference,
/// never shown as a name.
bool looksLikeReference(String? text) {
  final t = text?.trim() ?? '';
  if (t.isEmpty) return false;
  if (_ftRef.hasMatch(t)) return true;
  if (!_word.hasMatch(t)) return true;
  if (_dottedNumber.hasMatch(t) && t.replaceAll(RegExp(r'[^A-Za-z]'), '').length < 6) return true;
  final digits = t.replaceAll(RegExp(r'[^0-9]'), '').length;
  return digits / t.replaceAll(' ', '').length > 0.6;
}

/// A name a person would recognise for [merchant] / [counterparty]: the first
/// one that is not a bank reference, else a plain label for the type
/// ("Bank transfer", "Payment", "Money received").
String displayName({required String type, String? merchant, String? counterparty}) {
  for (final candidate in [merchant, counterparty]) {
    final c = candidate?.trim();
    if (c != null && c.isNotEmpty && !looksLikeReference(c)) return c;
  }
  return switch (type) {
    'income' => 'activity2.label.moneyIn'.tr(),
    'transfer' => 'activity2.label.bankTransfer'.tr(),
    _ =>
      (looksLikeReference(merchant) || looksLikeReference(counterparty))
          ? 'activity2.label.bankPayment'.tr()
          : 'activity2.label.payment'.tr(),
  };
}

/// [displayName] for a transaction.
String displayMerchant(Txn t) => displayName(type: t.type, merchant: t.merchant, counterparty: t.counterparty);

/// The merchant when it is a real name (for "apply to all from …"), else null.
String? cleanMerchant(Txn t) {
  final m = t.merchant?.trim();
  return (m == null || m.isEmpty || looksLikeReference(m)) ? null : m;
}

/// What a [TransactionTile] shows for a full transaction.
TransactionTileData txnTileData(Txn t, {String? meta}) {
  String? clean(String? v) => (v == null || v.trim().isEmpty || looksLikeReference(v)) ? null : v.trim();
  final title = clean(t.merchant) ?? clean(t.counterparty) ?? t.categoryName ?? displayMerchant(t);
  return TransactionTileData(
    id: t.id,
    title: title,
    amount: t.amount,
    type: t.type,
    categoryName: t.categoryName,
    categoryIcon: t.categoryIcon,
    categoryColor: t.categoryColor,
    meta: meta ?? timeOfDay(t.occurredLocal),
    needsAttention: t.needsCategory,
    pending: t.pending,
    needsReview: t.needsReview,
    notSpending: t.notSpending,
  );
}
