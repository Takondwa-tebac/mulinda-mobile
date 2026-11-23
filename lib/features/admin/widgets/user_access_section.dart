import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/semantic_colors.dart';
import '../../../core/widgets/status_chip.dart';
import '../../auth/providers/auth_controller.dart';
import '../data/admin_repository.dart';
import '../data/admin_user.dart';
import 'user_detail_format.dart';
import 'user_detail_sections.dart';
import 'user_detail_sheets.dart';

/// Roles, App security (super-admins only) and the Danger zone.
class UserAccessSection extends StatelessWidget {
  const UserAccessSection({
    super.key,
    required this.user,
    required this.isMe,
    required this.showSecurity,
    required this.onEditRoles,
    required this.onDelete,
    required this.onScreenshotsChanged,
  });

  final AdminUser user;

  /// The signed-in admin is looking at their own account.
  final bool isMe;
  final bool showSecurity;
  final VoidCallback onEditRoles;
  final VoidCallback onDelete;
  final VoidCallback onScreenshotsChanged;

  @override
  Widget build(BuildContext context) {
    final s = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    // The API refuses both; say why instead of letting it fail.
    final blockedReason = user.isSuperAdmin
        ? 'admin.user.deleteSuper'.tr()
        : (isMe ? 'admin.user.deleteSelf'.tr() : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UserSectionCard(
          title: 'admin.user.roles'.tr(),
          children: [
            UserCardPadding(
              child: user.roles.isEmpty
                  ? Text('admin.user.noRoles'.tr(), style: TextStyle(color: scheme.onSurfaceVariant))
                  : Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final role in user.roles) StatusChip(label: adminRoleLabel(role), tone: StatusTone.brand),
                      ],
                    ),
            ),
            UserCardPadding(
              child: OutlinedButton.icon(
                key: const ValueKey('edit-roles'),
                onPressed: onEditRoles,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text('admin.rolesTitle'.tr()),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppSpacing.minTouch)),
              ),
            ),
          ],
        ),
        if (showSecurity) ...[
          const SizedBox(height: AppSpacing.md),
          ScreenshotsSection(user: user, onChanged: onScreenshotsChanged),
        ],
        const SizedBox(height: AppSpacing.md),
        UserSectionCard(
          title: 'admin.user.dangerZone'.tr(),
          titleColor: s.danger,
          outlined: s.danger.withValues(alpha: 0.4),
          children: [
            UserCardPadding(
              child: Text(
                blockedReason ?? 'admin.user.deleteHint'.tr(),
                key: const ValueKey('delete-hint'),
                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
              ),
            ),
            UserCardPadding(
              child: OutlinedButton.icon(
                key: const ValueKey('delete-user'),
                onPressed: blockedReason == null ? onDelete : null,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: Text('admin.deleteAction'.tr()),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(AppSpacing.minTouch),
                  foregroundColor: s.danger,
                  side: BorderSide(color: blockedReason == null ? s.danger : scheme.outlineVariant),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// App security: allow or block screenshots and screen recording for this
/// user, after a confirmation. Saved on the server and audited; the user's
/// app applies it when it next loads their profile.
class ScreenshotsSection extends ConsumerStatefulWidget {
  const ScreenshotsSection({super.key, required this.user, required this.onChanged});

  final AdminUser user;
  final VoidCallback onChanged;

  @override
  ConsumerState<ScreenshotsSection> createState() => _ScreenshotsSectionState();
}

class _ScreenshotsSectionState extends ConsumerState<ScreenshotsSection> {
  bool _saving = false;

  Future<void> _change(bool allow) async {
    final name = widget.user.shortName;
    final confirmed = await showUserDetailSheet<bool>(context, ScreenshotsSheet(name: name, allow: allow));
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await ref.read(adminRepositoryProvider).setScreenshotsAllowed(widget.user.id, allowed: allow);
      // Changing your own: apply it on this phone now.
      if (ref.read(currentUserProvider)?.id == widget.user.id) {
        await ref.read(authControllerProvider.notifier).refresh();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((allow ? 'admin.screenshotsAllowed' : 'admin.screenshotsBlocked').tr(args: [name]))),
      );
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e is ApiException ? e.displayMessage : 'admin.screenshotsFailed'.tr())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allowed = widget.user.screenshotsAllowed;
    final name = widget.user.shortName;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return UserSectionCard(
      title: 'admin.screenshotsSection'.tr(),
      children: [
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          secondary: const Icon(Icons.screenshot_monitor_outlined),
          title: Text('admin.screenshotsTitle'.tr()),
          subtitle: Text((allowed ? 'admin.screenshotsOn' : 'admin.screenshotsOff').tr(args: [name])),
          value: allowed,
          onChanged: _saving ? null : _change,
        ),
        if (_saving)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: LinearProgressIndicator(),
          ),
        UserCardPadding(
          child: Text('admin.screenshotsNote'.tr(), style: TextStyle(fontSize: 12, color: muted)),
        ),
      ],
    );
  }
}
