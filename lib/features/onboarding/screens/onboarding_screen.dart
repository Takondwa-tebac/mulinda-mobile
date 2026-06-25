import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';

/// Three branded intro slides with a persistent language toggle (Chichewa
/// default, switchable here) and Skip / Next / Get started controls.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  static const _slides = <_SlideData>[
    _SlideData(Icons.account_balance_wallet_rounded, 'onboarding.slide1.title', 'onboarding.slide1.body'),
    _SlideData(Icons.bolt_rounded, 'onboarding.slide2.title', 'onboarding.slide2.body'),
    _SlideData(Icons.trending_up_rounded, 'onboarding.slide3.title', 'onboarding.slide3.body'),
  ];

  bool get _isLast => _index == _slides.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Hand off to the permissions screen, which explains each permission and
  // then marks onboarding seen + proceeds to login.
  void _goPermissions() => context.go('${Routes.permissions}?onboarding=true');

  void _next() {
    if (_isLast) {
      _goPermissions();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Top bar: language toggle + Skip.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const _LanguageToggle(),
                  TextButton(
                    onPressed: _goPermissions,
                    child: Text('onboarding.skip'.tr()),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (i) => setState(() => _index = i),
                itemCount: _slides.length,
                itemBuilder: (_, i) => _Slide(data: _slides[i]),
              ),
            ),
            _Dots(count: _slides.length, index: _index),
            Padding(
              padding: const EdgeInsets.all(24),
              child: FilledButton(
                onPressed: _next,
                child: Text((_isLast ? 'onboarding.getStarted' : 'onboarding.next').tr()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlideData {
  const _SlideData(this.icon, this.titleKey, this.bodyKey);
  final IconData icon;
  final String titleKey;
  final String bodyKey;
}

class _Slide extends StatelessWidget {
  const _Slide({required this.data});
  final _SlideData data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 168,
            height: 168,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(40),
            ),
            child: Icon(data.icon, size: 76, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(height: 40),
          Text(
            data.titleKey.tr(),
            textAlign: TextAlign.center,
            style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          Text(
            data.bodyKey.tr(),
            textAlign: TextAlign.center,
            style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});
  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? scheme.primary : scheme.outlineVariant,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

class _LanguageToggle extends StatelessWidget {
  const _LanguageToggle();

  @override
  Widget build(BuildContext context) {
    final code = context.locale.languageCode;
    return SegmentedButton<String>(
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: 'ny', label: Text('NY')),
        ButtonSegment(value: 'en', label: Text('EN')),
      ],
      selected: {code == 'en' ? 'en' : 'ny'},
      onSelectionChanged: (s) => context.setLocale(Locale(s.first)),
    );
  }
}
