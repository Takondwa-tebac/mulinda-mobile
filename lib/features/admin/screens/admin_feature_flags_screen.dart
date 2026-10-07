import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../data/admin_repository.dart';

final _featureFlagsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
      return ref.read(adminRepositoryProvider).featureFlags();
    });

/// Staged rollout and kill switch: turn a feature off for everyone, or show it
/// to a growing share of users. Changes apply to new requests straight away.
class AdminFeatureFlagsScreen extends ConsumerWidget {
  const AdminFeatureFlagsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_featureFlagsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Feature Flags')),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    e is ApiException
                        ? e.displayMessage
                        : 'Could not load the feature flags.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => ref.invalidate(_featureFlagsProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
          data: (flags) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final flag in flags) ...[
                _FlagCard(flag: flag),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FlagCard extends ConsumerStatefulWidget {
  const _FlagCard({required this.flag});

  final Map<String, dynamic> flag;

  @override
  ConsumerState<_FlagCard> createState() => _FlagCardState();
}

class _FlagCardState extends ConsumerState<_FlagCard> {
  late bool _enabled = widget.flag['enabled'] == true;
  late double _percent = ((widget.flag['rollout_percent'] as num?) ?? 100)
      .toDouble();
  bool _saving = false;

  String get _key => widget.flag['key'].toString();

  String get _title => switch (_key) {
    'offline_mode' => 'Offline mode',
    _ => _key.replaceAll('_', ' '),
  };

  Future<void> _save({bool? enabled, int? percent}) async {
    final before = (_enabled, _percent);
    setState(() => _saving = true);
    try {
      await ref
          .read(adminRepositoryProvider)
          .updateFeatureFlag(_key, enabled: enabled, rolloutPercent: percent);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enabled = before.$1;
        _percent = before.$2;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiException
                ? e.displayMessage
                : 'Could not save that change.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final allowListed = (widget.flag['allow_user_ids'] as List?)?.length ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                _title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(widget.flag['description']?.toString() ?? ''),
              value: _enabled,
              onChanged: _saving
                  ? null
                  : (v) {
                      setState(() => _enabled = v);
                      _save(enabled: v);
                    },
            ),
            const SizedBox(height: 4),
            Text(
              _enabled
                  ? 'Shown to ${_percent.round()}% of eligible users'
                  : 'Off for everyone',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            Slider(
              value: _percent,
              max: 100,
              divisions: 20,
              label: '${_percent.round()}%',
              onChanged: (_enabled && !_saving)
                  ? (v) => setState(() => _percent = v)
                  : null,
              onChangeEnd: (_enabled && !_saving)
                  ? (v) => _save(percent: v.round())
                  : null,
            ),
            if (allowListed > 0)
              Text(
                '$allowListed ${allowListed == 1 ? 'user is' : 'users are'} always included',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }
}
