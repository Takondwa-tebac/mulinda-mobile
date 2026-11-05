import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/money/money_json.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/semantic_colors.dart';

/// Demo amounts shown in the illustrations (formatted through lib/core/money).
const kDemoBalance = 1250000.0;
const kDemoPayment = 18450.0;
const kDemoGoalLeft = 120000.0;
const kDemoGoalShare = 0.6;

/// Seeded category colours (Food, Transport, Rent).
const _foodColor = Color(0xFFE67E22);
const _transportColor = Color(0xFF3498DB);
const _rentColor = Color(0xFF16A085);

/// Entry curve for everything that slides or fades in (Material "emphasized
/// decelerate"); [Curves.easeOutBack] is used only for the chip pop.
const _enter = Curves.easeOutCubic;

/// Progress of [t] through the window [begin]..[end] (0..1 of the whole
/// timeline), eased with [curve].
double seg(double t, double begin, double end, [Curve curve = _enter]) {
  if (t <= begin) return 0;
  if (t >= end) return 1;
  return curve.transform((t - begin) / (end - begin));
}

/// Whether the platform asks for reduced motion.
bool reduceMotion(BuildContext context) =>
    (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ||
    (MediaQuery.maybeAccessibleNavigationOf(context) ?? false);

/// Runs one timeline from 0 to 1 when [active] becomes true (and again each
/// time the slide comes back), plays once, and shows the final state at once
/// when reduced motion is on. Only the illustration rebuilds on each tick.
class OnboardingIllustration extends StatefulWidget {
  const OnboardingIllustration({super.key, required this.active, required this.duration, required this.builder});

  final bool active;
  final Duration duration;
  final Widget Function(BuildContext context, double t, bool reduced) builder;

  @override
  State<OnboardingIllustration> createState() => _OnboardingIllustrationState();
}

class _OnboardingIllustrationState extends State<OnboardingIllustration> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: widget.duration);
  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = reduceMotion(context);
    if (_reduced) {
      _controller.value = 1;
    } else if (widget.active && _controller.value == 0 && !_controller.isAnimating) {
      // First show (or reduced motion was just turned off): play from the start.
      _controller.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(covariant OnboardingIllustration old) {
    super.didUpdateWidget(old);
    _controller.duration = widget.duration;
    _sync(wasActive: old.active);
  }

  void _sync({required bool wasActive}) {
    if (_reduced) {
      _controller.value = 1;
    } else if (widget.active && !wasActive) {
      _controller.forward(from: 0);
    } else if (!widget.active) {
      // Rewind off-screen so the slide replays when it comes back.
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => widget.builder(context, _controller.value, _reduced),
        ),
      ),
    );
  }
}

/// The rounded panel each illustration sits in.
class IllustrationPanel extends StatelessWidget {
  const IllustrationPanel({super.key, required this.child, this.grow = false});

  final Widget child;

  /// Let the panel grow past 210 px when its content needs it (long
  /// translations, large text) instead of clipping.
  final bool grow;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: grow ? null : 210,
      constraints: grow ? const BoxConstraints(minHeight: 210) : null,
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }
}

/// Moves [child] up by [dy] pixels × (1 - [p]) and fades it in with [p].
Widget _rise(double p, Widget child, {double dy = 16}) => Opacity(
  opacity: p.clamp(0.0, 1.0),
  child: Transform.translate(offset: Offset(0, dy * (1 - p)), child: child),
);

// ----------------------------------------------------------------- Slide 1 --

