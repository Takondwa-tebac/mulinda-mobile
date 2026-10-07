import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../../core/offline/cache_store.dart';
import '../../../core/offline/mutation_sync.dart';
import '../../../core/offline/offline_mode.dart';
import '../../../core/offline/offline_sync_runner.dart';
import '../../../core/router/routes.dart';
import '../../../core/offline/offline_prefetch.dart';
import '../../../core/offline/offline_storage.dart';
import '../../../core/offline/prefs.dart';
import '../../auth/providers/auth_controller.dart';
import '../../capture/data/sms_auto_capture.dart';
import '../../capture/data/sms_manual_scanner.dart';
import '../../capture/data/sms_outbox.dart';

/// The sync card of the Offline capture & sync screen: how many changes and SMS
/// are waiting, the outcome of the last sync, anything that could not be applied,
/// and a Sync now button with live progress.
class OfflineSyncSection extends ConsumerStatefulWidget {
  const OfflineSyncSection({super.key});

  @override
  ConsumerState<OfflineSyncSection> createState() => _OfflineSyncSectionState();
}

class _OfflineSyncSectionState extends ConsumerState<OfflineSyncSection>
    with WidgetsBindingObserver {
  int _pending = 0; // SMS waiting
  int _pendingChanges = 0; // edits/creates/deletes waiting
  List<SyncNotice> _notices = const [];
  SyncStatus? _status;
  bool _autoCaptureOn = false;

  bool _syncing = false;
  int _done = 0;
  int _total = 0;
  bool _checkingInbox = false;
  String _phase = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// A background sync may have run while the app was away.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_syncing) _refresh();
  }

  Future<void> _refresh() async {
    final pending = await SmsOutbox.instance.pendingCount();
    final status = await SmsOutbox.instance.lastStatus();
    final auto = await SmsAutoCapture.isEnabled();
    var changes = 0;
    try {
      changes = await EncryptedCacheStore.instance.count();
    } catch (_) {}
    final notices = await SyncNotices.load();
    if (!mounted) return;
    setState(() {
      _pending = pending;
      _pendingChanges = changes;
      _notices = notices;
      _status = status;
      _autoCaptureOn = auto;
    });
  }

  Future<void> _syncNow() async {
    setState(() {
      _syncing = true;
      _done = 0;
      _total = _pendingChanges;
      _phase = 'changes';
      _checkingInbox = false;
    });

    String message;
    try {
      // 1) Changes made offline (edits can depend on each other, so they go first).
      final changes = await runMutationSync(
        ProviderScope.containerOf(context),
        onProgress: (done, total) {
          if (mounted) setState(() { _done = done; _total = total; _phase = 'changes'; });
        },
      );

      // 2) SMS captured offline.
      if (mounted) setState(() { _done = 0; _total = _pending; _phase = 'sms'; });
      final flush = await SmsOutbox.instance.flush(
        onProgress: (done, total) {
          if (mounted) setState(() { _done = done; _total = total; _phase = 'sms'; });
        },
      );

      var captured = flush.created;
      if (flush.busy && changes.busy) {
        message = 'A sync is already running — it will finish on its own.';
      } else if (flush.offline || changes.offline) {
        message = 'No connection. Everything is saved and will sync automatically.';
      } else {
        // Also pick up anything the live listener missed (opted-in users only;
        // never reads messages from before the server baseline).
        if (_autoCaptureOn) {
          if (mounted) setState(() => _checkingInbox = true);
          final scan = await SmsManualScanner.instance.scanFinancialSms();
          captured += scan.processed;
        }
        final parts = <String>[
          if (changes.applied > 0) '${changes.applied} change${changes.applied == 1 ? '' : 's'} saved',
          if (captured > 0) '$captured new transaction${captured == 1 ? '' : 's'} captured',
          if (changes.conflicts + changes.dropped > 0)
            '${changes.conflicts + changes.dropped} not applied (see below)',
        ];
        message = parts.isEmpty ? 'Everything is up to date.' : 'Synced — ${parts.join(', ')}.';
      }
    } catch (_) {
      message = 'Sync failed. Please try again.';
    }

    await _refresh();
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _checkingInbox = false;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final signedIn = ref.watch(currentUserProvider) != null;
    final view = _view(scheme);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_sync_outlined, color: scheme.primary),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Offline capture & sync',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Bank and mobile-money SMS are saved on your phone first. With offline mode on, '
            'changes you make to transactions, goals and loans while offline wait safely too. '
            'Everything syncs automatically when you are back online. Each item is recorded '
            'only once, and if something was changed elsewhere in the meantime, the latest '
            'version is kept.',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 14),

          // Status
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: view.color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(view.icon, size: 20, color: view.color),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(view.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(view.detail,
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5, height: 1.35)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Progress while syncing
          if (_syncing) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                minHeight: 8,
                value: (_checkingInbox || _total == 0) ? null : (_done / _total).clamp(0.0, 1.0),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _checkingInbox
                  ? 'Checking for missed SMS…'
                  : _total == 0
                      ? 'Contacting the server…'
                      : 'Syncing ${_phase == 'changes' ? 'changes' : 'SMS'}: $_done of $_total…',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ],

          if (_notices.isNotEmpty) ...[
            const SizedBox(height: 14),
            _NoticesCard(
              notices: _notices,
              onClear: () async {
                await SyncNotices.clear();
                await _refresh();
              },
            ),
          ],

          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (!signedIn || _syncing) ? null : _syncNow,
              icon: _syncing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync, size: 18),
              label: Text(_syncing ? 'Syncing…' : 'Sync now'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
            ),
          ),
        ],
      ),
    );
  }

  /// What to tell the user, derived from the outbox and the last sync outcome.
  ({IconData icon, Color color, String title, String detail}) _view(ColorScheme scheme) {
    final status = _status;
    const amber = Color(0xFFB26A00);

    if (_pending > 0 || _pendingChanges > 0) {
      final limit = _pending > 0 && status != null && status.limitReached > 0;
      final offline = status?.offline ?? false;
      final waiting = [
        if (_pendingChanges > 0) '$_pendingChanges change${_pendingChanges == 1 ? '' : 's'}',
        if (_pending > 0) '$_pending SMS',
      ].join(' and ');
      return (
        icon: offline ? Icons.cloud_off_outlined : Icons.schedule,
        color: amber,
        title: '$waiting waiting to sync',
        detail: limit
            ? 'Your free SMS capture limit has been reached. Subscribe to sync these.'
            : offline
                ? 'No connection at the last attempt. They will sync automatically when you are online.'
                : 'They will sync automatically, or tap Sync now.${_lastLine(status)}',
      );
    }

    if (status == null) {
      return (
        icon: Icons.cloud_done_outlined,
        color: scheme.primary,
        title: 'Nothing waiting',
        detail: 'No SMS are waiting to sync. Tap Sync now to check for missed ones.',
      );
    }

    return (
      icon: Icons.check_circle_outline,
      color: Colors.green.shade700,
      title: 'Everything is synced',
      detail: 'Last sync ${_ago(status.at)}'
          '${status.created > 0 ? ' · ${status.created} new transaction${status.created == 1 ? '' : 's'} captured' : ''}.',
    );
  }

  String _lastLine(SyncStatus? status) =>
      status == null ? '' : ' Last attempt ${_ago(status.at)}.';

  String _ago(DateTime at) {
    final diff = DateTime.now().difference(at);
    if (diff.inSeconds < 45) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) {
      final hh = at.hour.toString().padLeft(2, '0');
      final mm = at.minute.toString().padLeft(2, '0');
      return diff.inHours < 12 ? '${diff.inHours} h ago' : 'today at $hh:$mm';
    }
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${at.day} ${months[at.month - 1]} ${at.year}';
  }
}

