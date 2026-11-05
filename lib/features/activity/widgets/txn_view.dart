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

/// What a [TransactionTile] shows for a full transaction.
TransactionTileData txnTileData(Txn t, {String? meta}) {
  final title = (t.merchant?.trim().isNotEmpty ?? false)
      ? t.merchant!.trim()
      : (t.counterparty?.trim().isNotEmpty ?? false)
      ? t.counterparty!.trim()
      : (t.categoryName ?? 'activity2.type.${t.type}'.tr());
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
