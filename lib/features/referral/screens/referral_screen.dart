import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/security/screenshot_protection.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/semantic_colors.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/bottom_action_bar.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/stat_card.dart';
import '../data/referral_repository.dart';
import '../invite_message.dart';
import '../widgets/referral_qr_panel.dart';

/// Invite friends: the score (signed up, days earned), the invite link and
/// code to copy, how rewards work, a QR code and the share sheet. Every
/// number, the link and the invite message come from `GET /referral`.
class ReferralScreen extends ConsumerWidget {
  const ReferralScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final infoAsync = ref.watch(referralInfoProvider);
    final info = infoAsync.valueOrNull;

    // Nothing here is private, and people like to screenshot their QR code.
    return ScreenshotsAllowed(
      child: Scaffold(
        appBar: AppBar(title: Text('referral.title'.tr())),
        body: infoAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: ErrorRetry(
              message: e is ApiException ? e.displayMessage : null,
              onRetry: () => ref.invalidate(referralInfoProvider),
            ),
          ),
          data: (info) => RefreshIndicator(
            onRefresh: () => ref.refresh(referralInfoProvider.future),
            child: ReferralBody(info: info),
          ),
        ),
        bottomNavigationBar: info == null ? null : _InviteActions(info: info),
      ),
    );
  }
}

/// The scrolling part of the referral screen (separate for tests).
class ReferralBody extends StatelessWidget {
  const ReferralBody({super.key, required this.info});

  final ReferralInfo info;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final brand = context.semantic.brandInk;
    final days = info.rewardDays;

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm, AppSpacing.screen, AppSpacing.xl),
      children: [
        _Headline(days: days, style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, height: 1.2)),
        const SizedBox(height: AppSpacing.xl),
        SectionHeader('referral.scoreTitle'.tr()),
        Row(
          children: [
            Expanded(
              child: StatCard(
                key: const ValueKey('referral-signed-up'),
                centered: true,
                icon: Icons.group_outlined,
                value: '${info.signedUp}',
                label: 'referral.signedUp'.tr(),
                onTap: () => _showInfoSheet(
                  context,
                  title: 'referral.signedUp'.tr(),
                  body: Text(_signedUpExplainer(info), style: _sheetBody(context)),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: StatCard(
                key: const ValueKey('referral-days-earned'),
                centered: true,
                icon: Icons.workspace_premium_outlined,
                value: '${info.daysEarned}',
                valueColor: brand,
                label: 'referral.daysEarned'.tr(),
                onTap: () => _showInfoSheet(
                  context,
                  title: 'referral.daysEarned'.tr(),
                  body: Text(
                    days == null
                        ? 'referral.daysEarnedInfoNoDays'.tr()
                        : 'referral.daysEarnedInfo'.tr(namedArgs: {'days': '$days'}),
                    style: _sheetBody(context),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        SectionHeader('referral.inviteTitle'.tr()),
        _CopyRow(
          key: const ValueKey('referral-copy-link'),
          label: 'referral.linkLabel'.tr(),
          value: info.link.replaceFirst(RegExp(r'^https?://'), ''),
          copyValue: info.link,
          copiedMessage: 'referral.linkCopied'.tr(),
        ),
        const SizedBox(height: AppSpacing.sm),
        _CopyRow(
          key: const ValueKey('referral-copy-code'),
          label: 'referral.codeLabel'.tr(),
          value: info.code,
          copyValue: info.code,
          copiedMessage: 'referral.codeCopied'.tr(),
          spaced: true,
        ),
        const SizedBox(height: AppSpacing.xl),
        SectionHeader('referral.howTitle'.tr()),
        _RowButton(
          key: const ValueKey('referral-how'),
          leading: Icon(Icons.card_giftcard_outlined, color: context.semantic.warning),
          label: 'referral.howRow'.tr(),
          onTap: () => _showInfoSheet(context, title: 'referral.howSheetTitle'.tr(), body: _HowSteps(days: days)),
        ),
      ],
    );
  }

  String _signedUpExplainer(ReferralInfo info) {
    final base = 'referral.signedUpInfo'.tr();
    if (info.waiting == 0) return base;
    final days = info.rewardDays;
    final waiting = days == null
        ? 'referral.signedUpWaitingNoDays'.tr(namedArgs: {'count': '${info.waiting}'})
        : 'referral.signedUpWaiting'.tr(namedArgs: {'count': '${info.waiting}', 'days': '$days'});
    return '$base $waiting';
  }
}

TextStyle? _sheetBody(BuildContext context) => Theme.of(context).textTheme.bodyLarge?.copyWith(
  color: Theme.of(context).colorScheme.onSurfaceVariant,
  height: 1.5,
);

/// "Invite friends and get 7 days of Premium for each one", the reward part
/// in the brand colour.
class _Headline extends StatelessWidget {
  const _Headline({required this.days, required this.style});

  final int? days;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    if (days == null) return Text('referral.headlineNoDays'.tr(), style: style);
    final full = 'referral.headline'.tr(namedArgs: {'days': '$days'});
    final highlight = 'referral.headlineReward'.tr(namedArgs: {'days': '$days'});
    final at = full.indexOf(highlight);
    if (at < 0) return Text(full, style: style);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: full.substring(0, at)),
          TextSpan(text: highlight, style: TextStyle(color: context.semantic.brandInk)),
          TextSpan(text: full.substring(at + highlight.length)),
        ],
      ),
      style: style,
    );
  }
}

