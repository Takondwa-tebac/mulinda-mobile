import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_exception.dart';
import '../data/admin_repository.dart';

class UserDetailScreen extends ConsumerStatefulWidget {
  const UserDetailScreen({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends ConsumerState<UserDetailScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_userDetailProvider(widget.userId)),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () =>
              ref.refresh(_userDetailProvider(widget.userId).future),
          child: Consumer(
            builder: (context, ref, _) {
              final async = ref.watch(_userDetailProvider(widget.userId));
              return async.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        e is ApiException ? e.displayMessage : e.toString(),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () =>
                            ref.invalidate(_userDetailProvider(widget.userId)),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
                data: (data) => _UserDetailContent(user: data),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _UserDetailContent extends ConsumerWidget {
  const _UserDetailContent({required this.user});

  final Map<String, dynamic> user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    // Extract subscription data
    final subscription = user['subscription'] as Map<String, dynamic>?;
    final isSubscribed = subscription != null && subscription['active'] == true;

    // Extract roles
    final roles =
        (user['roles'] as List?)
            ?.map(
              (r) => r is Map ? (r['name']?.toString() ?? '') : r.toString(),
            )
            .where((r) => r.isNotEmpty)
            .toList() ??
        <String>[];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Profile Header
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.onPrimaryContainer,
                  child: Text(
                    _initials(
                      user['full_name']?.toString() ??
                          user['username']?.toString() ??
                          '?',
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user['full_name']?.toString() ??
                            user['username']?.toString() ??
                            '',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user['email']?.toString() ?? '',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user['username']?.toString() ?? '',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Account Information
        _Section(
          title: 'Account Information',
          children: [
            _InfoRow('Joined', _formatDate(user['created_at'])),
            _InfoRow('Last Active', _formatDate(user['last_active_at'])),
            _InfoRow(
              'Phone',
              user['phone_number']?.toString() ?? 'Not provided',
            ),
            _InfoRow(
              'Income Bracket',
              user['declared_income_bracket']?.toString() ?? 'Not set',
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Subscription Status
        _Section(
          title: 'Subscription',
          children: [
            _InfoRow(
              'Status',
              isSubscribed ? 'Active' : 'Free Tier',
              status: isSubscribed ? 'active' : 'inactive',
            ),
            if (isSubscribed) ...[
              _InfoRow(
                'Plan',
                subscription['plan_label']?.toString() ?? 'Unknown',
              ),
              _InfoRow(
                'Source',
                subscription['source']?.toString() ?? 'Unknown',
              ),
              _InfoRow('Ends', _formatDate(subscription['ends_at'])),
              if (subscription['is_trial'] == true) _InfoRow('Type', 'Trial'),
            ],
            if (!isSubscribed) ...[
              _InfoRow('SMS Capture Used', '${user['sms_capture_count'] ?? 0}'),
            ],
          ],
        ),
        const SizedBox(height: 16),

        // Roles
        _Section(
          title: 'Roles',
          children: [
            if (roles.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No roles assigned'),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: roles
                    .map(
                      (role) => Chip(
                        label: Text(role),
                        backgroundColor: scheme.primaryContainer,
                        labelStyle: TextStyle(color: scheme.onPrimaryContainer),
                      ),
                    )
                    .toList(),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _editRoles(context, ref, roles),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit Roles'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(40),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Subscription Actions
        _Section(
          title: 'Subscription Actions',
          children: [
            OutlinedButton.icon(
              onPressed: () => _giftSubscription(context, ref),
              icon: const Icon(Icons.card_giftcard_outlined, size: 18),
              label: const Text('Gift Subscription'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(40),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Danger zone
        _Section(
          title: 'Danger Zone',
          children: [
            OutlinedButton.icon(
              onPressed: () => _deleteUser(context, ref),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Delete User'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(40),
                foregroundColor: scheme.error,
                side: BorderSide(color: scheme.error),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // SMS Capture Stats (for free tier)
        if (!isSubscribed)
          _Section(
            title: 'SMS Capture',
            children: [
              _InfoRow('Free Limit Used', '${user['sms_capture_count'] ?? 0}'),
              _InfoRow('Remaining', '${(10 - ((user['sms_capture_count'] as num?)?.toInt() ?? 0)).clamp(0, 10)}'),
            ],
          ),
      ],
    );
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'Not set';
    try {
      final dateTime = DateTime.parse(date.toString());
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    } catch (_) {
      return 'Invalid date';
    }
  }

  Future<void> _deleteUser(BuildContext context, WidgetRef ref) async {
    final name = (user['full_name'] ?? user['email'] ?? '').toString();
    final ok = await _showUserSheet<bool>(
      context,
      (sheetContext) => _ConfirmDeleteSheet(name: name),
    );
    if (ok != true || !context.mounted) return;

    try {
      await ref.read(adminRepositoryProvider).deleteUser(user['id'].toString());
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('admin.deleted'.tr())),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is ApiException ? e.displayMessage : 'admin.deleteFailed'.tr(),
            ),
          ),
        );
      }
    }
  }

  Future<void> _editRoles(BuildContext context, WidgetRef ref, List<String> currentRoles) async {
    final selected = await _showUserSheet<List<String>>(
      context,
      (sheetContext) => _RolesSheet(initialRoles: currentRoles),
    );
    if (selected == null || !context.mounted) return;

    try {
      await ref.read(adminRepositoryProvider).updateUserRoles(user['id'].toString(), selected);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('admin.rolesDone'.tr())),
        );
        ref.invalidate(_userDetailProvider(user['id'].toString()));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is ApiException ? e.displayMessage : 'admin.rolesFailed'.tr(),
            ),
          ),
        );
      }
    }
  }

  Future<void> _giftSubscription(BuildContext context, WidgetRef ref) async {
    final gift = await _showUserSheet<({String period, String? reason})>(
      context,
      (sheetContext) => const _GiftSheet(),
    );
    if (gift == null || !context.mounted) return;

    try {
      await ref.read(adminRepositoryProvider).grantCredit(
        userId: user['id'].toString(),
        period: gift.period,
        reason: gift.reason,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('admin.giftDone'.tr())),
        );
        ref.invalidate(_userDetailProvider(user['id'].toString()));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is ApiException ? e.displayMessage : 'admin.giftFailed'.tr(),
            ),
          ),
        );
      }
    }
  }
}