/// The plan-gated Offline mode switch: a toggle for eligible plans (3-day,
/// weekly, monthly, trial), a locked row with an upgrade action otherwise.
class OfflineModeRow extends ConsumerWidget {
  const OfflineModeRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final mode = ref.watch(offlineModeProvider);

    if (!mode.eligible) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.lock_outline, color: scheme.onSurfaceVariant),
        title: const Text('Offline mode', style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          mode.clockWrong
              ? 'Paused: your phone\'s date or time looks wrong. Connect to the internet to resume.'
              : mode.paused
                  ? 'Paused: your plan no longer includes it. Renew to resume.'
                  : 'Use Mulinda with no internet. Available on the 3-day, weekly and monthly plans.',
          style: const TextStyle(fontSize: 12.5, height: 1.35),
        ),
        trailing: mode.clockWrong
            ? null
            : TextButton(
                onPressed: () => context.push(Routes.subscription),
                child: Text(mode.paused ? 'Renew' : 'Upgrade'),
              ),
      );
    }

    final muted = TextStyle(color: scheme.onSurfaceVariant, fontSize: 13, height: 1.4);

    // The switch sits beside a short title; the explanation gets the full width
    // below it, so nothing is squeezed between the icon and the switch.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.offline_bolt_outlined, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  mode.enabled ? 'Offline mode is on' : 'Offline mode',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
              Switch(
                value: mode.enabled,
                onChanged: (v) => ref.read(offlineModeProvider.notifier).setEnabled(v),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Use Mulinda with no internet. While you are online, the screens you use are saved on this '
            'phone (encrypted), so your accounts, transactions, goals and loans still open offline.',
            style: muted,
          ),
          const SizedBox(height: 8),
          const _Point(Icons.edit_outlined, 'Add or edit transactions, goals and loans offline. They sync when you are back online.'),
          const _Point(Icons.sms_outlined, 'Bank and mobile-money SMS are captured offline too.'),
          if (mode.until != null)
            _Point(Icons.event_available_outlined, 'Included with your plan until ${_date(mode.until!)}.'),
          const _Point(Icons.delete_outline, 'Turning this off deletes the saved data from this phone.'),
        ],
      ),
    );
  }

  static String _date(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final l = d.toLocal();
    return '${l.day} ${months[l.month - 1]} ${l.year}';
  }
}

