import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/semantic_colors.dart';
import '../onboarding_prefs.dart';
import '../widgets/onboarding_illustrations.dart';

/// Four branded intro slides (the fourth explains the free trial honestly) and
/// a closing summary, with a persistent language toggle and Skip / Next / Get
/// started controls. Each of the first four slides has a small code-built
/// animation that plays when the slide becomes active (see
/// onboarding_illustrations.dart). Skip jumps to the summary; Get started opens
/// sign up. SMS access is asked for after sign in, not here.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;
  bool _skipped = false;

  static final _slides = <_SlideData>[
    _SlideData((active) => BalanceIllustration(active: active), 'onboarding.slide1.title', 'onboarding.slide1.body'),
    _SlideData((active) => CaptureIllustration(active: active), 'onboarding.slide2.title', 'onboarding.slide2.body'),
    _SlideData((active) => GoalIllustration(active: active), 'onboarding.slide3.title', 'onboarding.slide3.body'),
    // What the free trial includes, how long it lasts, and that no card is needed.
    _SlideData((active) => TrialIllustration(active: active), 'onboarding.trial.title', 'onboarding.trial.body'),
  ];

  /// The animated slides plus the closing summary.
  static int get _pageCount => _slides.length + 1;

  bool get _isLast => _index == _pageCount - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _skip() {
    _skipped = true;
    _controller.animateToPage(_pageCount - 1, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  /// Onboarding is done: remember it and open sign up.
  Future<void> _finish() async {
    Analytics.track('onboarding_completed', {
      'step': _index + 1,
      'reason': _skipped ? 'skipped' : 'finished',
      'locale': context.locale.languageCode,
    });
    await OnboardingPrefs.markSeen();
    if (mounted) context.go(Routes.register);
  }

  void _next() {
    if (_isLast) {
      _finish();
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
            // Top bar: language toggle + Skip (hidden on the summary).
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.sm, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const _LanguageToggle(),
                  Visibility(
                    visible: !_isLast,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: TextButton(onPressed: _skip, child: Text('onboarding.skip'.tr())),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (i) => setState(() => _index = i),
                itemCount: _pageCount,
                itemBuilder: (_, i) =>
                    i < _slides.length ? _Slide(data: _slides[i], active: i == _index) : const _SummarySlide(),
              ),
            ),
            _Dots(count: _pageCount, index: _index),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
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

/// The closing slide: what Mulinda does in one line, and three promises.
class _SummarySlide extends StatelessWidget {
  const _SummarySlide();

  static const _checks = ['onboarding.summary.check1', 'onboarding.summary.check2', 'onboarding.summary.check3'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        key: const ValueKey('onboarding-summary'),
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The logo sits on white in both themes, as on the splash screen.
              Container(
                width: 72,
                height: 72,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Image.asset('assets/logo.png', excludeFromSemantics: true),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'onboarding.summary.title'.tr(),
                style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              Text(
                'onboarding.summary.body'.tr(),
                style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
              ),
              const SizedBox(height: AppSpacing.xl),
              for (final key in _checks)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_rounded, size: 22, color: context.semantic.success),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(key.tr(), style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
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
