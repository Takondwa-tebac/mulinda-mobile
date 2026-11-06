import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/semantic_colors.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/skeleton.dart';
import '../data/admin_repository.dart';
import '../data/audit_models.dart';
import 'audit_trail_screen.dart';

final auditDetailProvider = FutureProvider.autoDispose.family<AuditDetail, String>(
  (ref, id) => ref.read(adminRepositoryProvider).audit(id),
);

/// One audit, in sections: who, what, the field-by-field changes, the device
/// and network, the request and its metadata. Ids can be copied.
class AuditDetailScreen extends ConsumerWidget {
  const AuditDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(auditDetailProvider(id));
    return Scaffold(
      appBar: AppBar(title: Text('admin2.audit.detailTitle'.tr())),
      body: async.when(
        loading: () => const SkeletonList(count: 6),
        error: (_, _) => Center(
          child: ErrorRetry(
            message: 'admin2.audit.loadError'.tr(),
            onRetry: () => ref.invalidate(auditDetailProvider(id)),
          ),
        ),
        data: (d) => ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xxl),
          children: [
            _Headline(detail: d),
            _Section(
              title: 'admin2.audit.section.actor'.tr(),
              icon: Icons.person_outline,
              rows: d.actor == null
                  ? [('admin2.audit.who'.tr(), 'admin2.audit.system'.tr(), false)]
                  : [
                      ('admin2.audit.name'.tr(), d.actor!.name, false),
                      ('admin2.audit.email'.tr(), d.actor!.email, true),
                      ('admin2.audit.role'.tr(), d.actor!.role, false),
                      ('admin2.audit.userId'.tr(), d.actor!.id, true),
                    ],
            ),
            _Section(
              title: 'admin2.audit.section.action'.tr(),
              icon: auditIcon(d.icon),
              rows: [
                ('admin2.audit.eventLabel'.tr(), auditEventLabel(d.event), false),
                ('admin2.audit.what'.tr(), d.action['label']?.toString(), false),
                ('admin2.audit.record'.tr(), d.action['subject_type']?.toString(), false),
                ('admin2.audit.recordName'.tr(), d.action['subject_label']?.toString(), false),
                ('admin2.audit.recordId'.tr(), d.action['subject_id']?.toString(), true),
              ],
            ),
            if (d.changes.isNotEmpty) _ChangesCard(changes: d.changes),
            _Section(
              title: 'admin2.audit.section.device'.tr(),
              icon: Icons.phone_android,
              rows: [
                ('admin2.audit.platform'.tr(), d.device['platform']?.toString(), false),
                ('admin2.audit.appVersion'.tr(), d.device['app_version']?.toString(), false),
                ('admin2.audit.osVersion'.tr(), d.device['os_version']?.toString(), false),
                ('admin2.audit.userAgent'.tr(), d.device['user_agent']?.toString(), false),
                ('admin2.audit.ip'.tr(), d.network['ip_address']?.toString(), true),
              ],
            ),
            _Section(
              title: 'admin2.audit.section.request'.tr(),
              icon: Icons.http,
              rows: [
                ('admin2.audit.method'.tr(), d.request['method']?.toString(), false),
                ('admin2.audit.url'.tr(), d.request['url']?.toString(), true),
                ('admin2.audit.requestId'.tr(), d.request['request_id']?.toString(), true),
              ],
            ),
            _Section(
              title: 'admin2.audit.section.meta'.tr(),
              icon: Icons.label_outline,
              rows: [
                ('admin2.audit.auditId'.tr(), d.id, true),
                (
                  'admin2.audit.tags'.tr(),
                  (d.meta['tags'] is List && (d.meta['tags'] as List).isNotEmpty)
                      ? (d.meta['tags'] as List).join(', ')
                      : null,
                  false,
                ),
                ('admin2.audit.type'.tr(), d.meta['auditable_type']?.toString(), false),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.detail});

  final AuditDetail detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: scheme.primaryContainer,
            child: Icon(auditIcon(detail.icon), color: scheme.onPrimaryContainer),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.action['label']?.toString() ?? auditEventLabel(detail.event),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(auditTime(detail.createdAt), style: TextStyle(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A titled card of label/value rows; empty values are left out and ids can be copied.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.icon, required this.rows});

  final String title;
  final IconData icon;

  /// (label, value, copyable)
  final List<(String, String?, bool)> rows;

  @override
  Widget build(BuildContext context) {
    final visible = rows.where((r) => r.$2 != null && r.$2!.isNotEmpty).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.sm, AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: context.semantic.brandInk),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.w700, color: context.semantic.brandInk),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final (label, value, copy) in visible)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(label, style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
                    ),
                    Expanded(child: SelectableText(value!, style: const TextStyle(fontSize: 13))),
                    if (copy)
                      IconButton(
                        tooltip: 'admin2.audit.copy'.tr(),
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.copy, size: 16),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: value));
                          ScaffoldMessenger.of(context)
                            ..hideCurrentSnackBar()
                            ..showSnackBar(SnackBar(content: Text('admin2.audit.copied'.tr())));
                        },
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Field-by-field changes: old value struck through, new value in bold.
class _ChangesCard extends StatelessWidget {
  const _ChangesCard({required this.changes});

  final List<AuditChange> changes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = context.semantic;
    final empty = '—';
    return Card(
      key: const ValueKey('audit-changes'),
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.compare_arrows, size: 18, color: s.brandInk),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'admin2.audit.section.changes'.tr(),
                  style: TextStyle(fontWeight: FontWeight.w700, color: s.brandInk),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Table(
              columnWidths: const {0: FlexColumnWidth(1.1), 1: FlexColumnWidth(1.4), 2: FlexColumnWidth(1.4)},
              defaultVerticalAlignment: TableCellVerticalAlignment.top,
              children: [
                TableRow(
                  children: [
                    for (final h in ['admin2.audit.field', 'admin2.audit.old', 'admin2.audit.new'])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          h.tr(),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
                for (final c in changes)
                  TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(c.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                        child: Text(
                          c.oldValue ?? empty,
                          style: TextStyle(
                            fontSize: 13,
                            color: s.danger,
                            decoration: c.oldValue == null ? null : TextDecoration.lineThrough,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          c.newValue ?? empty,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: s.success),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
