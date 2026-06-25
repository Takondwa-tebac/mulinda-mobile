import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../data/admin_repository.dart';

class AuditTrailScreen extends ConsumerStatefulWidget {
  const AuditTrailScreen({super.key});

  @override
  ConsumerState<AuditTrailScreen> createState() => _AuditTrailScreenState();
}

class _AuditTrailScreenState extends ConsumerState<AuditTrailScreen> {
  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  final List<Map<String, dynamic>> _audits = [];
  int? _lastPage;

  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
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
      _audits.clear();
      _page = 1;
    });
    try {
      final data =
          await ref.read(adminRepositoryProvider).listAudits(page: 1);
      if (!mounted) return;
      final items = (data['data'] as List?) ?? [];
      final meta = data['meta'] as Map<String, dynamic>?;
      setState(() {
        _audits.addAll(items.cast<Map<String, dynamic>>());
        _lastPage = (meta?['last_page'] as num?)?.toInt();
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.displayMessage; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    try {
      final next = _page + 1;
      final data =
          await ref.read(adminRepositoryProvider).listAudits(page: next);
      if (!mounted) return;
      final items = (data['data'] as List?) ?? [];
      setState(() {
        _page = next;
        _audits.addAll(items.cast<Map<String, dynamic>>());
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit Trail'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
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
                          onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                )
              : _audits.isEmpty
                  ? const Center(child: Text('No audit records found.'))
                  : ListView.separated(
                      controller: _scroll,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _audits.length + (_loadingMore ? 1 : 0),
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        if (i == _audits.length) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(
                                child: CircularProgressIndicator()),
                          );
                        }
                        final a = _audits[i];
                        return _AuditTile(audit: a);
                      },
                    ),
    );
  }
}

class _AuditTile extends StatelessWidget {
  const _AuditTile({required this.audit});

  final Map<String, dynamic> audit;

  static const _eventColors = {
    'created': Colors.green,
    'updated': Colors.blue,
    'deleted': Colors.red,
  };

  static const _eventIcons = {
    'created': Icons.add_circle_outline,
    'updated': Icons.edit_outlined,
    'deleted': Icons.delete_outline,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final event = audit['event']?.toString() ?? 'updated';
    final color = _eventColors[event] ?? scheme.primary;
    final icon = _eventIcons[event] ?? Icons.history;

    final auditableType = audit['auditable_type']?.toString() ?? '';
    final typeName = auditableType.split('\\').last;
    final userName = (audit['user'] as Map?)?['name']?.toString() ??
        (audit['user'] as Map?)?['email']?.toString() ??
        'System';

    final createdAt = audit['created_at']?.toString() ?? '';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.15),
        foregroundColor: color,
        child: Icon(icon, size: 18),
      ),
      title: Text(
        '$event $typeName',
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('by $userName', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
          if (createdAt.isNotEmpty)
            Text(_formatDate(createdAt),
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11)),
        ],
      ),
      isThreeLine: true,
      onTap: () => _showDetails(context),
    );
  }

  void _showDetails(BuildContext context) {
    final old = audit['old_values'] as Map?;
    final nw = audit['new_values'] as Map?;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (_, sc) => ListView(
          controller: sc,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Text('Audit Details',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            if (old != null && old.isNotEmpty) ...[
              const Text('Before', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              _ValuesCard(values: old),
              const SizedBox(height: 12),
            ],
            if (nw != null && nw.isNotEmpty) ...[
              const Text('After', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              _ValuesCard(values: nw),
            ],
            if ((old == null || old.isEmpty) && (nw == null || nw.isEmpty))
              const Text('No value changes recorded.'),
          ],
        ),
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}

class _ValuesCard extends StatelessWidget {
  const _ValuesCard({required this.values});

  final Map values;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: values.entries
            .map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 110,
                        child: Text(e.key.toString(),
                            style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 12)),
                      ),
                      Expanded(
                        child: Text(
                          e.value?.toString() ?? 'null',
                          style: const TextStyle(
                              fontWeight: FontWeight.w500, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }
}
