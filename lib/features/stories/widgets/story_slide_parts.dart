import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import 'story_motion.dart';

/// Type for story slides (always on dark teal). Inter ships up to weight 700,
/// so the prototype's 800 and 900 render as 700.
abstract class StoryType {
  static const heavy = FontWeight.w800;

  static const eyebrow = TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.tealPale, letterSpacing: 2);
  static const lead = TextStyle(fontSize: 22, fontWeight: FontWeight.w700, height: 1.25);
  static const leadLight = TextStyle(fontSize: 20, fontWeight: FontWeight.w600, height: 1.25);
  static const body = TextStyle(fontSize: 16, color: AppColors.tealPale, height: 1.4);
  static const statement = TextStyle(fontSize: 24, fontWeight: heavy, height: 1.2);
  static const title = TextStyle(fontSize: 44, fontWeight: heavy, height: 1.05);

  static TextStyle hero(double size, {Color color = AppColors.orange}) =>
      TextStyle(fontSize: size, fontWeight: heavy, height: 1.0, color: color, letterSpacing: size > 90 ? -2 : -1);
}

/// A big figure that shrinks to fit the width instead of wrapping.
class StoryHero extends StatelessWidget {
  const StoryHero(this.text, {super.key, required this.size, this.color = AppColors.orange});

  final String text;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(text, maxLines: 1, style: StoryType.hero(size, color: color)),
    );
  }
}

/// Vertical room between slide items.
class StoryGap extends StatelessWidget {
  const StoryGap(this.height, {super.key});

  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(height: height);
}

/// A slide's items, revealed one after another.
Widget storyColumn(List<Widget> children) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children);

/// The orange disc with a money-style icon.
class StyleBadge extends StatelessWidget {
  const StyleBadge({super.key, required this.icon, this.size = 132});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(color: AppColors.orange, shape: BoxShape.circle),
        child: Icon(icon, size: size * 0.48, color: AppColors.onOrange),
      ),
    );
  }
}

/// A labelled row with a growing bar (top categories).
class StoryBarRow extends StatelessWidget {
  const StoryBarRow({
    super.key,
    required this.label,
    required this.value,
    required this.fraction,
    required this.color,
    this.bold = false,
    this.barHeight = 10,
    this.delay = Reveal.bar,
  });

  final String label;
  final String value;
  final double fraction;
  final Color color;
  final bool bold;
  final double barHeight;
  final double delay;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 16, fontWeight: bold ? FontWeight.w700 : FontWeight.w400);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: style)),
            const SizedBox(width: AppSpacing.sm),
            Text(value, style: style.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          ],
        ),
        const SizedBox(height: 6),
        StoryGrowBar(fraction: fraction, color: color, height: barHeight, delay: delay),
      ],
    );
  }
}
