import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Chart | Table: the same rows drawn as a chart or listed as a table.
class ChartTableToggle extends StatelessWidget {
  const ChartTableToggle({super.key, required this.showTable, required this.onChanged});

  final bool showTable;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'analytics.viewToggle'.tr(),
      child: SegmentedButton<bool>(
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          minimumSize: const Size(0, 44),
          visualDensity: VisualDensity.standard,
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
        segments: [
          ButtonSegment(
            value: false,
            icon: const Icon(Icons.pie_chart_outline, size: 18),
            label: Text('analytics.chartView'.tr()),
          ),
          ButtonSegment(
            value: true,
            icon: const Icon(Icons.table_rows_outlined, size: 18),
            label: Text('analytics.tableView'.tr()),
          ),
        ],
        selected: {showTable},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}

/// One choice of a [PeriodSwitcher].
class PeriodSegment {
  const PeriodSegment({required this.label, this.key});

  final String label;
  final Key? key;
}

/// Day | Week | Month | 30 days | Custom: a row of equal 44 px buttons.
/// The last segment usually opens a sheet; that is up to [onSelected].
class PeriodSwitcher extends StatelessWidget {
  const PeriodSwitcher({super.key, required this.segments, required this.selected, required this.onSelected});

  final List<PeriodSegment> segments;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: 'analytics.periodGroup'.tr(),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: AppRadius.chip,
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            for (var i = 0; i < segments.length; i++)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: i == selected,
                  child: Material(
                    color: i == selected ? scheme.primaryContainer : Colors.transparent,
                    child: InkWell(
                      key: segments[i].key,
                      onTap: () => onSelected(i),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                segments[i].label,
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: i == selected ? scheme.onPrimaryContainer : scheme.onSurface,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "< Last 30 days / 24 Oct to 22 Nov >": steps to the period before or after,
/// same length. [onNext] null disables the forward arrow (the period already
/// includes today).
class PeriodStepper extends StatelessWidget {
  const PeriodStepper({super.key, required this.title, required this.range, this.onPrevious, this.onNext});

  final String title;
  final String range;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        IconButton(
          key: const ValueKey('period-previous'),
          tooltip: 'analytics.prevPeriod'.tr(),
          constraints: const BoxConstraints.tightFor(width: AppSpacing.minTouch, height: AppSpacing.minTouch),
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: Column(
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (range.isNotEmpty)
                  Text(
                    range,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ),
        IconButton(
          key: const ValueKey('period-next'),
          tooltip: 'analytics.nextPeriod'.tr(),
          constraints: const BoxConstraints.tightFor(width: AppSpacing.minTouch, height: AppSpacing.minTouch),
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

/// Which way a compared figure moved. One neutral colour for all: spending
/// more is not marked as bad, spending less is not marked as good.
enum ComparisonTrend { up, down, same, info }

/// One line comparing a figure with the period before ("MK 27,500 less than
/// the previous 30 days (MK 312,900).").
class ComparisonLine extends StatelessWidget {
  const ComparisonLine({super.key, required this.trend, required this.text, this.color, this.fontSize = 14});

  final ComparisonTrend trend;
  final String text;

  /// Text and icon colour (defaults to the ink variant).
  final Color? color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    final icon = switch (trend) {
      ComparisonTrend.up => Icons.trending_up,
      ComparisonTrend.down => Icons.trending_down,
      ComparisonTrend.same => Icons.trending_flat,
      ComparisonTrend.info => Icons.info_outline,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: Icon(icon, size: 18, color: tint)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: TextStyle(fontSize: fontSize, color: tint, height: 1.35))),
        ],
      ),
    );
  }
}

/// One "What stands out" fact: an icon, a sentence, an optional second line
/// and an optional link.
class InsightTile extends StatelessWidget {
  const InsightTile({super.key, required this.icon, required this.title, this.body, this.actionLabel, this.onAction});

  final IconData icon;
  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
              child: Icon(icon, size: 18, color: scheme.onPrimaryContainer),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.35)),
                if (body != null && body!.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(body!, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant, height: 1.35)),
                ],
                if (actionLabel != null && onAction != null)
                  TextButton(
                    onPressed: onAction,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(AppSpacing.minTouch, 44),
                      alignment: Alignment.centerLeft,
                    ),
                    child: Text(actionLabel!),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A short note with an icon (thin data, not-counted money, hints).
class NoteRow extends StatelessWidget {
  const NoteRow({super.key, required this.icon, required this.text, this.body});

  final IconData icon;
  final String text;
  final String? body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: scheme.surfaceContainer, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: Icon(icon, size: 18, color: scheme.onSurfaceVariant)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: TextStyle(fontWeight: body == null ? FontWeight.w400 : FontWeight.w600, height: 1.35)),
                if (body != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(body!, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant, height: 1.35)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
