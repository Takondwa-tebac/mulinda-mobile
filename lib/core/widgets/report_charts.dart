import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../money/money_json.dart';
import '../theme/app_spacing.dart';
import '../theme/semantic_colors.dart';
import 'report_table.dart';

/// One bar of a [MulindaBarChart].
class BarDatum {
  const BarDatum({required this.value, required this.label, required this.readout, this.partial = false});

  /// Height (minor units or any consistent unit).
  final double value;

  /// Axis label; only some are drawn (every bar up to 7, otherwise weekly).
  final String label;

  /// What the readout above the chart says when this bar is tapped.
  final String readout;

  /// Not over yet (today): drawn as an outlined, lighter bar.
  final bool partial;
}

/// Daily bars with an optional dashed average line. Tapping a bar shows its
/// value in a readout above the chart, so labels never crowd the axis; the
/// table view lists every value.
class MulindaBarChart extends StatefulWidget {
  const MulindaBarChart({
    super.key,
    required this.bars,
    required this.hint,
    this.average,
    this.semanticsLabel,
    this.height = 190,
  });

  final List<BarDatum> bars;

  /// Readout text before anything is tapped.
  final String hint;

  /// Where the dashed line is drawn (same unit as the bars).
  final double? average;
  final String? semanticsLabel;
  final double height;

  @override
  State<MulindaBarChart> createState() => _MulindaBarChartState();
}

class _MulindaBarChartState extends State<MulindaBarChart> {
  int? _selected;

  @override
  void didUpdateWidget(covariant MulindaBarChart old) {
    super.didUpdateWidget(old);
    if (old.bars.length != widget.bars.length) _selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Teal ink on light (5.7:1), brand teal on dark: bright teal on white fails 3:1.
    final barColor = context.semantic.brandInk;
    final bars = widget.bars;
    final n = bars.length;
    final maxValue = bars.fold<double>(0, (m, b) => math.max(m, b.value));
    final maxY = maxValue <= 0 ? 1.0 : maxValue * 1.08;
    final tick = n <= 7 ? 1 : 7;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              _selected == null ? widget.hint : bars[_selected!].readout,
              key: const ValueKey('bar-readout'),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurface),
            ),
          ),
        ),
        Semantics(
          image: true,
          label: widget.semanticsLabel,
          child: SizedBox(
            height: widget.height,
            child: BarChart(
              BarChartData(
                maxY: maxY,
                minY: 0,
                alignment: BarChartAlignment.spaceAround,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(
                  show: true,
                  border: Border(bottom: BorderSide(color: scheme.outline)),
                ),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  topTitles: const AxisTitles(),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      getTitlesWidget: (v, meta) {
                        final i = v.toInt();
                        if (i < 0 || i >= n || i % tick != 0) return const SizedBox.shrink();
                        return SideTitleWidget(
                          axisSide: meta.axisSide,
                          space: 4,
                          child: Text(bars[i].label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                        );
                      },
                    ),
                  ),
                ),
                extraLinesData: widget.average == null || widget.average! <= 0
                    ? const ExtraLinesData()
                    : ExtraLinesData(
                        horizontalLines: [
                          HorizontalLine(
                            y: widget.average!,
                            color: scheme.onSurfaceVariant,
                            strokeWidth: 1.5,
                            dashArray: const [5, 4],
                          ),
                        ],
                      ),
                barTouchData: BarTouchData(
                  handleBuiltInTouches: false,
                  touchExtraThreshold: const EdgeInsets.symmetric(horizontal: 6, vertical: 40),
                  touchCallback: (event, response) {
                    if (!event.isInterestedForInteractions) return;
                    final i = response?.spot?.touchedBarGroupIndex;
                    if (i != null && i != _selected) setState(() => _selected = i);
                  },
                ),
                barGroups: [
                  for (var i = 0; i < n; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: bars[i].value,
                          width: math.max(4, math.min(28, 220 / math.max(n, 1))),
                          color: i == _selected
                              ? scheme.onSurface
                              : (bars[i].partial ? barColor.withValues(alpha: 0.3) : barColor),
                          borderSide: bars[i].partial ? BorderSide(color: barColor, width: 1) : null,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                          backDrawRodData: BackgroundBarChartRodData(show: true, toY: maxY, color: Colors.transparent),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A legend entry: a small mark and its meaning.
class ChartLegendItem extends StatelessWidget {
  const ChartLegendItem({super.key, required this.label, this.color, this.dashed = false, this.hatched = false});

  final String label;
  final Color? color;

  /// A dashed line (an average or an unfinished month).
  final bool dashed;

  /// A striped square (a bar or slice that is not complete).
  final bool hatched;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: dashed ? 22 : 12,
          height: 12,
          child: dashed
              ? CustomPaint(painter: _DashPainter(c))
              : CustomPaint(painter: HatchSwatchPainter(color: c, hatched: hatched)),
        ),
        const SizedBox(width: AppSpacing.xs),
        Flexible(child: Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant))),
      ],
    );
  }
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    final y = size.height / 2;
    for (double x = 0; x < size.width; x += 9) {
      canvas.drawLine(Offset(x, y), Offset(math.min(x + 5, size.width), y), p);
    }
  }

  @override
  bool shouldRepaint(covariant _DashPainter old) => old.color != color;
}

