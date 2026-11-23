import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/semantic_colors.dart';
import '../../../core/widgets/app_sheet.dart';
import 'user_detail_format.dart';

/// The choice made in [GiftSheet].
typedef GiftChoice = ({String period, String? reason});

/// Opens one of the user detail sheets.
Future<T?> showUserDetailSheet<T>(BuildContext context, Widget sheet) =>
    showAppSheetWith<T>(context, builder: (_) => sheet);

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Text(text, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
  );
}

/// Confirm and cancel, pinned under the sheet body.
class _Footer extends StatelessWidget {
  const _Footer({required this.label, required this.onConfirm, this.danger = false, this.icon});

  final String label;
  final VoidCallback onConfirm;
  final bool danger;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final s = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final style = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(AppSpacing.minTouch),
      backgroundColor: danger ? s.danger : null,
      foregroundColor: danger ? scheme.surface : null,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (icon == null)
          FilledButton(onPressed: onConfirm, style: style, child: Text(label))
        else
          FilledButton.icon(onPressed: onConfirm, style: style, icon: Icon(icon, size: 18), label: Text(label)),
        const SizedBox(height: AppSpacing.xs),
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(minimumSize: const Size.fromHeight(AppSpacing.minTouch)),
          child: Text('form.cancel'.tr()),
        ),
      ],
    );
  }
}

/// Gift a subscription period, with an optional reason.
class GiftSheet extends StatefulWidget {
  const GiftSheet({super.key});

  @override
  State<GiftSheet> createState() => _GiftSheetState();
}

class _GiftSheetState extends State<GiftSheet> {
  static const _periods = ['day', 'three_day', 'week', 'month'];

  final _reason = TextEditingController();
  String _period = 'month';

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _confirm() {
    final reason = _reason.text.trim();
    Navigator.pop<GiftChoice>(context, (period: _period, reason: reason.isEmpty ? null : reason));
  }

  @override
  Widget build(BuildContext context) {
    return AppSheet(
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Title('admin.giftTitle'.tr()),
          Text('admin.giftPeriod'.tr(), style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final p in _periods)
                ChoiceChip(
                  label: Text('admin.period.$p'.tr()),
                  selected: _period == p,
                  onSelected: (_) => setState(() => _period = p),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _reason,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'admin.giftReason'.tr(),
              hintText: 'admin.giftReasonHint'.tr(),
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      footer: _Footer(label: 'admin.giftAction'.tr(), icon: Icons.card_giftcard_outlined, onConfirm: _confirm),
    );
  }
}

/// Pick roles. Warns before someone is made a super-admin.
class RolesSheet extends StatefulWidget {
  const RolesSheet({super.key, required this.initialRoles});
  final List<String> initialRoles;

  @override
  State<RolesSheet> createState() => _RolesSheetState();
}

class _RolesSheetState extends State<RolesSheet> {
  static const _allRoles = ['user', 'admin', 'super-admin'];
  static const _help = {
    'user': 'admin.user.roleHelp.user',
    'admin': 'admin.user.roleHelp.admin',
    'super-admin': 'admin.user.roleHelp.superAdmin',
  };

  late final Set<String> _selected = {...widget.initialRoles};

  @override
  Widget build(BuildContext context) {
    final s = context.semantic;
    final addsSuper = _selected.contains('super-admin') && !widget.initialRoles.contains('super-admin');
    return AppSheet(
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Title('admin.rolesTitle'.tr()),
          for (final role in _allRoles)
            CheckboxListTile(
              key: ValueKey('role-$role'),
              contentPadding: EdgeInsets.zero,
              title: Text(adminRoleLabel(role)),
              subtitle: Text(_help[role]!.tr()),
              value: _selected.contains(role),
              onChanged: (checked) => setState(() {
                if (checked == true) {
                  _selected.add(role);
                } else {
                  _selected.remove(role);
                }
              }),
            ),
          if (addsSuper) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              key: const ValueKey('super-admin-warning'),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(color: s.warningContainer, borderRadius: AppRadius.card),
              child: Text('admin.user.superWarn'.tr(), style: TextStyle(color: s.warning, height: 1.4)),
            ),
          ],
        ],
      ),
      footer: _Footer(label: 'admin.rolesSave'.tr(), onConfirm: () => Navigator.pop(context, _selected.toList())),
    );
  }
}

/// "Delete user?" with the person's name.
class ConfirmDeleteSheet extends StatelessWidget {
  const ConfirmDeleteSheet({super.key, required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return AppSheet(
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Title('admin.deleteTitle'.tr()),
          Text('admin.deleteBody'.tr(args: [name])),
        ],
      ),
      footer: _Footer(label: 'admin.deleteAction'.tr(), danger: true, onConfirm: () => Navigator.pop(context, true)),
    );
  }
}

/// Confirms allowing or blocking screenshots for [name].
class ScreenshotsSheet extends StatelessWidget {
  const ScreenshotsSheet({super.key, required this.name, required this.allow});

  final String name;
  final bool allow;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return AppSheet(
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Title((allow ? 'admin.screenshotsAllowTitle' : 'admin.screenshotsBlockTitle').tr(args: [name])),
          Text(
            (allow ? 'admin.screenshotsAllowBody' : 'admin.screenshotsBlockBody').tr(args: [name]),
            style: textTheme.bodyMedium?.copyWith(color: muted, height: 1.45),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('admin.screenshotsNote'.tr(), style: textTheme.bodySmall?.copyWith(color: muted)),
        ],
      ),
      footer: _Footer(
        label: (allow ? 'admin.screenshotsAllow' : 'admin.screenshotsBlock').tr(),
        onConfirm: () => Navigator.pop(context, true),
      ),
    );
  }
}
