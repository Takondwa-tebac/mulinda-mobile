import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../auth/providers/auth_controller.dart';
import '../data/subscription_models.dart';

/// Free SMS captures left, from the server's numbers, never below zero.
int smsCapturesRemaining(SmsCaptureInfo? info) {
  if (info == null) return 0;
  final limit = info.limit < 0 ? 0 : info.limit;
  final byCount = limit - info.used;
  final remaining = info.remaining < byCount ? info.remaining : byCount;
  return remaining.clamp(0, limit);
}

/// The subtitle line of [SubscriptionStatusTile] for [sub] at [now].
String subscriptionStatusLine(SubscriptionInfo sub, DateTime now) {
  final ends = sub.endsAt;
  if (sub.active && ends != null && ends.isAfter(now)) {
    final local = ends.toLocal();
    final date = '${local.day}/${local.month}/${local.year}';
    if (sub.isTrial) {
      final hours = ends.difference(now).inMinutes <= 60
          ? 1
          : (ends.difference(now).inMinutes / 60).ceil();
      return 'subscription.tile.trialEnds'.tr(namedArgs: {'hours': '$hours'});
    }
    return 'subscription.tile.activeUntil'.tr(
      namedArgs: {'plan': sub.planLabel ?? '', 'date': date},
    );
  }
  final sms = sub.smsCapture;
  if (sms != null && sms.isLimited) {
    return 'subscription.tile.freeSms'.tr(
      namedArgs: {
        'remaining': '${smsCapturesRemaining(sms)}',
        'limit': '${sms.limit < 0 ? 0 : sms.limit}',
      },
    );
  }
  return 'subscription.tile.free'.tr();
}

/// Profile row: the current plan (free / trial / pass and its end) and, for
/// free users, the free SMS captures left. Opens the Subscription screen.
class SubscriptionStatusTile extends ConsumerWidget {
  const SubscriptionStatusTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final sub =
        ref.watch(currentUserProvider)?.subscription ??
        const SubscriptionInfo.none();
    final title = !sub.active
        ? 'subscription.free'.tr()
        : sub.isTrial
        ? 'subscription.trialActive'.tr()
        : (sub.planLabel ?? 'subscription.active'.tr());

    return ListTile(
      key: const ValueKey('subscription-status-tile'),
      leading: Icon(
        sub.active ? Icons.workspace_premium : Icons.workspace_premium_outlined,
        color: sub.active ? scheme.primary : scheme.onSurfaceVariant,
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subscriptionStatusLine(sub, DateTime.now())),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(Routes.subscription),
    );
  }
}