/// A short line with an icon, wrapping nicely on narrow screens.
class _Point extends StatelessWidget {
  const _Point(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5, height: 1.35)),
          ),
        ],
      ),
    );
  }
}

/// What the last sync could not apply (the server's version was kept, or the
/// item was rejected), with a way to dismiss it.
class _NoticesCard extends StatelessWidget {
  const _NoticesCard({required this.notices, required this.onClear});

  final List<SyncNotice> notices;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: scheme.error),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Not applied', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              TextButton(onPressed: onClear, child: const Text('Dismiss')),
            ],
          ),
          for (final n in notices.take(5))
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 6),
              child: Text(n.message, style: const TextStyle(fontSize: 12.5, height: 1.35)),
            ),
          if (notices.length > 5)
            Text('+ ${notices.length - 5} more',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// "Saved for offline use": when the app last saved the main screens' data, with
/// a button to do it now and live progress while it runs.
class SavedDataCard extends ConsumerWidget {
  const SavedDataCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final mode = ref.watch(offlineModeProvider);
    final prefetch = ref.watch(offlinePrefetchProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.download_for_offline_outlined, color: scheme.primary),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Saved on this phone', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            mode.active
                ? 'Your dashboard, accounts, transactions, goals, loans and more are saved here (encrypted) so '
                    'they open with no internet. They refresh automatically while you are online.'
                : 'Turn on Offline mode above and Mulinda will save your dashboard, accounts, transactions, '
                    'goals and loans on this phone so they open with no internet.',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13, height: 1.4),
          ),
          if (mode.active) ...[
            const SizedBox(height: 12),
            if (prefetch.running) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: prefetch.total == 0 ? null : (prefetch.done / prefetch.total).clamp(0.0, 1.0),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                prefetch.label.isEmpty
                    ? 'Saving your data…'
                    : 'Saving ${prefetch.label.toLowerCase()} (${prefetch.done + 1} of ${prefetch.total})…',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
            ] else
              Text(
                prefetch.lastSaved == null
                    ? 'Nothing saved yet.'
                    : 'Last saved ${_ago(prefetch.lastSaved!)}.',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            const SizedBox(height: 12),
            const _StoredDataList(),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: prefetch.running
                    ? null
                    : () async {
                        final result = await ref.read(offlinePrefetchProvider.notifier).start(force: true);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(SnackBar(
                            content: Text(result.offline
                                ? 'No connection. Connect to the internet to save your data.'
                                : result.failed > 0
                                    ? 'Saved, but ${result.failed} item${result.failed == 1 ? '' : 's'} could not be saved. Try again.'
                                    : 'Your data is saved on this phone.'),
                          ));
                      },
                icon: const Icon(Icons.download_outlined, size: 18),
                label: Text(prefetch.running ? 'Saving…' : 'Save my data now'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _ago(DateTime at) {
    final diff = DateTime.now().difference(at);
    if (diff.inSeconds < 45) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
  }
}

/// What is saved on the phone, by screen, with sizes, and a way to delete it.
/// Changes waiting to sync are never deleted from here.
class _StoredDataList extends ConsumerStatefulWidget {
  const _StoredDataList();

  @override
  ConsumerState<_StoredDataList> createState() => _StoredDataListState();
}

class _StoredDataListState extends ConsumerState<_StoredDataList> {
  StorageBreakdown? _breakdown;
  int _waiting = 0;
  bool _clearing = false;
  DateTime? _lastSeen;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    try {
      final usage = await EncryptedCacheStore.instance.usage(user.id);
      final waiting = await EncryptedCacheStore.instance.count(userId: user.id);
      if (!mounted) return;
      setState(() {
        _breakdown = StorageBreakdown.from(usage);
        _waiting = waiting;
      });
    } catch (_) {
      if (mounted) setState(() => _breakdown = const StorageBreakdown([]));
    }
  }

  Future<void> _clear() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear saved data?'),
        content: Text(
          'This removes the saved copies of your screens from this phone. They are saved again '
          'next time you are online. You will not be able to open them offline until then.'
          '${_waiting > 0 ? '\n\nYour $_waiting change${_waiting == 1 ? '' : 's'} waiting to sync will be kept.' : ''}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _clearing = true);
    try {
      await EncryptedCacheStore.instance.clearSaved(user.id);
      final prefs = ref.read(sharedPreferencesProvider);
      await prefs.remove(OfflinePrefetcher.lastKey);
      await prefs.remove(OfflinePrefetcher.cursorKey);
    } catch (_) {}
    await _load();
    if (!mounted) return;
    setState(() => _clearing = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Saved data cleared.')));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final prefetch = ref.watch(offlinePrefetchProvider);

    // Reload the list whenever a save finishes.
    if (prefetch.lastSaved != _lastSeen) {
      _lastSeen = prefetch.lastSaved;
      if (!prefetch.running) WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }

    final b = _breakdown;
    if (b == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: Text('Stored on this phone', style: TextStyle(fontWeight: FontWeight.w700))),
            Text(StorageBreakdown.formatBytes(b.totalBytes),
                style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 6),
        if (b.isEmpty)
          Text('Nothing is saved yet.', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5))
        else
          for (final g in b.groups)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(child: Text(g.label, style: const TextStyle(fontSize: 13))),
                  Text(
                    '${g.items} saved · ${StorageBreakdown.formatBytes(g.bytes)}',
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
                  ),
                ],
              ),
            ),
        if (_waiting > 0) ...[
          const SizedBox(height: 6),
          Text(
            '$_waiting change${_waiting == 1 ? '' : 's'} waiting to sync (kept when you clear saved data).',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
        ],
        if (!b.isEmpty) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _clearing || prefetch.running ? null : _clear,
              icon: _clearing
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.delete_outline, size: 18),
              label: const Text('Clear saved data'),
              style: TextButton.styleFrom(foregroundColor: scheme.error, padding: EdgeInsets.zero),
            ),
          ),
        ],
      ],
    );
  }
}

/// Text for the Personal data row that opens the offline screen.
final offlineSyncSummaryProvider = FutureProvider.autoDispose<String>((ref) async {
  final mode = ref.watch(offlineModeProvider);
  final sms = await SmsOutbox.instance.pendingCount();
  var changes = 0;
  try {
    changes = await EncryptedCacheStore.instance.count();
  } catch (_) {}
  final waiting = sms + changes;
  if (waiting > 0) return '$waiting waiting to sync';
  return mode.active ? 'Offline mode on · everything is synced' : 'SMS capture and offline mode';
});

/// The tappable row in Your data that opens the dedicated screen.
class OfflineSyncTile extends ConsumerWidget {
  const OfflineSyncTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(offlineSyncSummaryProvider).valueOrNull ?? 'SMS capture and offline mode';
    return ListTile(
      leading: const Icon(Icons.cloud_sync_outlined),
      title: const Text('Offline capture & sync'),
      subtitle: Text(summary),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(Routes.offlineSync),
    );
  }
}
