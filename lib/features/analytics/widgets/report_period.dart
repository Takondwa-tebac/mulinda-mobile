import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/report_controls.dart';
import '../data/analytics_models.dart';
import '../presentation/analytics_text.dart';

/// Day | Week | Month | 30 days | Custom, with the stepper underneath.
class ReportPeriodBar extends StatelessWidget {
  const ReportPeriodBar({super.key, required this.selection, required this.onChanged, this.period});

  final PeriodSelection selection;

  /// The resolved period from the last response (for exact dates).
  final AnalyticsPeriod? period;
  final ValueChanged<PeriodSelection> onChanged;

  static const _keys = [PeriodKey.today, PeriodKey.thisWeek, PeriodKey.thisMonth, PeriodKey.last30Days];

  @override
  Widget build(BuildContext context) {
    final index = _keys.indexOf(selection.key);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PeriodSwitcher(
          segments: [
            PeriodSegment(label: 'analytics.seg.day'.tr(), key: const ValueKey('seg-today')),
            PeriodSegment(label: 'analytics.seg.week'.tr(), key: const ValueKey('seg-this_week')),
            PeriodSegment(label: 'analytics.seg.month'.tr(), key: const ValueKey('seg-this_month')),
            PeriodSegment(label: 'analytics.seg.d30'.tr(), key: const ValueKey('seg-last_30_days')),
            PeriodSegment(label: 'analytics.seg.custom'.tr(), key: const ValueKey('seg-custom')),
          ],
          selected: index < 0 ? 4 : index,
          onSelected: (i) async {
            if (i < 4) {
              onChanged(PeriodSelection(_keys[i]));
              return;
            }
            final picked = await showPeriodSheet(context, selection, includeShortcuts: false);
            if (picked != null) onChanged(picked);
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        PeriodStepper(
          title: periodTitle(selection, period),
          range: period == null ? '' : periodRange(period!),
          onPrevious: () => onChanged(selection.previous),
          onNext: selection.next == null ? null : () => onChanged(selection.next!),
        ),
      ],
    );
  }
}

/// "Choose a period": the quick choices plus a date range picker. Returns
/// null when dismissed. With [includeShortcuts] false the four choices the
/// switcher already shows are left out.
Future<PeriodSelection?> showPeriodSheet(
  BuildContext context,
  PeriodSelection current, {
  bool includeShortcuts = true,
}) {
  final options = <(PeriodSelection, String)>[
    if (includeShortcuts) (const PeriodSelection(PeriodKey.today), 'analytics.label.todaySoFar'.tr()),
    (const PeriodSelection(PeriodKey.thisWeek), 'analytics.label.weekSoFar'.tr()),
    if (includeShortcuts) (const PeriodSelection(PeriodKey.thisMonth), 'analytics.label.monthSoFar'.tr()),
    (PeriodSelection.defaultPeriod, 'analytics.label.last30'.tr()),
    (const PeriodSelection(PeriodKey.lastMonth), 'analytics.period.last_month'.tr()),
  ];
  return showModalBottomSheet<PeriodSelection>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                'analytics.sheet.title'.tr(),
                style: Theme.of(sheet).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final (sel, label) in options)
              ListTile(
                key: ValueKey('period-option-${sel.key.api}'),
                minTileHeight: AppSpacing.minTouch,
                contentPadding: EdgeInsets.zero,
                title: Text(label),
                trailing: sel == current ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(sheet).pop(sel),
              ),
            ListTile(
              key: const ValueKey('period-option-pick'),
              minTileHeight: AppSpacing.minTouch,
              contentPadding: EdgeInsets.zero,
              title: Text('analytics.sheet.pickDates'.tr()),
              trailing: const Icon(Icons.calendar_month_outlined),
              onTap: () async {
                final now = DateTime.now();
                final today = DateTime(now.year, now.month, now.day);
                final picked = await showDateRangePicker(
                  context: sheet,
                  firstDate: DateTime(now.year - 5),
                  lastDate: today,
                  initialDateRange: current.key == PeriodKey.custom && current.from != null && current.to != null
                      ? DateTimeRange(start: current.from!, end: current.to!)
                      : null,
                );
                if (picked == null || !sheet.mounted) return;
                // The API takes up to 366 days.
                final start = picked.end.difference(picked.start).inDays > 365
                    ? picked.end.subtract(const Duration(days: 365))
                    : picked.start;
                Navigator.of(sheet).pop(PeriodSelection.custom(start, picked.end));
              },
            ),
          ],
        ),
      ),
    ),
  );
}

/// "Last 30 days, 24 Oct to 22 Nov" as a chip that opens the period sheet
/// (category detail inherits the period from the report it came from).
class PeriodChip extends StatelessWidget {
  const PeriodChip({super.key, required this.selection, required this.onChanged, this.period});

  final PeriodSelection selection;
  final AnalyticsPeriod? period;
  final ValueChanged<PeriodSelection> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: scheme.surfaceContainer,
        borderRadius: AppRadius.chip,
        child: InkWell(
          key: const ValueKey('period-chip'),
          borderRadius: AppRadius.chip,
          onTap: () async {
            final picked = await showPeriodSheet(context, selection);
            if (picked != null) onChanged(picked);
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_today_outlined, size: 18, color: scheme.onSurfaceVariant),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(
                      periodChipLabel(selection, period),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Icon(Icons.expand_more, size: 18, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
