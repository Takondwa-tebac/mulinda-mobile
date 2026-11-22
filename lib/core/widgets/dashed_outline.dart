import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// A box with a dashed rounded outline: for something that is not there yet
/// (a placeholder, a "coming later" note) rather than a filled card.
class DashedOutline extends StatelessWidget {
  const DashedOutline({
    super.key,
    required this.child,
    this.color,
    this.radius = AppRadius.xl,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  final Widget child;

  /// Defaults to the theme's outline variant.
  final Color? color;
  final double radius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedRRectPainter(
        color: color ?? Theme.of(context).colorScheme.outlineVariant,
        radius: radius,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  static const _dash = 6.0;
  static const _gap = 4.0;
  static const _stroke = 1.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = Path()..addRRect(RRect.fromRectAndRadius(rect.deflate(_stroke / 2), Radius.circular(radius)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + _dash), paint);
        distance += _dash + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter old) => old.color != color || old.radius != radius;
}
