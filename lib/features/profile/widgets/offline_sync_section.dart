import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../../core/offline/offline_mode.dart';
import '../../../core/router/routes.dart';
import '../../auth/providers/auth_controller.dart';
import '../../capture/data/sms_auto_capture.dart';
import '../../capture/data/sms_manual_scanner.dart';
import '../../capture/data/sms_outbox.dart';

/// "Offline capture & sync" block for the Your data card: explains the feature,
/// shows how many captured SMS are waiting and the outcome of the last sync, and
/// lets the user sync right now with live progress.
class OfflineSyncSection extends ConsumerStatefulWidget {
  const OfflineSyncSection({super.key});

  @override
  ConsumerState<OfflineSyncSection> createState() => _OfflineSyncSectionState();
}

class _OfflineSyncSectionState extends ConsumerState<OfflineSyncSection>
    with WidgetsBindingObserver {
  int _pending = 0;
  SyncStatus? _status;
  bool _autoCaptureOn = false;

  bool _syncing = false;
  int _done = 0;
  int _total = 0;
  bool _checkingInbox = false;

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
    if (!mounted) return;
    setState(() {
      _pending = pending;
      _status = status;
      _autoCaptureOn = auto;
    });
  }

  Future<void> _syncNow() async {
    setState(() {
      _syncing = true;
      _done = 0;
      _total = _pending;
      _checkingInbox = false;
    });

    String message;
    try {
      final flush = await SmsOutbox.instance.flush(
        onProgress: (done, total) {
          if (mounted) setState(() { _done = done; _total = total; });
        },
      );

      var captured = flush.created;
      if (flush.busy) {
        message = 'A sync is already running — it will finish on its own.';
      } else if (flush.offline) {
        message = 'No connection. Your SMS are saved and will sync automatically.';
      } else {
        // Also pick up anything the live listener missed (opted-in users only;
        // never reads messages from before the server baseline).
        if (_autoCaptureOn) {
          if (mounted) setState(() => _checkingInbox = true);
          final scan = await SmsManualScanner.instance.scanFinancialSms();
          captured += scan.processed;
        }
        message = captured > 0
            ? 'Synced — $captured new transaction${captured == 1 ? '' : 's'} captured.'
            : 'Everything is up to date.';
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
            'Bank and mobile-money SMS are saved on your phone first. If you have no '
            'connection they wait safely, then sync automatically when you are back '
            'online — each one is recorded only once.',
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
                      : 'Syncing $_done of $_total SMS…',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
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

          const SizedBox(height: 8),
          const Divider(),
          const _OfflineModeRow(),
        ],
      ),
    );
  }

  /// What to tell the user, derived from the outbox and the last sync outcome.
  ({IconData icon, Color color, String title, String detail}) _view(ColorScheme scheme) {
    final status = _status;
    const amber = Color(0xFFB26A00);

    if (_pending > 0) {
      final limit = status != null && status.limitReached > 0;
      final offline = status?.offline ?? false;
      return (
        icon: offline ? Icons.cloud_off_outlined : Icons.schedule,
        color: amber,
        title: '$_pending SMS waiting to sync',
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
class _OfflineModeRow extends ConsumerWidget {
  const _OfflineModeRow();

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
          mode.paused
              ? 'Paused — your plan no longer includes it. Renew to resume.'
              : 'Use Mulinda with no internet. Available on the 3-day, weekly and monthly plans.',
          style: const TextStyle(fontSize: 12.5, height: 1.35),
        ),
        trailing: TextButton(
          onPressed: () => context.push(Routes.subscription),
          child: Text(mode.paused ? 'Renew' : 'Upgrade'),
        ),
      );
    }

    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      secondary: Icon(Icons.offline_bolt_outlined, color: scheme.primary),
      title: const Text('Offline mode', style: TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        'Keep using Mulinda without internet — your latest data is kept on this phone and '
        'changes sync when you reconnect.'
        '${mode.until != null ? ' Included with your plan until ${_date(mode.until!)}.' : ''}'
        ' Viewing your records offline is rolling out soon; SMS capture already works offline.',
        style: const TextStyle(fontSize: 12.5, height: 1.35),
      ),
      value: mode.enabled,
      onChanged: (v) => ref.read(offlineModeProvider.notifier).setEnabled(v),
    );
  }

  static String _date(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final l = d.toLocal();
    return '${l.day} ${months[l.month - 1]} ${l.year}';
  }
}