/// A tappable rounded row on the low surface (copy rows, "how it works").
class _RowButton extends StatelessWidget {
  const _RowButton({super.key, this.leading, required this.label, this.trailing, required this.onTap, this.child});

  final Widget? leading;
  final String label;
  final Widget? trailing;
  final Widget? child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: AppRadius.card,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
            child: Row(
              children: [
                if (leading != null) ...[ExcludeSemantics(child: leading!), const SizedBox(width: AppSpacing.md)],
                Expanded(
                  child: child ?? Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: AppSpacing.sm),
                trailing ?? Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Invite link  mulinda.../i/CODE  [copy]": copies on tap, the icon turns into
/// a tick for a moment.
class _CopyRow extends StatefulWidget {
  const _CopyRow({
    super.key,
    required this.label,
    required this.value,
    required this.copyValue,
    required this.copiedMessage,
    this.spaced = false,
  });

  final String label;
  final String value;
  final String copyValue;
  final String copiedMessage;

  /// Letter-spaced, for the short code.
  final bool spaced;

  @override
  State<_CopyRow> createState() => _CopyRowState();
}

class _CopyRowState extends State<_CopyRow> {
  bool _copied = false;
  Timer? _timer;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.copyValue));
    if (!mounted) return;
    setState(() => _copied = true);
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(widget.copiedMessage)));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brand = context.semantic.brandInk;
    return Semantics(
      button: true,
      label: '${widget.label}, ${widget.value}',
      hint: 'referral.copyHint'.tr(),
      excludeSemantics: true,
      child: _RowButton(
        label: widget.label,
        onTap: _copy,
        trailing: Icon(
          _copied ? Icons.check_rounded : Icons.copy_rounded,
          size: 20,
          color: _copied ? brand : scheme.onSurfaceVariant,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              // At most half the row, so large text never pushes the value out.
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: constraints.maxWidth / 2),
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  widget.value,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: widget.spaced ? 15 : 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: widget.spaced ? 1 : null,
                    color: brand,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The three steps of "How rewards work".
class _HowSteps extends StatelessWidget {
  const _HowSteps({required this.days});

  final int? days;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final steps = [
      'referral.step1'.tr(),
      'referral.step2'.tr(),
      days == null ? 'referral.step3NoDays'.tr() : 'referral.step3'.tr(namedArgs: {'days': '$days'}),
    ];
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: scheme.primaryContainer,
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: Text(steps[i], style: _sheetBody(context))),
              ],
            ),
          ),
      ],
    );
  }
}

/// A bottom sheet with a title, [body] and "Done" pinned at the bottom.
Future<void> _showInfoSheet(BuildContext context, {required String title, required Widget body, bool centered = false}) {
  return showAppSheet<void>(
    context,
    builder: (sheet) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: centered ? CrossAxisAlignment.center : CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: Theme.of(sheet).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.lg),
        body,
      ],
    ),
    footer: (sheet) => FilledButton(
      key: const ValueKey('referral-sheet-done'),
      onPressed: () => Navigator.of(sheet).pop(),
      child: Text('referral.done'.tr()),
    ),
  );
}

/// QR code and "Invite friends" pinned at the bottom.
class _InviteActions extends StatelessWidget {
  const _InviteActions({required this.info});

  final ReferralInfo info;

  void _showQr(BuildContext context) {
    Analytics.track('referral_qr_opened', const {});
    _showInfoSheet(
      context,
      title: 'referral.qrTitle'.tr(),
      centered: true,
      body: ReferralQrPanel(info: info),
    );
  }

  Future<void> _share(BuildContext context) async {
    Analytics.track('referral_share_opened', const {});
    await Share.share(inviteMessage(info, context.locale.languageCode));
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: OutlinedButton.icon(
                  key: const ValueKey('referral-qr'),
                  onPressed: () => _showQr(context),
                  icon: const Icon(Icons.qr_code_2_rounded),
                  label: Text('referral.qrButton'.tr(), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                flex: 5,
                child: FilledButton.icon(
                  key: const ValueKey('referral-share'),
                  style: BottomActionBar.ctaButtonStyle(context),
                  onPressed: () => _share(context),
                  icon: const Icon(Icons.ios_share_rounded),
                  label: Text('referral.shareButton'.tr(), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
