import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/notifications/notification_router.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/semantic_colors.dart';
import '../../activity/data/day_grouping.dart';
import '../../activity/widgets/txn_view.dart';
import '../data/insights_repository.dart';

/// The filter chips of the notification centre.
enum InsightFilter { all, unread, alerts, dueSoon, updates }

/// Which chip group a server `type` belongs to (InsightType values).
InsightFilter? groupOf(String type) => switch (type) {
  'budget_alert' || 'spending_spike' => InsightFilter.alerts,
  'bill_due' || 'loan_repayment_due' || 'investment_contribution_due' || 'investment_meeting' => InsightFilter.dueSoon,
  'savings_opportunity' || 'investment_payout' || 'summary' || 'announcement' => InsightFilter.updates,
  _ => null,
};

/// Whether [i] shows under [filter] (taking local reads into account via [isRead]).
bool matchesFilter(Insight i, InsightFilter filter, {required bool isRead}) => switch (filter) {
  InsightFilter.all => true,
  InsightFilter.unread => !isRead,
  _ => groupOf(i.type) == filter,
};

/// The icon and colour of a notification kind, from the theme's semantic tones.
(IconData, Color) toneOf(BuildContext context, String type) {
  final s = context.semantic;
  return switch (type) {
    'budget_alert' => (Icons.warning_amber_rounded, s.warning),
    'spending_spike' => (Icons.trending_up, s.danger),
    'bill_due' ||
    'loan_repayment_due' ||
    'investment_contribution_due' ||
    'investment_meeting' => (Icons.schedule, s.info),
    'savings_opportunity' || 'investment_payout' => (Icons.savings_outlined, s.success),
    'summary' => (Icons.analytics_outlined, s.brandInk),
    'announcement' => (Icons.campaign_outlined, s.special),
    _ => (Icons.notifications_none, Theme.of(context).colorScheme.onSurfaceVariant),
  };
}

/// A notification's action pill: its label and where it leads. The
/// destination comes from the shared [destinationFor] mapping (the same one
/// push taps use), so a pill and a push about the same thing open the same
/// screen.
class InsightAction {
  const InsightAction({required this.labelKey, required this.destination, required this.data});

  final String labelKey;
  final NotificationDestination destination;

  /// The notification data handed to [NotificationRouter.open].
  final Map<String, dynamic> data;

  String get route => destination.location;

  /// Push on top (true) or switch tab (false).
  bool get push => !destination.tab;
}

InsightAction actionFor(Insight i) {
  final data = i.routeData;
  return InsightAction(labelKey: actionLabelFor(i), destination: destinationFor(data), data: data);
}

/// The pill label: from the target when the server sends one, else the type.
String actionLabelFor(Insight i) {
  final single = i.targetId != null;
  final byTarget = switch (i.target) {
    'budget' => single ? 'budget' : 'budgets',
    'loan' => single ? 'loan' : 'loans',
    'goal' => single ? 'goal' : 'goals',
    'investment' => single ? 'investment' : 'investments',
    'bill' => single ? 'bill' : 'plan',
    'daily_summary' => 'summary',
    'transaction' => single ? 'transaction' : 'spending',
    'activity' => 'spending',
    'review' => 'review',
    'inbox_sms' || 'inbox_receipt' => 'inbox',
    'export' || 'audit_export' => 'export',
    'subscription' => 'subscription',
    'add_transaction' => 'add',
    _ => null,
  };
  final key =
      byTarget ??
      switch (i.type) {
        'budget_alert' => i.details['budget_id'] == null ? 'budgets' : 'budget',
        'bill_due' => 'plan',
        'loan_repayment_due' => 'loans',
        'investment_contribution_due' || 'investment_meeting' || 'investment_payout' => 'investments',
        'summary' || 'daily_summary' => 'summary',
        'spending_spike' => 'spending',
        'savings_opportunity' => 'goals',
        _ => 'open',
      };
  return 'notifications2.action.$key';
}

