import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// One row of a [ReportTable]. The first cell is the label; the rest are
/// right-aligned figures.
class ReportTableRow {
  const ReportTableRow({required this.cells, this.onTap, this.swatch, this.hatched = false, this.key});

  final List<String> cells;
  final VoidCallback? onTap;

  /// A small colour square before the label (matches the chart).
  final Color? swatch;

  /// The swatch is striped ("Everything else").
  final bool hatched;
  final Key? key;
}

/// The table view of a chart: a header, one 48 px row per item (tappable when
/// the chart's item is) and a total row that equals the headline.
class ReportTable extends StatelessWidget {
  const ReportTable({super.key, required this.columns, required this.rows, this.footer, this.flex = const [5, 4, 2]});

  final List<String> columns;
  final List<ReportTableRow> rows;
  final List<String>? footer;

  /// Relative column widths.
  final List<int> flex;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final numStyle = const TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

    Widget line(List<String> cells, {TextStyle? style, Color? swatch, bool hatched = false}) => Row(
      children: [
        for (var i = 0; i < cells.length; i++)
          Expanded(
            flex: i < flex.length ? flex[i] : 2,
            child: i == 0
                ? Row(
                    children: [
                      if (swatch != null) ...[
                        _Swatch(color: swatch, hatched: hatched),
                        const SizedBox(width: AppSpacing.sm),
                      ],
                      Expanded(
                        child: Text(cells[i], style: style, maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  )
                : Text(cells[i], textAlign: TextAlign.right, style: numStyle.merge(style), maxLines: 1),
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: scheme.outlineVariant))),
          child: line(columns, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
        ),
        for (final r in rows)
          InkWell(
            key: r.key,
            onTap: r.onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: AppSpacing.minTouch),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
              ),
              child: line(r.cells, swatch: r.swatch, hatched: r.hatched),
            ),
          ),
        if (footer != null)
          Container(
            constraints: const BoxConstraints(minHeight: AppSpacing.minTouch),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
            alignment: Alignment.centerLeft,
            child: line(footer!, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.hatched});

  final Color color;
  final bool hatched;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 12,
      child: CustomPaint(painter: HatchSwatchPainter(color: color, hatched: hatched)),
    );
  }
}

/// A 3 px rounded square in [color], or diagonal stripes of it.
class HatchSwatchPainter extends CustomPainter {
  HatchSwatchPainter({required this.color, this.hatched = false});

  final Color color;
  final bool hatched;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(3));
    if (!hatched) {
      canvas.drawRRect(rrect, Paint()..color = color);
      return;
    }
    canvas.save();
    canvas.clipRRect(rrect);
    final line = Paint()
      ..color = color
      ..strokeWidth = 1.6;
    for (var x = -size.height; x < size.width + size.height; x += 4) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), line);
    }
    canvas.restore();
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = color
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant HatchSwatchPainter old) => old.color != color || old.hatched != hatched;
}
