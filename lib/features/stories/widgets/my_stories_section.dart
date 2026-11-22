import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/section_header.dart';
import '../data/story_models.dart';
import '../data/story_visibility.dart';
import 'story_home_cards.dart';
import 'story_slides.dart';

/// "My stories" at the top of Insights: the latest month story when it is
/// available and the year story once it is out. Nothing when there is none.
class MyStoriesSection extends ConsumerWidget {
  const MyStoriesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stories = ref.watch(myStoriesProvider).valueOrNull;
    if (stories == null || stories.isEmpty) return const SizedBox.shrink();
    final month = stories.month;
    final year = stories.year;
    return Padding(
      key: const ValueKey('my-stories'),
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader('stories.mine.title'.tr()),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                if (year != null)
                  _StoryTile(
                    kind: StoryKind.year,
                    periodKey: '${year.year}',
                    title: 'stories.mine.yearItem'.tr(namedArgs: {'year': '${year.year}'}),
                  ),
                if (month != null)
                  _StoryTile(
                    kind: StoryKind.month,
                    periodKey: month.period.key,
                    title: 'stories.mine.monthItem'.tr(
                      namedArgs: {'month': monthName(month.period.month ?? 1), 'year': '${month.period.year}'},
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StoryTile extends StatefulWidget {
  const _StoryTile({required this.kind, required this.periodKey, required this.title});

  final StoryKind kind;
  final String periodKey;
  final String title;

  @override
  State<_StoryTile> createState() => _StoryTileState();
}

class _StoryTileState extends State<_StoryTile> {
  @override
  void initState() {
    super.initState();
    trackStoryShown(widget.kind, widget.periodKey, 'insights');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      key: ValueKey('my-story-${widget.kind.name}'),
      minTileHeight: AppSpacing.minTouch + AppSpacing.md,
      leading: const CircleAvatar(
        backgroundColor: AppColors.onTeal,
        foregroundColor: AppColors.orange,
        child: Icon(Icons.auto_stories_rounded),
      ),
      title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('stories.mine.subtitle'.tr(), style: TextStyle(color: scheme.onSurfaceVariant)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(Routes.storyFor(widget.kind, widget.periodKey)),
    );
  }
}
