import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/router/routes.dart';
import '../widgets/onboarding_illustrations.dart';

/// Four branded intro slides (the last one explains the free trial honestly) with a persistent language toggle (Chichewa
/// default, switchable here) and Skip / Next / Get started controls. Each slide has a small code-built animation that
/// plays when the slide becomes active (see onboarding_illustrations.dart).
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  static final _slides = <_SlideData>[
    _SlideData((active) => BalanceIllustration(active: active), 'onboarding.slide1.title', 'onboarding.slide1.body'),
    _SlideData((active) => CaptureIllustration(active: active), 'onboarding.slide2.title', 'onboarding.slide2.body'),
    _SlideData((active) => GoalIllustration(active: active), 'onboarding.slide3.title', 'onboarding.slide3.body'),
    // What the free trial includes, how long it lasts, and that no card is needed.
    _SlideData((active) => TrialIllustration(active: active), 'onboarding.trial.title', 'onboarding.trial.body'),
  ];

  bool get _isLast => _index == _slides.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Hand off to the permissions screen, which explains each permission and
  // then marks onboarding seen + proceeds to login.
  void _goPermissions({required bool skipped}) {
    Analytics.track('onboarding_completed', {
      'step': _index + 1,
      'reason': skipped ? 'skipped' : 'finished',
      'locale': context.locale.languageCode,
    });
    context.go('${Routes.permissions}?onboarding=true');
  }

  void _next() {
    if (_isLast) {
      _goPermissions(skipped: false);
    } else {
      _controller.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
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
                  TextButton(onPressed: () => _goPermissions(skipped: true), child: Text('onboarding.skip'.tr())),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (i) => setState(() => _index = i),
                itemCount: _slides.length,
                itemBuilder: (_, i) => _Slide(data: _slides[i], active: i == _index),
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
  const _SlideData(this.illustration, this.titleKey, this.bodyKey);

  /// Builds the slide's animation; it plays while `active` is true.
  final Widget Function(bool active) illustration;
  final String titleKey;
  final String bodyKey;
}

class _Slide extends StatelessWidget {
  const _Slide({required this.data, required this.active});
  final _SlideData data;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    // Centred when there is room, scrollable on short screens or large text.
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 8),
              data.illustration(active),
              const SizedBox(height: 32),
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
              const SizedBox(height: 8),
            ],
          ),
        ),
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
          key: ValueKey('onboarding-dot-$i'),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
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
