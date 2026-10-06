import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../data/admin_repository.dart';

class UserManagementScreen extends ConsumerStatefulWidget {
  const UserManagementScreen({super.key});

  @override
  ConsumerState<UserManagementScreen> createState() =>
      _UserManagementScreenState();
}

class _UserManagementScreenState extends ConsumerState<UserManagementScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  String _query = '';
  int _page = 1;
  int? _lastPage;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  final List<Map<String, dynamic>> _users = [];

  @override
  void initState() {
    super.initState();
    _load();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200 &&
        !_loadingMore &&
        (_lastPage == null || _page < _lastPage!)) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _users.clear();
      _page = 1;
    });
    try {
      final data = await ref
          .read(adminRepositoryProvider)
          .listUsers(page: 1, search: _query);
      if (!mounted) return;
      final items = (data['data'] as List?) ?? [];
      final meta = data['meta'] as Map<String, dynamic>?;
      setState(() {
        _users.addAll(items.cast<Map<String, dynamic>>());
        _lastPage = (meta?['last_page'] as num?)?.toInt();
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.displayMessage;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    try {
      final next = _page + 1;
      final data = await ref
          .read(adminRepositoryProvider)
          .listUsers(page: next, search: _query);
      if (!mounted) return;
      final items = (data['data'] as List?) ?? [];
      setState(() {
        _page = next;
        _users.addAll(items.cast<Map<String, dynamic>>());
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _runSearch(String value) {
    _query = value.trim();
    _load();
  }

  Future<void> _openDetail(String userId) async {
    // The detail screen can change roles or delete the user — refresh on return.
    await context.push('/admin/users/$userId');
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
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
                          _runSearch('');
                        },
                      ),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                filled: true,
              ),
              onSubmitted: _runSearch,
              textInputAction: TextInputAction.search,
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off_outlined, size: 48),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _load,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            : _users.isEmpty
            ? const Center(child: Text('No users found.'))
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView.separated(
                  controller: _scroll,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _users.length + (_loadingMore ? 1 : 0),
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    if (i == _users.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    return _UserTile(
                      user: _users[i],
                      onTap: () => _openDetail(_users[i]['id'].toString()),
                    );
                  },
                ),
              ),
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({required this.user, required this.onTap});

  final Map<String, dynamic> user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = user['full_name']?.toString() ?? user['username']?.toString();
    // Roles may arrive as plain name strings or as {name: ...} objects.
    final roles =
        (user['roles'] as List?)
            ?.map(
              (r) => r is Map ? (r['name']?.toString() ?? '') : r.toString(),
            )
            .where((r) => r.isNotEmpty)
            .toList() ??
        <String>[];

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        child: Text(
          _initials(name ?? '?'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      title: Text(
        name ?? '',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        user['email']?.toString() ?? '',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: roles.isEmpty
          ? null
          : Chip(
              label: Text(roles.first, style: const TextStyle(fontSize: 11)),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
      onTap: onTap,
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
}
