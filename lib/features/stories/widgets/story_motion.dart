import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The clocks a story slide animates with: [entrance] runs from 0 to 1 over
/// [entranceSeconds] each time a slide appears, [drift] loops for the
/// background blobs. With reduced motion both stand still at their end.
class StoryMotion extends InheritedWidget {
  const StoryMotion({super.key, required this.entrance, required this.drift, required this.reduced, required super.child});

  /// How long a slide's entrance takes, end to end (the latest item, a bar
  /// starting at 1.2 s, ends here).
  static const entranceSeconds = 2.5;

  final Animation<double> entrance;
  final Animation<double> drift;
  final bool reduced;

  static StoryMotion? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<StoryMotion>();

  /// A still clock (everything shown at its final state).
  static const Animation<double> still = AlwaysStoppedAnimation<double>(1);

  @override
  bool updateShouldNotify(StoryMotion old) =>
      old.entrance != entrance || old.drift != drift || old.reduced != reduced;
}

/// Progress (0..1, eased) of an item that starts [delay] seconds into the
/// entrance and takes [duration] seconds.
double revealProgress(double entrance, {required double delay, required double duration, Curve curve = Curves.easeOut}) {
  final t = entrance * StoryMotion.entranceSeconds;
  final local = ((t - delay) / duration).clamp(0.0, 1.0);
  return curve.transform(local);
}

/// How an item enters.
enum RevealKind {
  /// Fades in while sliding up 28 px.
  up,

  /// Grows from 40% past full size and settles.
  pop,

  /// Turns in from -20 degrees while growing.
  spin,
}

/// The prototype's entrance steps: `a1` to `a4` slide up one after another,
/// `pop` and `spin` for the hero item.
abstract class Reveal {
  static const a1 = 0.0;
  static const a2 = 0.5;
  static const a3 = 1.1;
  static const a4 = 1.7;
  static const pop = 0.4;
  static const spin = 0.3;
  static const bar = 0.6;
}

/// Shows [child] with an entrance animation on the slide's clock.
class StoryReveal extends StatelessWidget {
  const StoryReveal({super.key, this.kind = RevealKind.up, this.delay = Reveal.a1, required this.child});

  final RevealKind kind;
  final double delay;
  final Widget child;

  static final _popScale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.4, end: 1.08), weight: 70),
    TweenSequenceItem(tween: Tween(begin: 1.08, end: 1.0), weight: 30),
  ]);

  @override
  Widget build(BuildContext context) {
    final motion = StoryMotion.maybeOf(context);
    if (motion == null || motion.reduced) return child;
    return AnimatedBuilder(
      animation: motion.entrance,
      child: child,
      builder: (context, child) {
        final e = motion.entrance.value;
        switch (kind) {
          case RevealKind.up:
            final p = revealProgress(e, delay: delay, duration: 0.6);
            return Opacity(
              opacity: p,
              child: Transform.translate(offset: Offset(0, 28 * (1 - p)), child: child),
            );
          case RevealKind.pop:
            final raw = revealProgress(e, delay: delay, duration: 0.7, curve: Curves.linear);
            final scale = _popScale.transform(const Cubic(0.2, 0.9, 0.3, 1.2).transform(raw).clamp(0.0, 1.0));
            return Opacity(
              opacity: (raw / 0.7).clamp(0.0, 1.0),
              child: Transform.scale(scale: scale, alignment: Alignment.centerLeft, child: child),
            );
          case RevealKind.spin:
            final p = revealProgress(e, delay: delay, duration: 0.8);
            return Opacity(
              opacity: p,
              child: Transform.rotate(
                angle: -20 * math.pi / 180 * (1 - p),
                alignment: Alignment.centerLeft,
                child: Transform.scale(scale: 0.6 + 0.4 * p, alignment: Alignment.centerLeft, child: child),
              ),
            );
        }
      },
    );
  }
}

/// A rounded bar that grows to [fraction] of the width.
class StoryGrowBar extends StatelessWidget {
  const StoryGrowBar({
    super.key,
    required this.fraction,
    required this.color,
    this.height = 10,
    this.delay = Reveal.bar,
  });

  final double fraction;
  final Color color;
  final double height;
  final double delay;

  @override
  Widget build(BuildContext context) {
    final motion = StoryMotion.maybeOf(context);
    final bar = DecoratedBox(
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(height / 2)),
      child: SizedBox(height: height),
    );
    Widget sized(double grow) => Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(widthFactor: (fraction * grow).clamp(0.0, 1.0), child: bar),
    );
    if (motion == null || motion.reduced) return sized(1);
    return AnimatedBuilder(
      animation: motion.entrance,
      builder: (_, _) => sized(revealProgress(motion.entrance.value, delay: delay, duration: 1.2)),
    );
  }
}

/// A month column that rises to [fraction] of the available height.
class StoryRiseColumn extends StatelessWidget {
  const StoryRiseColumn({super.key, required this.fraction, required this.color, required this.delay});

  final double fraction;
  final Color color;
  final double delay;

  @override
  Widget build(BuildContext context) {
    final motion = StoryMotion.maybeOf(context);
    final column = DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(6), bottom: Radius.circular(2)),
      ),
      child: const SizedBox(width: double.infinity),
    );
    Widget sized(double grow) => Align(
      alignment: Alignment.bottomCenter,
      // A sliver of a column even for a quiet month, so every month shows.
      child: FractionallySizedBox(heightFactor: math.max(0.02, fraction) * grow, child: column),
    );
    if (motion == null || motion.reduced) return sized(1);
    return AnimatedBuilder(
      animation: motion.entrance,
      builder: (_, _) => sized(revealProgress(motion.entrance.value, delay: delay, duration: 1.0)),
    );
  }
}

/// A soft circle that drifts up and down in the background.
class StoryBlob extends StatelessWidget {
  const StoryBlob({super.key, required this.size, required this.color, this.phase = 0});

  final double size;
  final Color color;

  /// Where in the loop this blob starts (0..1).
  final double phase;

  @override
  Widget build(BuildContext context) {
    final motion = StoryMotion.maybeOf(context);
    final blob = SizedBox.square(
      dimension: size,
      child: DecoratedBox(decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    );
    if (motion == null || motion.reduced) return blob;
    return AnimatedBuilder(
      animation: motion.drift,
      child: blob,
      builder: (_, child) {
        final t = (motion.drift.value + phase) % 1.0;
        // ease-in-out up 14 px and back, as in the prototype.
        final dy = -14 * (1 - math.cos(2 * math.pi * t)) / 2;
        return Transform.translate(offset: Offset(0, dy), child: child);
      },
    );
  }
}
