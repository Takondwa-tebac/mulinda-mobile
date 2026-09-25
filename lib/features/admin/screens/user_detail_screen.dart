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
            onPressed: () => ref.invalidate(_userDetailProvider(userId)),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.invalidate(_userDetailProvider(userId)),
          child: Consumer(
            builder: (context, ref, _) {
              final async = ref.watch(_userDetailProvider(userId));

              return async.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48),
                      const SizedBox(height: 12),
                      Text(e is ApiException ? e.displayMessage : e.toString(),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () => ref.invalidate(_userDetailProvider(userId)),
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

class _UserDetailContent extends StatelessWidget {
  const _UserDetailContent({required this.user});

  final Map<String, dynamic> user;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Extract subscription data
    final subscription = user['subscription'] as Map<String, dynamic>?;
    final isSubscribed = subscription != null && subscription['active'] == true;

    // Extract roles
    final roles = (user['roles'] as List?)
            ?.map((r) => r is Map ? (r['name']?.toString() ?? '') : r.toString())
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
                    _initials(user['full_name']?.toString() ?? user['username']?.toString() ?? '?'),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user['full_name']?.toString() ?? user['username']?.toString() ?? '',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user['email']?.toString() ?? '',
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user['username']?.toString() ?? '',
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
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
            _InfoRow('Phone', user['phone_number']?.toString() ?? 'Not provided'),
            _InfoRow('Income Bracket', user['declared_income_bracket']?.toString() ?? 'Not set'),
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
              _InfoRow('Plan', subscription['plan_label']?.toString() ?? 'Unknown'),
              _InfoRow('Source', subscription['source']?.toString() ?? 'Unknown'),
              _InfoRow('Ends', _formatDate(subscription['ends_at'])),
              if (subscription['is_trial'] == true)
                _InfoRow('Type', 'Trial'),
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
                children: roles.map((role) => Chip(
                  label: Text(role),
                  backgroundColor: scheme.primaryContainer,
                  labelStyle: TextStyle(color: scheme.onPrimaryContainer),
                )).toList(),
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
              _InfoRow('Remaining', '${10 - (user['sms_capture_count'] ?? 0)}'),
            ],
          ),
      ],
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
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
final _userDetailProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, userId) async {
  return ref.read(adminRepositoryProvider).getUserDetail(userId);
});