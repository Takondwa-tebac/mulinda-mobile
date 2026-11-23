import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/skeleton.dart';
import '../../auth/providers/auth_controller.dart';
import '../data/admin_repository.dart';
import '../data/admin_user.dart';
import '../widgets/user_access_section.dart';
import '../widgets/user_activity_section.dart';
import '../widgets/user_detail_header.dart';
import '../widgets/user_detail_sections.dart';
import '../widgets/user_detail_sheets.dart';
import 'push_notification_screen.dart';

/// One user as the admin user detail endpoint returns it.
final userDetailProvider = FutureProvider.autoDispose.family<AdminUser, String>(
  (ref, userId) async =>
      AdminUser.fromJson({'id': userId, ...await ref.read(adminRepositoryProvider).getUserDetail(userId)}),
);

/// Admin view of one user: header with status chips, quick actions, key
/// figures, and Overview / Plan / Access / Activity tabs.
class UserDetailScreen extends ConsumerStatefulWidget {
  const UserDetailScreen({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends ConsumerState<UserDetailScreen> {
  UserDetailTab _tab = UserDetailTab.overview;

  void _reload() => ref.invalidate(userDetailProvider(widget.userId));

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  String _errorText(Object e, String fallbackKey) => e is ApiException ? e.displayMessage : fallbackKey.tr();

  Future<void> _gift(AdminUser user) async {
    final gift = await showUserDetailSheet<GiftChoice>(context, const GiftSheet());
    if (gift == null || !mounted) return;
    try {
      await ref.read(adminRepositoryProvider).grantCredit(userId: user.id, period: gift.period, reason: gift.reason);
      if (!mounted) return;
      _snack('admin.giftDone'.tr());
      _reload();
    } catch (e) {
      if (mounted) _snack(_errorText(e, 'admin.giftFailed'));
    }
  }

  Future<void> _editRoles(AdminUser user) async {
    final selected = await showUserDetailSheet<List<String>>(context, RolesSheet(initialRoles: user.roles));
    if (selected == null || !mounted) return;
    try {
      await ref.read(adminRepositoryProvider).updateUserRoles(user.id, selected);
      if (!mounted) return;
      _snack('admin.rolesDone'.tr());
      _reload();
    } catch (e) {
      if (mounted) _snack(_errorText(e, 'admin.rolesFailed'));
    }
  }

  Future<void> _delete(AdminUser user) async {
    final ok = await showUserDetailSheet<bool>(context, ConfirmDeleteSheet(name: user.displayName));
    if (ok != true || !mounted) return;
    try {
      await ref.read(adminRepositoryProvider).deleteUser(user.id);
      if (!mounted) return;
      _snack('admin.deleted'.tr());
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) _snack(_errorText(e, 'admin.deleteFailed'));
    }
  }

  void _notify(AdminUser user) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PushNotificationScreen(initialRecipients: {user.id: user.displayName})),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(userDetailProvider(widget.userId));
    return Scaffold(
      appBar: AppBar(
        title: Text('admin.user.title'.tr()),
        actions: [
          IconButton(
            key: const ValueKey('user-refresh'),
            tooltip: 'admin.user.refresh'.tr(),
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(userDetailProvider(widget.userId).future),
          child: async.when(
            loading: () => const _UserDetailSkeleton(),
            error: (e, _) => ListView(
              children: [
                ScrollFill(
                  child: ErrorRetry(message: _errorText(e, 'admin.user.loadError'), onRetry: _reload),
                ),
              ],
            ),
            data: _content,
          ),
        ),
      ),
    );
  }

  Widget _content(AdminUser user) {
    final me = ref.watch(currentUserProvider);
    final isSuper = me?.isSuperAdmin == true;
    const gap = SizedBox(height: AppSpacing.md);
    return ListView(
      key: const ValueKey('user-detail-list'),
      padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm, AppSpacing.screen, AppSpacing.xxl),
      children: [
        UserHeaderCard(user: user, showScreenshots: isSuper),
        gap,
        UserQuickActions(
          onGift: () => _gift(user),
          onRoles: () => _editRoles(user),
          onNotify: () => _notify(user),
          onActivity: () => setState(() => _tab = UserDetailTab.activity),
        ),
        gap,
        UserStatTiles(user: user),
        gap,
        UserTabSwitcher(selected: _tab, onSelected: (tab) => setState(() => _tab = tab)),
        gap,
        switch (_tab) {
          UserDetailTab.overview => UserOverviewSection(
            user: user,
            showSecurity: isSuper,
            onOpenTab: (tab) => setState(() => _tab = tab),
          ),
          UserDetailTab.plan => UserPlanSection(user: user, onGift: () => _gift(user)),
          UserDetailTab.access => UserAccessSection(
            user: user,
            isMe: me?.id == user.id,
            showSecurity: isSuper,
            onEditRoles: () => _editRoles(user),
            onDelete: () => _delete(user),
            onScreenshotsChanged: _reload,
          ),
          UserDetailTab.activity => UserActivitySection(user: user),
        },
      ],
    );
  }
}

/// Placeholder in the shape of the page while the user loads.
class _UserDetailSkeleton extends StatelessWidget {
  const _UserDetailSkeleton();

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: AppSpacing.md);
    const row = SizedBox(width: AppSpacing.sm);
    return Shimmer(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm, AppSpacing.screen, AppSpacing.xxl),
        children: const [
          SkeletonBox(height: 150, radius: AppRadius.xl),
          gap,
          Row(
            children: [
              Expanded(child: SkeletonBox(height: 64, radius: AppRadius.lg)),
              row,
              Expanded(child: SkeletonBox(height: 64, radius: AppRadius.lg)),
              row,
              Expanded(child: SkeletonBox(height: 64, radius: AppRadius.lg)),
              row,
              Expanded(child: SkeletonBox(height: 64, radius: AppRadius.lg)),
            ],
          ),
          gap,
          Row(
            children: [
              Expanded(child: SkeletonBox(height: 96, radius: AppRadius.lg)),
              row,
              Expanded(child: SkeletonBox(height: 96, radius: AppRadius.lg)),
            ],
          ),
          gap,
          SkeletonBox(height: AppSpacing.minTouch, radius: AppRadius.pill),
          gap,
          SkeletonBox(height: 280, radius: AppRadius.lg),
        ],
      ),
    );
  }
}
