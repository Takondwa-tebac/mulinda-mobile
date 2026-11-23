import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/clock.dart';
import '../data/stories_repository.dart';
import '../data/story_models.dart';
import '../data/story_visibility.dart';
import 'story_home_cards.dart';
import 'story_slides.dart';

/// One story the Home row offers.
class HomeStoryEntry {
  const HomeStoryEntry({required this.kind, required this.periodKey, this.month, required this.year});

  final StoryKind kind;
  final String periodKey;
  final int? month;
  final int year;
}

/// The stories the Home row lists: the released year and the latest
/// available month, leaving out any a big Home card already offers.
List<HomeStoryEntry> homeStoryEntries({
  required MyStories? stories,
  required bool monthCardShown,
  required bool yearCardShown,
}) {
  if (stories == null) return const [];
  final year = stories.year;
  final month = stories.month;
  return [
    if (year != null && !yearCardShown) HomeStoryEntry(kind: StoryKind.year, periodKey: '${year.year}', year: year.year),
    if (month != null && !monthCardShown)
      HomeStoryEntry(
        kind: StoryKind.month,
        periodKey: month.period.key,
        month: month.period.month,
        year: month.period.year,
      ),
  ];
}

/// "Your stories" on Home, under the figures: a compact row per available
/// story that opens it. Renders nothing when there is no story (or when the
/// big story cards above already offer it). Insights keeps "My stories".
class HomeStoriesRow extends ConsumerWidget {
  const HomeStoriesRow({super.key, this.margin = EdgeInsets.zero});

  /// Space around the row, applied only while it is visible.
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stories = ref.watch(myStoriesProvider).valueOrNull;
    final monthCard = ref.watch(homeMonthStoryProvider).valueOrNull != null;
    final status = ref.watch(yearStoryStatusProvider).valueOrNull;
    final yearCard = yearCardFor(now: ref.watch(clockProvider)(), status: status) == YearCard.ready;
    final entries = homeStoryEntries(stories: stories, monthCardShown: monthCard, yearCardShown: yearCard);
    if (entries.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: margin,
      child: Card(
        key: const ValueKey('home-stories'),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < entries.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: AppSpacing.lg + 36 + AppSpacing.md),
              _StoryRow(entry: entries[i], showLabel: i == 0),
            ],
          ],
        ),
      ),
    );
  }
}

class _StoryRow extends StatefulWidget {
  const _StoryRow({required this.entry, required this.showLabel});

  final HomeStoryEntry entry;
  final bool showLabel;

  @override
  State<_StoryRow> createState() => _StoryRowState();
}

class _StoryRowState extends State<_StoryRow> {
  @override
  void initState() {
    super.initState();
    trackStoryShown(widget.entry.kind, widget.entry.periodKey, 'home_row');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final e = widget.entry;
    final title = e.kind == StoryKind.year
        ? 'stories.mine.yearItem'.tr(namedArgs: {'year': '${e.year}'})
        : 'stories.mine.monthItem'.tr(namedArgs: {'month': monthName(e.month ?? 1), 'year': '${e.year}'});
    return InkWell(
      key: ValueKey('home-story-${e.kind.name}'),
      onTap: () => context.push(Routes.storyFor(e.kind, e.periodKey)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          child: Row(
            children: [
              // The story brand mark, the same in both themes.
              const CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.onTeal,
                foregroundColor: AppColors.orange,
                child: Icon(Icons.auto_stories_rounded, size: 18),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.showLabel)
                      Text('stories.home.rowLabel'.tr(), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                    Text(
                      title,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: scheme.onSurface),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
