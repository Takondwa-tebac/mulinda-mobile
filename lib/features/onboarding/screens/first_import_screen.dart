import 'package:another_telephony/telephony.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../analytics/data/analytics_repository.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/notifications/push_service.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../shared/plural.dart';
import '../../activity/data/activity_repository.dart';
import '../../capture/data/sender_accounts.dart';
import '../../capture/data/sms_manual_scanner.dart';
import '../../dashboard/data/dashboard_repository.dart';
import '../first_run.dart';

enum _Stage { scanning, found, building, failed }

/// The 30-day history import offered right after SMS access is granted:
/// how many money messages were found, from whom, then "Build my budget"
/// creates the missing wallet and bank accounts and sends the messages
/// through the usual outbox sync. With nothing found it goes straight Home.
class FirstImportScreen extends ConsumerStatefulWidget {
  const FirstImportScreen({super.key});

  @override
  ConsumerState<FirstImportScreen> createState() => _FirstImportScreenState();
}

class _FirstImportScreenState extends ConsumerState<FirstImportScreen> {
  _Stage _stage = _Stage.scanning;
  List<SmsMessage> _messages = const [];
  List<SenderCount> _senders = const [];
  int _done = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() => _stage = _Stage.scanning);
    try {
      final messages = await FirstRunImport.instance.findMessages();
      if (!mounted) return;
      if (messages.isEmpty) {
        _goHome(imported: 0);
        return;
      }
      setState(() {
        _messages = messages;
        _senders = countBySender(messages.map((m) => m.address));
        _stage = _Stage.found;
      });
    } catch (_) {
      if (mounted) setState(() => _stage = _Stage.failed);
    }
  }

  Future<void> _build() async {
    setState(() {
      _stage = _Stage.building;
      _done = 0;
      _total = _messages.length;
    });

    // Accounts named after the senders, so every message has somewhere to go.
    // A failure here is not fatal: messages still arrive in the review queue.
    final repo = ref.read(activityRepositoryProvider);
    try {
      final existing = await repo.accounts();
      for (final account in accountsToCreate(_messages.map((m) => m.address), existing)) {
        await repo.createAccount(name: account.name, type: account.type);
      }
    } catch (_) {}

    final result = await FirstRunImport.instance.send(
      _messages,
      onProgress: (done, total) {
        if (mounted) {
          setState(() {
            _done = done;
            _total = total;
          });
        }
      },
    );
    if (!mounted) return;

    if (result.offline) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('firstImport.offline'.tr())));
    }
    final imported = result.offline ? 0 : _messages.length;
    Analytics.track('history_import_completed', {'count': imported, 'surface': 'first_run'});
    ref.invalidate(accountsProvider);
    ref.invalidate(dashboardProvider);
    invalidateAnalytics(ref.invalidate);
    _goHome(imported: imported);
    // The user has now seen their money: a fair moment to ask about reminders.
    PushService.instance.requestPermission();
  }

  void _goHome({required int imported}) {
    ref.read(firstRunProvider.notifier).importDone(imported);
    context.go(Routes.home);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: switch (_stage) {
          _Stage.scanning => _Progress(label: 'firstImport.scanning'.tr()),
          _Stage.building => _Progress(
            label: 'firstImport.building'.tr(),
            detail: _total > 0 ? 'firstImport.progress'.tr(args: ['$_done', '$_total']) : null,
            value: _total > 0 ? _done / _total : null,
          ),
          _Stage.failed => Column(
            children: [
              Expanded(child: ErrorRetry(message: 'firstImport.error'.tr(), onRetry: _scan)),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: TextButton(onPressed: () => _goHome(imported: 0), child: Text('firstImport.skip'.tr())),
              ),
            ],
          ),
          _Stage.found => _Found(
            count: _messages.length,
            senders: _senders,
            onBuild: _build,
            onSkip: () => _goHome(imported: 0),
          ),
        },
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.label, this.detail, this.value});

  final String label;
  final String? detail;
  final double? value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 48, height: 48, child: CircularProgressIndicator(value: value)),
            const SizedBox(height: AppSpacing.xl),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (detail != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(detail!, style: TextStyle(color: scheme.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}

class _Found extends StatelessWidget {
  const _Found({required this.count, required this.senders, required this.onBuild, required this.onSkip});

  final int count;
  final List<SenderCount> senders;
  final VoidCallback onBuild;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xxl, AppSpacing.xl, AppSpacing.lg),
            children: [
              Text(
                trCount('firstImport.found', count),
                style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.xl),
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final (i, s) in senders.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: scheme.primaryContainer,
                          foregroundColor: scheme.onPrimaryContainer,
                          child: Icon(
                            s.account?.type == 'bank'
                                ? Icons.account_balance_outlined
                                : s.account != null
                                    ? Icons.phone_android
                                    : Icons.sms_outlined,
                            size: 20,
                          ),
                        ),
                        title: Text(s.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                        trailing: Text(
                          trCount('firstImport.messages', s.count),
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 18, color: scheme.onSurfaceVariant),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'firstImport.note'.tr(),
                      style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                key: const ValueKey('first-import-build'),
                onPressed: onBuild,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                child: Text('firstImport.build'.tr()),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: onSkip,
                style: TextButton.styleFrom(minimumSize: const Size.fromHeight(AppSpacing.minTouch)),
                child: Text('firstImport.skip'.tr()),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
