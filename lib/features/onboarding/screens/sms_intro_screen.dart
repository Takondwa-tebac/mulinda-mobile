import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/semantic_colors.dart';
import '../../capture/data/sms_auto_capture.dart';
import '../first_run.dart';

/// Right after sign in (Android): what Mulinda reads and never reads, then
/// Android's own SMS prompt. Allowing leads to the 30-day import; "Not now"
/// goes straight to Home, where the get-started steps take over.
class SmsIntroScreen extends ConsumerStatefulWidget {
  const SmsIntroScreen({super.key});

  @override
  ConsumerState<SmsIntroScreen> createState() => _SmsIntroScreenState();
}

class _SmsIntroScreenState extends ConsumerState<SmsIntroScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _skipIfAlreadyOn();
  }

  /// Automatic capture already on for this phone (a returning user): nothing
  /// to ask, and the launch scan catches up on its own.
  Future<void> _skipIfAlreadyOn() async {
    final on = await SmsAutoCapture.isEnabled();
    if (!on) return;
    final granted = await ref.read(permissionServiceProvider).smsStatus() == PermState.granted;
    if (!granted || !mounted) return;
    ref.read(firstRunProvider.notifier).smsStepDone(granted: true);
    context.go(Routes.home);
  }

  Future<void> _allow() async {
    setState(() => _busy = true);
    final granted = await SmsAutoCapture.instance.enableAndStart();
    if (!mounted) return;
    Analytics.track(granted ? 'sms_permission_granted' : 'sms_permission_denied', {
      'surface': 'first_run',
      if (!granted) 'reason': 'system_denied',
    });
    ref.read(firstRunProvider.notifier).smsStepDone(granted: granted);
    if (granted) {
      context.go(Routes.firstImport);
    } else {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('permissions.smsDenied'.tr())));
      context.go(Routes.home);
    }
  }

  void _notNow() {
    Analytics.track('sms_permission_denied', {'surface': 'first_run', 'reason': 'not_now'});
    ref.read(firstRunProvider.notifier).smsStepDone(granted: false);
    context.go(Routes.home);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xxl, AppSpacing.xl, AppSpacing.lg),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: CircleAvatar(
                      radius: 32,
                      backgroundColor: scheme.primaryContainer,
                      foregroundColor: scheme.onPrimaryContainer,
                      child: const Icon(Icons.sms_outlined, size: 30),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text('smsIntro.title'.tr(), style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'smsIntro.body'.tr(),
                    style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _ReadCard(
                    icon: Icons.check_circle_rounded,
                    iconColor: context.semantic.success,
                    title: 'smsIntro.readTitle'.tr(),
                    body: 'smsIntro.readBody'.tr(),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _ReadCard(
                    icon: Icons.block_rounded,
                    iconColor: context.semantic.danger,
                    title: 'smsIntro.neverTitle'.tr(),
                    body: 'smsIntro.neverBody'.tr(),
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
                    key: const ValueKey('sms-intro-allow'),
                    onPressed: _busy ? null : _allow,
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    child: Text('smsIntro.allow'.tr()),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    key: const ValueKey('sms-intro-not-now'),
                    onPressed: _busy ? null : _notNow,
                    style: TextButton.styleFrom(minimumSize: const Size.fromHeight(AppSpacing.minTouch)),
                    child: Text('smsIntro.notNow'.tr()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadCard extends StatelessWidget {
  const _ReadCard({required this.icon, required this.iconColor, required this.title, required this.body});

  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: iconColor, size: 22),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: AppSpacing.xs),
                  Text(body, style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
