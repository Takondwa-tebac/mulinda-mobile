import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/skeleton.dart';
import '../data/admin_repository.dart';
import '../data/admin_user.dart';
import '../data/audit_models.dart';
import '../screens/audit_detail_screen.dart';
import '../screens/audit_trail_screen.dart';
import 'user_detail_sections.dart';

/// How many recent audits the Activity tab shows before "Open in audit trail".
const userActivityPreview = 5;

/// The latest audits made by one user (the audit trail's actor filter).
final userActivityProvider = FutureProvider.autoDispose.family<AuditPage, String>(
  (ref, userId) => ref.read(adminRepositoryProvider).audits(AuditQuery(actor: userId), perPage: userActivityPreview),
);

/// "Done by Chisomo": recent audits by this person, each opening its detail.
class UserActivitySection extends ConsumerWidget {
  const UserActivitySection({super.key, required this.user});

  final AdminUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(userActivityProvider(user.id));
    final name = user.shortName;
    return UserSectionCard(
      title: 'admin.user.doneBy'.tr(args: [name]),
      children: [
        UserCardPadding(
          child: Text('admin.user.doneByHint'.tr(), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Shimmer(
              child: Column(
                children: [
                  SkeletonBox(height: 40),
                  SizedBox(height: AppSpacing.md),
                  SkeletonBox(height: 40),
                  SizedBox(height: AppSpacing.md),
                  SkeletonBox(height: 40),
                ],
              ),
            ),
          ),
          error: (_, _) => UserCardPadding(
            child: ErrorRetry(
              compact: true,
              message: 'admin.user.activityError'.tr(),
              onRetry: () => ref.invalidate(userActivityProvider(user.id)),
            ),
          ),
          data: (page) => page.items.isEmpty
              ? EmptyState(
                  compact: true,
                  icon: Icons.history,
                  title: 'admin.user.activityEmpty'.tr(),
                  body: 'admin.user.activityEmptyBody'.tr(args: [name]),
                )
              : Column(
                  children: [
                    for (final item in page.items)
                      AuditTile(
                        item: item,
                        onTap: () => Navigator.of(
                          context,
                        ).push(MaterialPageRoute<void>(builder: (_) => AuditDetailScreen(id: item.id))),
                      ),
                  ],
                ),
        ),
        UserCardPadding(
          child: OutlinedButton.icon(
            key: const ValueKey('open-audit-trail'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AuditTrailScreen(initialQuery: AuditQuery(actor: user.id)),
              ),
            ),
            icon: const Icon(Icons.history, size: 18),
            label: Text('admin.user.openAudit'.tr()),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppSpacing.minTouch)),
          ),
        ),
      ],
    );
  }
}
