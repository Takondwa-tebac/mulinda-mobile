import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/clock.dart';
import '../../../shared/plural.dart';
import '../../auth/providers/auth_controller.dart';
import '../data/stories_repository.dart';
import '../data/story_models.dart';
import '../data/story_visibility.dart';
import 'story_slides.dart';

/// `story_shown` once per story and surface in a session.
final _shown = <String>{};

void trackStoryShown(StoryKind kind, String key, String surface) {
  if (_shown.add('$surface/${kind.name}/$key')) {
    unawaited(Analytics.track('story_shown', {'story': kind.name, 'key': key, 'surface': surface}));
  }
}

/// Home's story cards: "Your (month) in money is ready" in the first days of
/// a month, and the year countdown or "It's here". Brand colours in both
/// themes. Renders nothing when there is nothing to offer.
class StoryHomeCards extends ConsumerWidget {
  const StoryHomeCards({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(homeMonthStoryProvider).valueOrNull;
    final status = ref.watch(yearStoryStatusProvider).valueOrNull;
    final now = ref.watch(clockProvider)();
    // Until the stored choice is known the countdown waits, so it never
    // flashes up and disappears.
    final tapped = status == null ? false : (ref.watch(yearReminderTappedProvider(status.year)).valueOrNull ?? true);
    final year = yearCardFor(now: now, status: status, reminderTapped: tapped);

    final cards = <Widget>[
      if (month != null) MonthReadyCard(story: month),
      if (year == YearCard.countdown) YearCountdownCard(status: status!),
      if (year == YearCard.ready) YearReadyCard(status: status!),
    ];
    if (cards.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in cards) ...[c, const SizedBox(height: AppSpacing.lg)],
      ],
    );
  }
}

/// A brand card with a tap target over all of it.
class _StoryCard extends StatelessWidget {
  const _StoryCard({required this.color, required this.child, this.onTap, super.key});

  final Color color;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(AppRadius.xl + 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(AppSpacing.xl - 4), child: child),
      ),
    );
  }
}

/// A pill that looks like a button inside a tappable card.
class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.background, required this.foreground});

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg + 2, vertical: AppSpacing.sm),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Text(label, style: TextStyle(color: foreground, fontSize: 15, fontWeight: FontWeight.w700)),
    );
  }
}

class MonthReadyCard extends StatefulWidget {
  const MonthReadyCard({super.key, required this.story});

  final MoneyStory story;

  @override
  State<MonthReadyCard> createState() => _MonthReadyCardState();
}

class _MonthReadyCardState extends State<MonthReadyCard> {
  @override
  void initState() {
    super.initState();
    trackStoryShown(StoryKind.month, widget.story.period.key, 'home');
  }

  @override
  Widget build(BuildContext context) {
    final month = monthName(widget.story.period.month ?? 1);
    return _StoryCard(
      key: const ValueKey('story-month-ready'),
      color: AppColors.onTeal,
      onTap: () => context.push(Routes.storyFor(StoryKind.month, widget.story.period.key)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'stories.home.new'.tr(),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.tealPale),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'stories.home.monthTitle'.tr(namedArgs: {'month': month}),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.25, color: AppColors.white),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'stories.home.monthBody'.tr(),
            style: const TextStyle(fontSize: 14, height: 1.45, color: AppColors.tealPale),
          ),
          const SizedBox(height: AppSpacing.md),
          _Pill(
            label: 'stories.home.monthCta'.tr(namedArgs: {'month': month}),
            background: AppColors.orange,
            foreground: AppColors.onOrange,
          ),
        ],
      ),
    );
  }
}

class YearCountdownCard extends ConsumerStatefulWidget {
  const YearCountdownCard({super.key, required this.status});

  final YearStoryStatus status;

  @override
  ConsumerState<YearCountdownCard> createState() => _YearCountdownCardState();
}

class _YearCountdownCardState extends ConsumerState<YearCountdownCard> {
  /// The switch as the person last set it (before the API answers).
  bool? _remind;
  bool _saving = false;

  String get _key => '${widget.status.year}';

  @override
  void initState() {
    super.initState();
    trackStoryShown(StoryKind.year, _key, 'home_countdown');
  }