/// Modal bottom sheet that stays inside the safe area, scrolls when the form is
/// taller than the space left, and lifts above the keyboard.
Future<T?> _showUserSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          MediaQuery.of(sheetContext).viewInsets.bottom + 20,
        ),
        child: builder(sheetContext),
      ),
    ),
  );
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(text, style: Theme.of(context).textTheme.titleLarge),
      );
}

class _GiftSheet extends StatefulWidget {
  const _GiftSheet();

  @override
  State<_GiftSheet> createState() => _GiftSheetState();
}

class _GiftSheetState extends State<_GiftSheet> {
  static const _periods = ['day', 'three_day', 'week', 'month'];

  final _reason = TextEditingController();
  String _period = 'month';

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SheetTitle('admin.giftTitle'.tr()),
        Text('admin.giftPeriod'.tr(), style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in _periods)
              ChoiceChip(
                label: Text('admin.period.$p'.tr()),
                selected: _period == p,
                onSelected: (_) => setState(() => _period = p),
              ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _reason,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'admin.giftReason'.tr(),
            hintText: 'admin.giftReasonHint'.tr(),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () {
            final reason = _reason.text.trim();
            Navigator.pop(context, (period: _period, reason: reason.isEmpty ? null : reason));
          },
          icon: const Icon(Icons.card_giftcard_outlined, size: 18),
          label: Text('admin.giftAction'.tr()),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
      ],
    );
  }
}

class _RolesSheet extends StatefulWidget {
  const _RolesSheet({required this.initialRoles});
  final List<String> initialRoles;

  @override
  State<_RolesSheet> createState() => _RolesSheetState();
}

class _RolesSheetState extends State<_RolesSheet> {
  static const _allRoles = ['user', 'admin', 'super-admin'];

  late final Set<String> _selected = {...widget.initialRoles};

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SheetTitle('admin.rolesTitle'.tr()),
        for (final role in _allRoles)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(role),
            value: _selected.contains(role),
            onChanged: (checked) => setState(() {
              if (checked == true) {
                _selected.add(role);
              } else {
                _selected.remove(role);
              }
            }),
          ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected.toList()),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: Text('admin.rolesSave'.tr()),
        ),
      ],
    );
  }
}

class _ConfirmDeleteSheet extends StatelessWidget {
  const _ConfirmDeleteSheet({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SheetTitle('admin.deleteTitle'.tr()),
        Text('admin.deleteBody'.tr(args: [name])),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
            minimumSize: const Size.fromHeight(48),
          ),
          child: Text('admin.deleteAction'.tr()),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('form.cancel'.tr()),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value, {this.status = 'normal'});

  final String label;
  final String value;
  final String status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Color valueColor = scheme.onSurface;

    if (status == 'active') {
      valueColor = scheme.primary;
    } else if (status == 'inactive') {
      valueColor = scheme.onSurfaceVariant;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// Provider for user detail data
final _userDetailProvider = FutureProvider.family<Map<String, dynamic>, String>(
  (ref, userId) async {
    return ref.read(adminRepositoryProvider).getUserDetail(userId);
  },
);