/// The day a notification belongs to, in local time.
DateTime? insightDay(Insight i) => DateTime.tryParse(i.createdAt ?? '')?.toLocal();

/// Header for a group: "Today", "Yesterday", "Earlier this week", or the month.
String insightGroupLabel(DateTime? day, DateTime now) {
  if (day == null) return 'activity2.noDate'.tr();
  switch (dayKind(day, now)) {
    case DayKind.today:
      return 'common.today'.tr();
    case DayKind.yesterday:
      return 'common.yesterday'.tr();
    default:
      break;
  }
  final startOfWeek = DateUtils.dateOnly(now).subtract(Duration(days: now.weekday - 1));
  if (!day.isBefore(startOfWeek)) return 'notifications2.earlierThisWeek'.tr();
  return '${'common.monthLong.${day.month}'.tr()} ${day.year}';
}

/// Groups newest-first notifications under [insightGroupLabel] headers.
List<(String, List<Insight>)> groupInsights(List<Insight> items, DateTime now) {
  final groups = <(String, List<Insight>)>[];
  for (final i in items) {
    final label = insightGroupLabel(insightDay(i), now);
    if (groups.isNotEmpty && groups.last.$1 == label) {
      groups.last.$2.add(i);
    } else {
      groups.add((label, [i]));
    }
  }
  return groups;
}

/// `14:05` today and yesterday, the weekday this week, otherwise `3 Nov`.
String insightTime(DateTime? at, DateTime now) {
  if (at == null) return '';
  final kind = dayKind(at, now);
  if (kind == DayKind.today || kind == DayKind.yesterday) return timeOfDay(at) ?? '';
  final startOfWeek = DateUtils.dateOnly(now).subtract(Duration(days: now.weekday - 1));
  if (!at.isBefore(startOfWeek)) return 'common.weekdayShort.${at.weekday}'.tr();
  return '${at.day} ${'common.monthShort.${at.month}'.tr()}';
}

/// One notification. Unread: white with an outline, a dot and a bold title.
/// Read: flat and quiet. Tapping opens the detail; the pill only navigates.
class NotificationCard extends StatelessWidget {
  const NotificationCard({
    super.key,
    required this.insight,
    required this.isRead,
    required this.now,
    required this.onOpen,
    required this.onAction,
  });

  final Insight insight;
  final bool isRead;
  final DateTime now;
  final VoidCallback onOpen;
  final void Function(InsightAction action) onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, tone) = toneOf(context, insight.type);
    final action = actionFor(insight);
    final hasImage = insight.type == 'announcement' && (insight.imageUrl?.isNotEmpty ?? false);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Material(
        key: ValueKey('insight-${insight.id}'),
        color: isRead ? scheme.surfaceContainerLow : scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
          side: isRead ? BorderSide.none : BorderSide(color: scheme.primaryContainer, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(color: tone.withValues(alpha: 0.14), shape: BoxShape.circle),
                          child: Icon(icon, color: tone, size: 20),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  insight.title,
                                  key: ValueKey('insight-title-${insight.id}'),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontWeight: isRead ? FontWeight.w400 : FontWeight.w700),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  insight.body,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (hasImage) ...[
                      const SizedBox(height: AppSpacing.md),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        child: CachedNetworkImage(
                          imageUrl: insight.imageUrl!,
                          height: 140,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => Container(height: 140, color: scheme.surfaceContainerHigh),
                          errorWidget: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        const SizedBox(width: 52),
                        ActionChip(
                          key: ValueKey('insight-action-${insight.id}'),
                          label: Text(action.labelKey.tr()),
                          avatar: Icon(Icons.arrow_forward, size: 16, color: tone),
                          onPressed: () => onAction(action),
                        ),
                        const Spacer(),
                        Text(
                          insightTime(insightDay(insight), now),
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ),
                if (!isRead)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      key: ValueKey('insight-unread-${insight.id}'),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
