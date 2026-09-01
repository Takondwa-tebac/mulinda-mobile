import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/router/routes.dart';
import '../data/activity_models.dart';
import '../data/activity_repository.dart';

/// Review queue for transactions auto-recorded from SMS. The user confirms the
/// ones that are right and bulk-deletes (soft) the ones that aren't. Each
/// principal shows its fee/levy split nested underneath.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  final Set<String> _selected = {};
  bool _busy = false;

  Future<void> _refresh() async {
    ref.invalidate(reviewTransactionsProvider);
    await ref.read(reviewTransactionsProvider.future);
  }

  void _toggle(String id) {
    setState(() {
      _selected.contains(id) ? _selected.remove(id) : _selected.add(id);
    });
  }

  void _selectAll(List<Txn> items) {
    setState(() {
      if (_selected.length == items.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(items.map((t) => t.id));
      }
    });
  }

  Future<void> _run(Future<void> Function(List<String>) action, String done) async {
    if (_selected.isEmpty || _busy) return;
    setState(() => _busy = true);
    final ids = _selected.toList();
    try {
      await action(ids);
      _selected.clear();
      ref.invalidate(reviewTransactionsProvider);
      ref.invalidate(transactionsProvider);
      ref.invalidate(accountsProvider);
      await ref.read(reviewTransactionsProvider.future);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(done)));
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete selected?'),
        content: Text(
          'This removes ${_selected.length} transaction(s) and their fees/levies '
          'from your records. This can be undone by support if needed.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _run(
        (ids) => ref.read(activityRepositoryProvider).bulkDeleteTransactions(ids),
        'Deleted',
      );
    }
  }

  /// Let the user pick a time today/tomorrow to be reminded to review.
  Future<void> _scheduleReminder() async {
    final granted = await NotificationService.requestReminderPermissions();
    if (!granted) {
      _snack('Enable notifications to set a reminder.');
      return;
    }
    if (!mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 19, minute: 0),
      helpText: 'Remind me to review at',
    );
    if (time == null) return;

    final now = DateTime.now();
    var when = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    if (when.isBefore(now)) when = when.add(const Duration(days: 1));

    await NotificationService.scheduleReviewReminder(when);
    if (mounted) {
      final label = when.day == now.day ? 'today' : 'tomorrow';
      _snack('Reminder set for $label at ${time.format(context)}.');
    }
  }

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final review = ref.watch(reviewTransactionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review transactions'),
        actions: [
          IconButton(
            tooltip: 'Remind me to review',
            onPressed: _scheduleReminder,
            icon: const Icon(Icons.alarm_add_outlined),
          ),
          review.maybeWhen(
            data: (items) => items.isEmpty
                ? const SizedBox.shrink()
                : TextButton(
                    onPressed: () => _selectAll(items),
                    child: Text(_selected.length == items.length ? 'None' : 'All'),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: review.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ListView(
            children: const [
              SizedBox(height: 120),
              Center(child: Text('Could not load your review queue.')),
            ],
          ),
          data: (items) {
            if (items.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  Icon(Icons.verified_outlined, size: 56, color: Colors.green),
                  SizedBox(height: 12),
                  Center(child: Text('Nothing to review — you\'re all caught up.')),
                ],
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 120),
              itemCount: items.length,
              itemBuilder: (_, i) => _ReviewCard(
                txn: items[i],
                selected: _selected.contains(items[i].id),
                onToggle: () => _toggle(items[i].id),
                onLongPress: () => context.push(Routes.transactionDetail, extra: items[i].id),
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: _selected.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _confirmDelete,
                        icon: const Icon(Icons.delete_outline),
                        label: Text('Delete (${_selected.length})'),
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _run(
                                  (ids) => ref
                                      .read(activityRepositoryProvider)
                                      .confirmTransactions(ids),
                                  'Confirmed',
                                ),
                        icon: _busy
                            ? const SizedBox(
                                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.check),
                        label: Text('Confirm (${_selected.length})'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.txn,
    required this.selected,
    required this.onToggle,
    required this.onLongPress,
  });

  final Txn txn;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final incoming = txn.isIncome;
    final color = incoming ? Colors.green.shade700 : Colors.red.shade700;
    final sign = incoming ? '+' : '-';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: selected
            ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onLongPress: onLongPress,
        child: Column(
        children: [
          CheckboxListTile(
            value: selected,
            onChanged: (_) => onToggle(),
            controlAffinity: ListTileControlAffinity.leading,
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    txn.merchant ?? txn.reference ?? 'Transaction',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text('$sign${txn.amount.formatted}',
                    style: TextStyle(color: color, fontWeight: FontWeight.bold)),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 2),
                Text(
                  [
                    if (txn.accountName != null) txn.accountName,
                    if (txn.categoryName != null) txn.categoryName,
                    if (txn.date.isNotEmpty) txn.date,
                  ].whereType<String>().join(' · '),
                  style: const TextStyle(fontSize: 12),
                ),
                if (txn.fromSms)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _Chip(icon: Icons.sms_outlined, label: txn.sender!),
                  ),
              ],
            ),
          ),
          // Fee / levy split, shown as read-only nested rows.
          for (final child in txn.children)
            Padding(
              padding: const EdgeInsets.fromLTRB(56, 0, 16, 8),
              child: Row(
                children: [
                  Icon(
                    child.isLevy ? Icons.account_balance_outlined : Icons.receipt_long_outlined,
                    size: 14,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      child.isLevy ? 'Government levy' : 'Fee',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                  Text('-${child.amount.formatted}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
        ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}
