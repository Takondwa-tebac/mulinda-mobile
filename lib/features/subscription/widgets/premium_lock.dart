import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'paywall_sheet.dart';

/// A polished gradient "unlock premium" card for inline use (e.g. in place of a
/// gated section). Tapping the button opens the paywall.
class PremiumUpsellCard extends StatelessWidget {
  const PremiumUpsellCard({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.workspace_premium,
    this.compact = false,
  });

  final String title;
  final String message;
  final IconData icon;

  /// Tighter padding for dense spots like the Plan advisory strip.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.all(compact ? 16 : 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, scheme.tertiary],
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.onPrimary.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: scheme.onPrimary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: scheme.onPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: compact ? 16 : 18,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: TextStyle(
              color: scheme.onPrimary.withValues(alpha: 0.9),
              fontSize: 13,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => showPaywall(context, feature: message),
              icon: const Icon(Icons.lock_open_rounded, size: 18),
              label: Text('subscription.unlock'.tr()),
              style: FilledButton.styleFrom(
                backgroundColor: scheme.onPrimary,
                foregroundColor: scheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen "locked" state shown in place of a premium feature. Centres the
/// upsell card; once the user subscribes the parent screen (watching the user)
/// rebuilds and reveals the real content.
class PremiumLockView extends StatelessWidget {
  const PremiumLockView({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.workspace_premium,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: PremiumUpsellCard(title: title, message: message, icon: icon),
      ),
    );
  }
}