  Future<void> _toggle() async {
    final next = !(_remind ?? widget.status.remindersEnabled);
    setState(() {
      _remind = next;
      _saving = true;
    });
    final messenger = ScaffoldMessenger.maybeOf(context);
    final release = widget.status.releaseAt;
    final date = release == null ? null : '${release.day} ${monthName(release.month)}';
    final userId = ref.read(currentUserProvider)?.id;
    try {
      await ref.read(storiesRepositoryProvider).setReminders(next);
      unawaited(Analytics.track('story_reminders_toggled', {'story': 'year', 'key': _key, 'enabled': next}));
      // Reminder set: the countdown steps aside until "It's here". Turning
      // reminders off keeps the card, so they can be turned back on here.
      if (next) await YearReminderStore.markTapped(userId, widget.status.year);
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              date == null
                  ? (next ? 'stories.home.remindSetNoDate' : 'stories.home.remindOffNoDate').tr()
                  : (next ? 'stories.home.remindSet' : 'stories.home.remindOff').tr(namedArgs: {'date': date}),
            ),
          ),
        );
      if (!mounted) return;
      ref
        ..invalidate(yearReminderTappedProvider(widget.status.year))
        ..invalidate(yearStoryStatusProvider);
    } catch (_) {
      if (mounted) setState(() => _remind = !next);
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('stories.home.remindFailed'.tr())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.status;
    final on = _remind ?? s.remindersEnabled;
    final release = s.releaseAt;
    final days = s.daysLeft;
    return Container(
      key: const ValueKey('story-year-countdown'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: AppColors.onTeal, borderRadius: BorderRadius.circular(AppRadius.xl + 8)),
      child: Stack(
        children: [
          Positioned(
            right: -50,
            top: -40,
            child: ExcludeSemantics(
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(color: AppColors.orange.withValues(alpha: 0.3), shape: BoxShape.circle),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg + 4, AppSpacing.xl - 2, AppSpacing.lg + 4, AppSpacing.xl - 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (release != null)
                  Text(
                    'stories.home.comingOn'
                        .tr(namedArgs: {'date': '${release.day} ${monthName(release.month)}'})
                        .toUpperCase(),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                      color: AppColors.tealPale,
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'stories.home.yearTitle'.tr(namedArgs: {'year': _key}),
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1.15, color: AppColors.white),
                ),
                const SizedBox(height: AppSpacing.md),
                Semantics(
                  label: '$days ${trCount('stories.home.daysToGo', days)}',
                  excludeSemantics: true,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '$days',
                        style: const TextStyle(
                          fontSize: 64,
                          fontWeight: FontWeight.w800,
                          height: 1,
                          color: AppColors.orange,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(
                        child: Text(
                          trCount('stories.home.daysToGo', days),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'stories.home.countdownBody'.tr(),
                  style: const TextStyle(fontSize: 14, height: 1.45, color: AppColors.tealPale),
                ),
                const SizedBox(height: AppSpacing.md),
                Semantics(
                  toggled: on,
                  child: on
                      ? OutlinedButton(
                          key: const ValueKey('story-remind'),
                          onPressed: _saving ? null : _toggle,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.tealPale,
                            side: BorderSide(color: AppColors.tealPale.withValues(alpha: 0.5)),
                            minimumSize: const Size(0, 44),
                            shape: const StadiumBorder(),
                            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                          child: Text('stories.home.remindersOn'.tr()),
                        )
                      : FilledButton(
                          key: const ValueKey('story-remind'),
                          onPressed: _saving ? null : _toggle,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.orange,
                            foregroundColor: AppColors.onOrange,
                            minimumSize: const Size(0, 44),
                            shape: const StadiumBorder(),
                            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                          child: Text('stories.home.remindMe'.tr()),
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

class YearReadyCard extends StatefulWidget {
  const YearReadyCard({super.key, required this.status});

  final YearStoryStatus status;

  @override
  State<YearReadyCard> createState() => _YearReadyCardState();
}

class _YearReadyCardState extends State<YearReadyCard> {
  @override
  void initState() {
    super.initState();
    trackStoryShown(StoryKind.year, '${widget.status.year}', 'home');
  }

  @override
  Widget build(BuildContext context) {
    final year = '${widget.status.year}';
    return _StoryCard(
      key: const ValueKey('story-year-ready'),
      color: AppColors.orange,
      onTap: () => context.push(Routes.storyFor(StoryKind.year, year)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'stories.home.itsHere'.tr(),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 2, color: AppColors.onOrange),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'stories.home.yearTitle'.tr(namedArgs: {'year': year}),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.1, color: AppColors.onOrange),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'stories.home.readyBody'.tr(),
            style: const TextStyle(fontSize: 14, height: 1.45, color: AppColors.onOrange),
          ),
          const SizedBox(height: AppSpacing.md),
          _Pill(label: 'stories.home.watch'.tr(), background: AppColors.onTeal, foreground: AppColors.white),
        ],
      ),
    );
  }
}
