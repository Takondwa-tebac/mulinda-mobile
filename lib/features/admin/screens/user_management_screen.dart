import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../data/admin_repository.dart';

final _usersProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, search) {
  return ref.read(adminRepositoryProvider).listUsers(search: search);
});

class UserManagementScreen extends ConsumerStatefulWidget {
  const UserManagementScreen({super.key});

  @override
  ConsumerState<UserManagementScreen> createState() =>
      _UserManagementScreenState();
}

class _UserManagementScreenState extends ConsumerState<UserManagementScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_usersProvider(_query));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Users'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Search by name, email or username…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30)),
                filled: true,
              ),
              onSubmitted: (v) => setState(() => _query = v.trim()),
              textInputAction: TextInputAction.search,
            ),
          ),
        ),
      ),
      body: async.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_outlined, size: 48),
              const SizedBox(height: 12),
              Text(e is ApiException ? e.displayMessage : e.toString(),
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => ref.invalidate(_usersProvider(_query)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (data) {
          final users = (data['data'] as List?) ?? [];
          if (users.isEmpty) {
            return const Center(child: Text('No users found.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: users.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final u = users[i] as Map<String, dynamic>;
              // Roles may arrive as plain name strings or as {name: ...} objects.
              final roles = (u['roles'] as List?)
                      ?.map((r) => r is Map ? (r['name']?.toString() ?? '') : r.toString())
                      .where((r) => r.isNotEmpty)
                      .toList() ??
                  <String>[];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  foregroundColor:
                      Theme.of(context).colorScheme.onPrimaryContainer,
                  child: Text(
                    _initials(u['full_name']?.toString() ??
                        u['username']?.toString() ??
                        '?'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                title: Text(
                    u['full_name']?.toString() ??
                        u['username']?.toString() ??
                        '',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(u['email']?.toString() ?? '',
                    style: const TextStyle(fontSize: 12)),
                trailing: roles.isEmpty
                    ? null
                    : Chip(
                        label: Text(roles.first,
                            style: const TextStyle(fontSize: 11)),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                onTap: () => _showUserSheet(context, u, roles),
              );
            },
          );
        },
      ),
    );
  }

  void _showUserSheet(
      BuildContext context, Map<String, dynamic> user, List roles) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _UserSheet(
        user: user,
        currentRoles: roles.map((r) => r.toString()).toList(),
        onChanged: () {
          ref.invalidate(_usersProvider(_query));
        },
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

class _UserSheet extends ConsumerStatefulWidget {
  const _UserSheet({
    required this.user,
    required this.currentRoles,
    required this.onChanged,
  });

  final Map<String, dynamic> user;
  final List<String> currentRoles;
  final VoidCallback onChanged;

  @override
  ConsumerState<_UserSheet> createState() => _UserSheetState();
}

class _UserSheetState extends ConsumerState<_UserSheet> {
  late List<String> _roles;
  bool _saving = false;
  bool _deleting = false;

  static const _allRoles = ['user', 'admin', 'super-admin'];

  @override
  void initState() {
    super.initState();
    _roles = List.from(widget.currentRoles);
  }

  Future<void> _saveRoles() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(adminRepositoryProvider)
          .updateUserRoles(widget.user['id'].toString(), _roles);
      if (mounted) {
        Navigator.of(context).pop();
        widget.onChanged();
      }
    } on ApiException catch (e) {
      if (mounted) _snack(e.displayMessage, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _giftPremium() async {
    const periods = [
      ('day', 'Day Pass'),
      ('three_day', '3-Day Pass'),
      ('week', 'Weekly'),
      ('month', 'Monthly'),
    ];

    final period = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Gift a subscription',
                    style: Theme.of(sheetCtx).textTheme.titleMedium),
              ),
            ),
            for (final (value, label) in periods)
              ListTile(
                leading: const Icon(Icons.card_giftcard),
                title: Text(label),
                onTap: () => Navigator.of(sheetCtx).pop(value),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (period == null || !mounted) return;

    setState(() => _saving = true);
    try {
      await ref.read(adminRepositoryProvider).grantCredit(
            userId: widget.user['id'].toString(),
            period: period,
            reason: 'Admin gift',
          );
      if (mounted) {
        Navigator.of(context).pop();
        widget.onChanged();
        _snack('Premium gifted to ${widget.user['full_name'] ?? widget.user['username']}.');
      }
    } on ApiException catch (e) {
      if (mounted) _snack(e.displayMessage, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteUser() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete user?'),
        content: Text(
            'This will permanently remove ${widget.user['full_name'] ?? widget.user['email']}. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(c).colorScheme.error),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await ref
          .read(adminRepositoryProvider)
          .deleteUser(widget.user['id'].toString());
      if (mounted) {
        Navigator.of(context).pop();
        widget.onChanged();
      }
    } on ApiException catch (e) {
      if (mounted) _snack(e.displayMessage, error: true);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final busy = _saving || _deleting;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 8, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.user['full_name']?.toString() ??
                widget.user['username']?.toString() ??
                'User',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(widget.user['email']?.toString() ?? '',
              style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 20),
          Text('Roles',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: scheme.primary, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: _allRoles
                  .map((role) => CheckboxListTile(
                        title: Text(role),
                        value: _roles.contains(role),
                        onChanged: busy
                            ? null
                            : (v) {
                                setState(() {
                                  if (v == true) {
                                    _roles.add(role);
                                  } else {
                                    _roles.remove(role);
                                  }
                                });
                              },
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: busy ? null : _giftPremium,
              icon: const Icon(Icons.card_giftcard),
              label: const Text('Gift premium'),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : _deleteUser,
                  icon: _deleting
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scheme.error,
                    side: BorderSide(color: scheme.error),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy ? null : _saveRoles,
                  icon: _saving
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check),
                  label: const Text('Save roles'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