/// One point of a [MulindaLineChart].
class LinePointDatum {
  const LinePointDatum({required this.minorUnits, required this.label, required this.readout, this.partial = false});

  final int minorUnits;
  final String label;
  final String readout;

  /// Not complete (the current month): hollow point, dashed segment.
  final bool partial;
}

/// A monthly trend: solid line through complete months, dashed into the
/// unfinished one, two labelled gridlines. Tapping a point shows its value in
/// the readout (by default the last complete month).
class MulindaLineChart extends StatefulWidget {
  const MulindaLineChart({
    super.key,
    required this.points,
    required this.color,
    required this.currency,
    this.semanticsLabel,
    this.height = 170,
  });

  final List<LinePointDatum> points;
  final Color color;

  /// For the gridline labels ("MK 50,000").
  final String currency;
  final String? semanticsLabel;
  final double height;

  @override
  State<MulindaLineChart> createState() => _MulindaLineChartState();
}

class _MulindaLineChartState extends State<MulindaLineChart> {
  int? _selected;

  int get _defaultIndex {
    final complete = widget.points.lastIndexWhere((p) => !p.partial);
    return complete >= 0 ? complete : widget.points.length - 1;
  }

  /// A round step so that about two gridlines fall under the top value.
  static double _step(double max) {
    if (max <= 0) return 1;
    final raw = max / 2;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    for (final m in [1, 2, 2.5, 5, 10]) {
      if (m * mag >= raw) return m * mag;
    }
    return 10 * mag;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pts = widget.points;
    if (pts.isEmpty) return const SizedBox.shrink();
    final selected = (_selected ?? _defaultIndex).clamp(0, pts.length - 1);
    final maxValue = pts.fold<double>(0, (m, p) => math.max(m, p.minorUnits.toDouble()));
    final step = _step(maxValue);
    final maxY = math.max(step * 2, (maxValue / step).ceil() * step) * 1.1;
    final complete = [
      for (var i = 0; i < pts.length; i++)
        if (!pts[i].partial) FlSpot(i.toDouble(), pts[i].minorUnits.toDouble()),
    ];
    final firstPartial = pts.indexWhere((p) => p.partial);
    final dashed = firstPartial > 0
        ? [
            FlSpot((firstPartial - 1).toDouble(), pts[firstPartial - 1].minorUnits.toDouble()),
            FlSpot(firstPartial.toDouble(), pts[firstPartial].minorUnits.toDouble()),
          ]
        : (firstPartial == 0 ? [FlSpot(0, pts[0].minorUnits.toDouble())] : const <FlSpot>[]);

    FlDotPainter dot(FlSpot spot, double _, LineChartBarData _, int _) {
      final i = spot.x.toInt();
      final partial = pts[i].partial;
      return FlDotCirclePainter(
        radius: i == selected ? 6 : 4.5,
        color: partial ? scheme.surfaceContainerLow : widget.color,
        strokeColor: widget.color,
        strokeWidth: 2,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              pts[selected].readout,
              key: const ValueKey('line-readout'),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurface),
            ),
          ),
        ),
        Semantics(
          image: true,
          label: widget.semanticsLabel,
          child: SizedBox(
            height: widget.height,
            child: LineChart(
              LineChartData(
                minX: -0.3,
                maxX: pts.length - 0.7,
                minY: 0,
                maxY: maxY,
                borderData: FlBorderData(show: true, border: Border(bottom: BorderSide(color: scheme.outline))),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: step,
                  checkToShowHorizontalLine: (v) => v > 0,
                  getDrawingHorizontalLine: (_) => FlLine(color: scheme.surfaceContainerHigh, strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(),
                  topTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 72,
                      interval: step,
                      getTitlesWidget: (v, meta) {
                        if (v <= 0 || v > maxY / 1.1 + 1) return const SizedBox.shrink();
                        return SideTitleWidget(
                          axisSide: meta.axisSide,
                          child: Text(
                            formatMinorShort(v.round(), widget.currency),
                            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      interval: 1,
                      getTitlesWidget: (v, meta) {
                        final i = v.round();
                        if ((v - i).abs() > 0.01 || i < 0 || i >= pts.length) return const SizedBox.shrink();
                        return SideTitleWidget(
                          axisSide: meta.axisSide,
                          space: 4,
                          child: Text(pts[i].label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  handleBuiltInTouches: false,
                  touchSpotThreshold: 44,
                  touchCallback: (event, response) {
                    if (!event.isInterestedForInteractions) return;
                    final spot = response?.lineBarSpots?.firstOrNull;
                    if (spot != null) setState(() => _selected = spot.x.toInt());
                  },
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: complete,
                    color: widget.color,
                    barWidth: 2.5,
                    dotData: FlDotData(getDotPainter: dot),
                  ),
                  if (dashed.isNotEmpty)
                    LineChartBarData(
                      spots: dashed,
                      color: widget.color,
                      barWidth: 2.5,
                      dashArray: const [5, 5],
                      dotData: FlDotData(getDotPainter: dot),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
