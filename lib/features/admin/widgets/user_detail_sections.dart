import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/semantic_colors.dart';
import '../../../core/widgets/info_row.dart';
import '../../../core/widgets/status_chip.dart';
import '../data/admin_user.dart';
import 'user_detail_format.dart';

enum UserDetailTab { overview, plan, access, activity }

/// Overview, Plan, Access, Activity as a segmented row.
class UserTabSwitcher extends StatelessWidget {
  const UserTabSwitcher({super.key, required this.selected, required this.onSelected});

  final UserDetailTab selected;
  final ValueChanged<UserDetailTab> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: AppRadius.chip),
      child: Row(
        children: [
          for (final tab in UserDetailTab.values)
            Expanded(
              child: Semantics(
                selected: tab == selected,
                button: true,
                child: Material(
                  color: tab == selected ? scheme.primary : Colors.transparent,
                  borderRadius: AppRadius.chip,
                  child: InkWell(
                    key: ValueKey('user-tab-${tab.name}'),
                    borderRadius: AppRadius.chip,
                    onTap: () => onSelected(tab),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: AppSpacing.minTouch - AppSpacing.sm),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'admin.user.tab.${tab.name}'.tr(),
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: tab == selected ? scheme.onPrimary : scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A titled card for one group of rows.
class UserSectionCard extends StatelessWidget {
  const UserSectionCard({super.key, required this.title, required this.children, this.titleColor, this.outlined});

  final String title;
  final List<Widget> children;
  final Color? titleColor;

  /// Draws an outline in this colour instead of a filled card (Danger zone).
  final Color? outlined;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // A Material surface (not a coloured box) so list tiles inside show
    // their ink.
    return Material(
      color: outlined == null ? scheme.surfaceContainerLow : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: outlined == null ? BorderSide.none : BorderSide(color: outlined!),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, AppSpacing.lg, 0, AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: titleColor ?? context.semantic.brandInk,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Padding for buttons and notes inside a [UserSectionCard].
class UserCardPadding extends StatelessWidget {
  const UserCardPadding({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, AppSpacing.sm),
    child: child,
  );
}

/// A label and value with a copy button.
class _CopyRow extends StatelessWidget {
  const _CopyRow({required this.label, required this.value, required this.tooltip, super.key});

  final String label;
  final String value;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.only(left: AppSpacing.lg, right: AppSpacing.xs),
      title: Text(label, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.45),
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            tooltip: tooltip,
            icon: const Icon(Icons.copy_outlined, size: 18),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: value));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text('admin.user.copied'.tr())));
            },
          ),
        ],
      ),
    );
  }
}

/// A one-line summary with a button that opens another tab.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.title, required this.subtitle, required this.action, required this.onTap});

  final String title;
  final String subtitle;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.card),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle, style: TextStyle(color: scheme.onSurfaceVariant)),
        trailing: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(minimumSize: const Size(AppSpacing.minTouch, AppSpacing.minTouch)),
          child: Text(action),
        ),
      ),
    );
  }
}

/// Account details, plus short plan and security summaries.
class UserOverviewSection extends StatelessWidget {
  const UserOverviewSection({super.key, required this.user, required this.showSecurity, required this.onOpenTab});

  final AdminUser user;
  final bool showSecurity;
  final ValueChanged<UserDetailTab> onOpenTab;

  @override
  Widget build(BuildContext context) {
    final sub = user.subscription;
    final notSet = 'admin.user.notSet'.tr();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UserSectionCard(
          title: 'admin.user.account'.tr(),
          children: [
            if (user.phone != null)
              _CopyRow(
                key: const ValueKey('copy-phone'),
                label: 'admin.user.phone'.tr(),
                value: user.phone!,
                tooltip: 'admin.user.copyPhone'.tr(),
              )
            else
              InfoRow(label: 'admin.user.phone'.tr(), value: notSet),
            if (user.email != null)
              _CopyRow(
                key: const ValueKey('copy-email'),
                label: 'admin.user.email'.tr(),
                value: user.email!,
                tooltip: 'admin.user.copyEmail'.tr(),
              )
            else
              InfoRow(label: 'admin.user.email'.tr(), value: notSet),
            InfoRow(label: 'admin.user.username'.tr(), value: user.username ?? notSet),
            InfoRow(label: 'admin.user.income'.tr(), value: adminIncomeLabel(user.incomeBracket)),
            InfoRow(label: 'admin.user.joined'.tr(), value: adminDate(user.createdAt)),
            InfoRow(label: 'admin.user.lastActive'.tr(), value: adminDateTime(user.lastActiveAt)),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _SummaryCard(
          title: adminPlanLine(user),
          subtitle: sub == null
              ? 'admin.user.freeCapturesLine'.tr(args: ['${user.smsCaptureCount}'])
              : 'admin.user.endsOn'.tr(args: [adminDate(sub.endsAt)]),
          action: 'admin.user.details'.tr(),
          onTap: () => onOpenTab(UserDetailTab.plan),
        ),
        if (showSecurity) ...[
          const SizedBox(height: AppSpacing.md),
          _SummaryCard(
            title: (user.screenshotsAllowed ? 'admin.user.shotsAllowedLine' : 'admin.user.shotsBlockedLine').tr(),
            subtitle: 'admin.user.securityHint'.tr(),
            action: 'admin.user.manage'.tr(),
            onTap: () => onOpenTab(UserDetailTab.access),
          ),
        ],
      ],
    );
  }
}

/// The plan active now (or free) and the gift action.
class UserPlanSection extends StatelessWidget {
  const UserPlanSection({super.key, required this.user, required this.onGift});

  final AdminUser user;
  final VoidCallback onGift;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sub = user.subscription;
    final (statusKey, tone) = sub == null
        ? ('free', StatusTone.neutral)
        : (sub.isTrial ? ('trial', StatusTone.warning) : ('active', StatusTone.brand));
    return UserSectionCard(
      title: 'admin.user.subscription'.tr(),
      children: [
        ListTile(
          title: Text('admin.user.status.label'.tr(), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
          trailing: StatusChip(label: 'admin.user.status.$statusKey'.tr(), tone: tone),
        ),
        if (sub != null) ...[
          InfoRow(label: 'admin.user.plan'.tr(), value: sub.planLabel ?? 'admin.user.notSet'.tr()),
          InfoRow(label: 'admin.user.source.label'.tr(), value: adminSourceLabel(sub.source)),
          InfoRow(
            label: 'admin.user.ends'.tr(),
            value: [adminDate(sub.endsAt), adminLeft(sub.endsAt)].where((e) => e.isNotEmpty).join(' · '),
          ),
        ] else
          InfoRow(label: 'admin.user.freeCapturesMonth'.tr(), value: '${user.smsCaptureCount}'),
        UserCardPadding(
          child: FilledButton.icon(
            key: const ValueKey('plan-gift'),
            onPressed: onGift,
            style: FilledButton.styleFrom(
              backgroundColor: scheme.secondary,
              foregroundColor: scheme.onSecondary,
              minimumSize: const Size.fromHeight(AppSpacing.minTouch),
            ),
            icon: const Icon(Icons.card_giftcard_outlined, size: 18),
            label: Text('admin.giftTitle'.tr()),
          ),
        ),
      ],
    );
  }
}
