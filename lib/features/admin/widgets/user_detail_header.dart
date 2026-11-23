import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/stat_card.dart';
import '../../../core/widgets/status_chip.dart';
import '../data/admin_user.dart';
import 'user_detail_format.dart';

/// Initials or photo, name, username, phone and status chips.
class UserHeaderCard extends StatelessWidget {
  const UserHeaderCard({super.key, required this.user, required this.showScreenshots});

  final AdminUser user;

  /// Whether to show the "Screenshots allowed" chip (super-admins only).
  final bool showScreenshots;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sub = user.subscription;
    final muted = scheme.onPrimaryContainer.withValues(alpha: 0.85);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(AppRadius.xl)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
                foregroundImage: user.avatarUrl == null ? null : NetworkImage(user.avatarUrl!),
                onForegroundImageError: user.avatarUrl == null ? null : (_, _) {},
                child: Text(user.initials, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: scheme.onPrimaryContainer),
                    ),
                    if (user.username != null) Text('@${user.username}', style: TextStyle(fontSize: 13, color: muted)),
                    if (user.phone != null) Text(user.phone!, style: TextStyle(fontSize: 13, color: muted)),
                    if (user.createdAt != null)
                      Text(
                        'admin.user.joinedOn'.tr(args: [adminDate(user.createdAt)]),
                        style: TextStyle(fontSize: 13, color: muted),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xs + AppSpacing.xxs,
            runSpacing: AppSpacing.xs + AppSpacing.xxs,
            children: [
              StatusChip(
                key: const ValueKey('user-plan-chip'),
                label: adminPlanLine(user),
                // Not the brand tone: it matches the header and would vanish.
                tone: sub == null ? StatusTone.neutral : (sub.isTrial ? StatusTone.warning : StatusTone.success),
              ),
              for (final role in user.roles.where((r) => r != 'user'))
                StatusChip(label: adminRoleLabel(role), icon: Icons.verified_user_outlined),
              if (showScreenshots && user.screenshotsAllowed)
                StatusChip(
                  label: 'admin.user.screenshotsChip'.tr(),
                  tone: StatusTone.warning,
                  icon: Icons.screenshot_outlined,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One quick action: icon over a short label, at least 64 px tall.
class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.onTap, super.key});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: AppRadius.card,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.card,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.sm),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 22, color: scheme.primary),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    label,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Gift plan, Roles, Notify, Activity.
class UserQuickActions extends StatelessWidget {
  const UserQuickActions({
    super.key,
    required this.onGift,
    required this.onRoles,
    required this.onNotify,
    required this.onActivity,
  });

  final VoidCallback onGift;
  final VoidCallback onRoles;
  final VoidCallback onNotify;
  final VoidCallback onActivity;

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(width: AppSpacing.sm);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _QuickAction(
          key: const ValueKey('qa-gift'),
          icon: Icons.card_giftcard_outlined,
          label: 'admin.user.qa.gift'.tr(),
          onTap: onGift,
        ),
        gap,
        _QuickAction(
          key: const ValueKey('qa-roles'),
          icon: Icons.admin_panel_settings_outlined,
          label: 'admin.user.qa.roles'.tr(),
          onTap: onRoles,
        ),
        gap,
        _QuickAction(
          key: const ValueKey('qa-notify'),
          icon: Icons.notifications_outlined,
          label: 'admin.user.qa.notify'.tr(),
          onTap: onNotify,
        ),
        gap,
        _QuickAction(
          key: const ValueKey('qa-activity'),
          icon: Icons.history,
          label: 'admin.user.qa.activity'.tr(),
          onTap: onActivity,
        ),
      ],
    );
  }
}

/// Last active, and Plan ends (or free captures this month for free users).
class UserStatTiles extends StatelessWidget {
  const UserStatTiles({super.key, required this.user});

  final AdminUser user;

  @override
  Widget build(BuildContext context) {
    final sub = user.subscription;
    final second = sub == null
        ? StatCard(
            icon: Icons.sms_outlined,
            label: 'admin.user.freeCaptures'.tr(),
            value: '${user.smsCaptureCount}',
            caption: 'admin.user.thisMonth'.tr(),
          )
        : StatCard(
            icon: Icons.event_outlined,
            label: (sub.isTrial ? 'admin.user.trialEnds' : 'admin.user.planEnds').tr(),
            value: adminDate(sub.endsAt),
            caption: adminLeft(sub.endsAt),
          );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: StatCard(
            icon: Icons.schedule,
            label: 'admin.user.lastActive'.tr(),
            value: adminAgo(user.lastActiveAt),
            caption: user.lastActiveAt == null ? null : adminDate(user.lastActiveAt),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: second),
      ],
    );
  }
}
