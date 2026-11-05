import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/category_icons.dart';
import '../data/dashboard_models.dart';

/// Fallback colours for categories the server sent without one (brand-adjacent,
/// distinguishable, in a fixed order).
const _palette = [
  Color(0xFF2EC4B6),
  Color(0xFFFF9F1C),
  Color(0xFF3D7DD8),
  Color(0xFFB05CC8),
  Color(0xFF5FA83F),
  Color(0xFFE0565B),
  Color(0xFF8C9A97),
];

Color spendColor(CategorySpend s, int index) => parseHexColor(s.color) ?? _palette[index % _palette.length];

/// A donut of this month's spending by category with a legend of bars.
class SpendingChart extends StatelessWidget {
  const SpendingChart({super.key, required this.rows, this.onTapRow});

  final List<CategorySpend> rows;
  final void Function(CategorySpend row)? onTapRow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shown = rows.where((r) => r.amount.minorUnits > 0).toList();
    final total = shown.fold<int>(0, (s, r) => s + r.amount.minorUnits);
    if (total <= 0) return const SizedBox.shrink();
    final maxRow = shown.map((r) => r.amount.minorUnits).reduce(math.max);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          image: true,
          label: shown.map((r) => '${r.name} ${r.amount.formatted}').join(', '),
          child: SizedBox(
            width: 104,
            height: 104,
            child: CustomPaint(
              painter: DonutPainter(
                values: [for (final r in shown) r.amount.minorUnits.toDouble()],
                colors: [for (var i = 0; i < shown.length; i++) spendColor(shown[i], i)],
                track: scheme.surfaceContainerHigh,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: Column(
            children: [
              for (var i = 0; i < shown.length; i++)
                InkWell(
                  onTap: onTapRow == null ? null : () => onTapRow!(shown[i]),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                shown[i].name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                            Text(
                              shown[i].amount.formatted,
                              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: shown[i].amount.minorUnits / maxRow,
                            minHeight: 5,
                            backgroundColor: scheme.surfaceContainerHigh,
                            color: spendColor(shown[i], i),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Draws a ring split into arcs proportional to [values].
class DonutPainter extends CustomPainter {
  DonutPainter({required this.values, required this.colors, required this.track, this.stroke = 16, this.gap = 0.03});

  final List<double> values;
  final List<Color> colors;
  final Color track;
  final double stroke;

  /// Gap between arcs in radians.
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);

    final total = values.fold<double>(0, (s, v) => s + v);
    if (total <= 0) return;
    var start = -math.pi / 2;
    final useGap = values.where((v) => v > 0).length > 1 ? gap : 0.0;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * math.pi * 2;
      if (sweep <= 0) continue;
      canvas.drawArc(rect, start + useGap / 2, math.max(0, sweep - useGap), false, paint..color = colors[i]);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant DonutPainter old) => old.values != values || old.colors != colors || old.track != track;
}

/// A single-value ring (e.g. budget used) with a label in the middle.
class RingProgress extends StatelessWidget {
  const RingProgress({super.key, required this.value, required this.color, this.size = 96, this.center});

  final double value;
  final Color color;
  final double size;
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: DonutPainter(
              values: [v, 1 - v],
              colors: [color, Colors.transparent],
              track: Theme.of(context).colorScheme.surfaceContainerHigh,
              stroke: size * 0.12,
              gap: 0,
            ),
          ),
          ?center,
        ],
      ),
    );
  }
}
