import 'dart:math' as math;

import 'package:flutter/material.dart';

/// One slice of a [DonutChart].
class DonutSlice {
  const DonutSlice({required this.value, required this.color, this.hatched = false});

  final double value;

  /// Fill colour, or the stripe colour when [hatched].
  final Color color;

  /// Drawn as diagonal stripes instead of a solid colour ("Everything else"),
  /// so it never reads as one more grey category.
  final bool hatched;
}

/// A ring split into slices with an optional label in the middle. The ring is
/// decorative for screen readers: pass [semanticsLabel] that names every slice
/// (each slice also has a named row or a table row next to it).
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.slices,
    this.size = 200,
    this.stroke = 28,
    this.center,
    this.semanticsLabel,
  });

  final List<DonutSlice> slices;
  final double size;
  final double stroke;
  final Widget? center;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      image: true,
      label: semanticsLabel,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size.square(size),
              painter: DonutPainter(
                values: [for (final s in slices) s.value],
                colors: [for (final s in slices) s.color],
                hatched: {for (var i = 0; i < slices.length; i++) if (slices[i].hatched) i},
                hatchBackground: scheme.surfaceContainerLow,
                track: scheme.surfaceContainerHigh,
                stroke: stroke,
              ),
            ),
            if (center != null)
              Padding(
                padding: EdgeInsets.all(stroke + 6),
                child: ExcludeSemantics(child: FittedBox(fit: BoxFit.scaleDown, child: center)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Draws a ring split into arcs proportional to [values]. Arcs whose index is
/// in [hatched] are drawn as stripes of their colour on [hatchBackground].
class DonutPainter extends CustomPainter {
  DonutPainter({
    required this.values,
    required this.colors,
    required this.track,
    this.stroke = 16,
    this.gap = 0.03,
    this.hatched = const {},
    this.hatchBackground,
  });

  final List<double> values;
  final List<Color> colors;
  final Color track;
  final double stroke;

  /// Gap between arcs in radians.
  final double gap;
  final Set<int> hatched;
  final Color? hatchBackground;

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
      final from = start + useGap / 2;
      final arc = math.max(0.0, sweep - useGap);
      if (hatched.contains(i)) {
        _hatchedArc(canvas, size, rect, from, arc, colors[i]);
      } else {
        canvas.drawArc(rect, from, arc, false, paint..color = colors[i]);
      }
      start += sweep;
    }
  }

  void _hatchedArc(Canvas canvas, Size size, Rect rect, double from, double sweep, Color color) {
    final outer = rect.inflate(stroke / 2);
    final inner = rect.deflate(stroke / 2);
    final sector = Path()
      ..arcTo(outer, from, sweep, true)
      ..arcTo(inner, from + sweep, -sweep, false)
      ..close();
    canvas.save();
    canvas.clipPath(sector);
    canvas.drawRect(Offset.zero & size, Paint()..color = hatchBackground ?? track);
    final line = Paint()
      ..color = color
      ..strokeWidth = 2.5;
    for (var x = -size.height; x < size.width + size.height; x += 6) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), line);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant DonutPainter old) =>
      old.values != values ||
      old.colors != colors ||
      old.track != track ||
      old.hatched != hatched ||
      old.hatchBackground != hatchBackground;
}