/// A balance card that rises in while its amount counts up, then three
/// category bars that grow in one after another.
class BalanceIllustration extends StatelessWidget {
  const BalanceIllustration({super.key, required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    const bars = [
      ('onboarding.anim.food', 0.72, _foodColor),
      ('onboarding.anim.transport', 0.46, _transportColor),
      ('onboarding.anim.rent', 0.9, _rentColor),
    ];
    return IllustrationPanel(
      child: OnboardingIllustration(
        key: const ValueKey('onboarding-illustration-1'),
        active: active,
        duration: const Duration(milliseconds: 1400),
        builder: (context, t, _) {
          final card = seg(t, 0, 0.36);
          // ~900 ms count-up (0.1..0.74 of 1400 ms).
          final count = seg(t, 0.1, 0.74);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _rise(
                card,
                dy: 24,
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'onboarding.anim.balance'.tr(),
                        style: text.labelMedium?.copyWith(color: scheme.onPrimary.withValues(alpha: 0.85)),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          formatMoney((kDemoBalance * count).roundToDouble(), 'MWK'),
                          key: const ValueKey('onboarding-balance'),
                          style: text.headlineSmall?.copyWith(
                            color: scheme.onPrimary,
                            fontWeight: FontWeight.w800,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              for (var i = 0; i < bars.length; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _Bar(
                    label: bars[i].$1.tr(),
                    share: bars[i].$2 * seg(t, 0.45 + i * 0.086, 0.8 + i * 0.086),
                    color: bars[i].$3,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.label, required this.share, required this.color});

  final String label;
  final double share;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: Container(
            height: 10,
            decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(5)),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: share.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(5)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------- Slide 2 --

/// A mobile-money SMS drops in, becomes a transaction, and its suggested
/// category ("Food?") turns into a confirmed one ("Food").
class CaptureIllustration extends StatelessWidget {
  const CaptureIllustration({super.key, required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final semantic = context.semantic;
    final amount = formatMoney(kDemoPayment, 'MWK');
    return IllustrationPanel(
      child: OnboardingIllustration(
        key: const ValueKey('onboarding-illustration-2'),
        active: active,
        // The chip appears at ~1.1 s and confirms about 1 s later.
        duration: const Duration(milliseconds: 2400),
        builder: (context, t, reduced) {
          final sms = seg(t, 0, 0.21);
          final arrow = seg(t, 0.2, 0.3);
          final tile = seg(t, 0.26, 0.46);
          final chip = seg(t, 0.44, 0.6, Curves.easeOutBack);
          final confirmed = t >= 1;
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _rise(
                sms,
                dy: -24,
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(14),
                      topRight: Radius.circular(14),
                      bottomRight: Radius.circular(14),
                      bottomLeft: Radius.circular(4),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AIRTELMONEY',
                        style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'onboarding.anim.sms'.tr(args: [amount]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              Opacity(
                opacity: arrow,
                child: Icon(Icons.arrow_downward_rounded, size: 20, color: scheme.onSurfaceVariant),
              ),
              _rise(
                tile,
                Container(
                  padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
                  decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(14)),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(color: _foodColor.withValues(alpha: 0.15), shape: BoxShape.circle),
                        child: const Icon(Icons.shopping_cart, size: 18, color: _foodColor),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Shoprite Area 47',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            // The amount shares the chip's row so the merchant name gets the full width.
                            Row(
                              children: [
                                Transform.scale(
                                  scale: chip,
                                  alignment: Alignment.centerLeft,
                                  child: AnimatedSwitcher(
                                    duration: reduced ? Duration.zero : const Duration(milliseconds: 250),
                                    switchInCurve: _enter,
                                    transitionBuilder: (child, a) => FadeTransition(
                                      opacity: a,
                                      child: ScaleTransition(scale: a, child: child),
                                    ),
                                    child: confirmed
                                        ? _Chip(
                                            key: const ValueKey('onboarding-chip-confirmed'),
                                            icon: Icons.check_rounded,
                                            label: 'onboarding.anim.food'.tr(),
                                            fg: semantic.success,
                                            bg: semantic.successContainer,
                                          )
                                        : _Chip(
                                            key: const ValueKey('onboarding-chip-suggested'),
                                            icon: AppIcons.suggestion,
                                            label: 'onboarding.anim.foodQuestion'.tr(),
                                            fg: semantic.warning,
                                            bg: semantic.warningContainer,
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Spacer(),
                                Text('-$amount', style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.icon, required this.label, required this.fg, required this.bg});

  final IconData icon;
  final String label;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            maxLines: 1,
            style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- Slide 3 --

/// A goal ring that fills to 60% while the percentage counts up, then a
/// "MK 120,000 to go" pill.
class GoalIllustration extends StatelessWidget {
  const GoalIllustration({super.key, required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return IllustrationPanel(
      child: OnboardingIllustration(
        key: const ValueKey('onboarding-illustration-3'),
        active: active,
        duration: const Duration(milliseconds: 1600),
        builder: (context, t, _) {
          final fill = seg(t, 0, 0.62) * kDemoGoalShare;
          final label = seg(t, 0.3, 0.6);
          final pill = seg(t, 0.62, 0.9);
          return Column(
            children: [
              SizedBox(
                width: 112,
                height: 112,
                child: CustomPaint(
                  painter: RingPainter(value: fill, color: scheme.primary, track: scheme.surfaceContainerHigh),
                  child: Center(
                    child: Text(
                      '${(fill * 100).round()}%',
                      key: const ValueKey('onboarding-goal-percent'),
                      style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Opacity(
                opacity: label,
                child: Text(
                  'onboarding.anim.goalName'.tr(),
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 6),
              _rise(
                pill,
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(999)),
                  child: Text(
                    'onboarding.anim.toGo'.tr(args: [formatMoney(kDemoGoalLeft, 'MWK')]),
                    key: const ValueKey('onboarding-goal-pill'),
                    style: text.labelMedium?.copyWith(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A progress ring: [track] all round, [color] for the first [value] (0..1).
class RingPainter extends CustomPainter {
  RingPainter({required this.value, required this.color, required this.track, this.stroke = 12});

  final double value;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    if (value > 0) {
      canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * value.clamp(0.0, 1.0), false, paint..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant RingPainter old) => old.value != value || old.color != color || old.track != track;
}

// ----------------------------------------------------------------- Slide 4 --

/// The 24-hour trial: an orange ring fills, the four premium benefits check
/// in one by one, then "No card. Nothing renews by itself."
class TrialIllustration extends StatelessWidget {
  const TrialIllustration({super.key, required this.active});

  final bool active;

  static const benefits = [
    'onboarding.anim.benefitChat',
    'onboarding.anim.benefitInsights',
    'onboarding.anim.benefitAi',
    'onboarding.anim.benefitSms',
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final success = context.semantic.success;
    return IllustrationPanel(
      grow: true,
      child: OnboardingIllustration(
        key: const ValueKey('onboarding-illustration-4'),
        active: active,
        duration: const Duration(milliseconds: 1500),
        builder: (context, t, _) {
          final ring = seg(t, 0, 0.6);
          return Row(
            children: [
              SizedBox(
                width: 96,
                height: 96,
                child: CustomPaint(
                  painter: RingPainter(value: ring, color: scheme.secondary, track: scheme.surfaceContainerHigh),
                  child: Center(
                    child: Text(
                      'onboarding.anim.hours'.tr(),
                      textAlign: TextAlign.center,
                      style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < benefits.length; i++)
                      // Staggered by 110 ms (110 / 1500 of the timeline).
                      _rise(
                        seg(t, 0.2 + i * 0.0733, 0.47 + i * 0.0733),
                        dy: 8,
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle_rounded, size: 16, color: success),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  benefits[i].tr(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),
                    Opacity(
                      opacity: seg(t, 0.78, 1),
                      child: Text(
                        'onboarding.anim.noCard'.tr(),
                        key: const ValueKey('onboarding-no-card'),
                        style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
