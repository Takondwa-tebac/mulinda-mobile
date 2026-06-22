import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';

/// Phase 0 onboarding placeholder: shows the welcome copy and a language
/// chooser (Chichewa default), then routes to login. The full 3-slide
/// onboarding is built in the onboarding phase.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(Icons.savings_rounded, color: scheme.onPrimaryContainer, size: 32),
              ),
              const SizedBox(height: 28),
              Text('onboarding.welcomeTitle'.tr(),
                  style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Text('onboarding.welcomeSubtitle'.tr(),
                  style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 28),
              Text('onboarding.chooseLanguage'.tr(),
                  style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Row(
                children: [
                  _LangChip(
                    label: 'profile.chichewa'.tr(),
                    selected: context.locale.languageCode == 'ny',
                    onTap: () => context.setLocale(const Locale('ny')),
                  ),
                  const SizedBox(width: 12),
                  _LangChip(
                    label: 'profile.english'.tr(),
                    selected: context.locale.languageCode == 'en',
                    onTap: () => context.setLocale(const Locale('en')),
                  ),
                ],
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => context.go(Routes.login),
                child: Text('onboarding.getStarted'.tr()),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _LangChip extends StatelessWidget {
  const _LangChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
