import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/security/screenshot_protection.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_retry.dart';
import '../../auth/providers/auth_controller.dart';
import '../data/stories_repository.dart';
import '../data/story_models.dart';
import '../data/story_visibility.dart';
import '../widgets/story_player.dart';
import '../widgets/story_share.dart';
import '../widgets/story_slides.dart';

/// "My month in money" (`key` 2026-10) or "My year in money" (`key` 2026),
/// full screen and always dark teal. Opened from Home, Insights and the
/// story push.
class StoryScreen extends ConsumerWidget {
  const StoryScreen({super.key, required this.kind, required this.periodKey});

  final StoryKind kind;
  final String periodKey;

  void _close(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.home);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = kind == StoryKind.month
        ? ref.watch(monthStoryProvider(periodKey))
        : ref.watch(yearStoryProvider(int.tryParse(periodKey) ?? 0));

    void retry() => kind == StoryKind.month
        ? ref.invalidate(monthStoryProvider(periodKey))
        : ref.invalidate(yearStoryProvider(int.tryParse(periodKey) ?? 0));

    Widget message(Widget child) => SafeArea(
      child: Stack(
        children: [
          Center(
            child: Padding(padding: const EdgeInsets.all(AppSpacing.xl), child: child),
          ),
          Positioned(
            top: AppSpacing.xs,
            right: AppSpacing.xs,
            child: IconButton(
              tooltip: 'stories.player.close'.tr(),
              onPressed: () => _close(context),
              icon: const Icon(Icons.close_rounded, color: AppColors.white),
            ),
          ),
        ],
      ),
    );

    // Stories are made to be shared, so screenshots are allowed here.
    return ScreenshotsAllowed(
      child: Theme(
        data: AppTheme.dark,
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: Scaffold(
            backgroundColor: AppColors.onTeal,
            body: async.when(
              loading: () => message(const CircularProgressIndicator(color: AppColors.teal)),
              error: (e, _) {
                if (kind == StoryKind.year && e is ApiException && e.statusCode == 403) {
                  return message(
                    EmptyState(
                      icon: Icons.hourglass_top_rounded,
                      title: 'stories.notYetTitle'.tr(namedArgs: {'year': periodKey}),
                      body: 'stories.notYetBody'.tr(),
                    ),
                  );
                }
                return message(ErrorRetry(message: 'stories.loadError'.tr(), onRetry: retry));
              },
              data: (story) => story.available
                  ? _StoryView(story: story, onClose: () => _close(context))
                  : message(
                      EmptyState(
                        icon: Icons.auto_stories_outlined,
                        title: 'stories.notAvailableTitle'.tr(),
                        body: 'stories.notAvailableBody'.tr(),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StoryView extends ConsumerStatefulWidget {
  const _StoryView({required this.story, required this.onClose});

  final MoneyStory story;
  final VoidCallback onClose;

  @override
  ConsumerState<_StoryView> createState() => _StoryViewState();
}

class _StoryViewState extends ConsumerState<_StoryView> {
  /// Amounts are hidden until the person chooses to show them.
  bool _amounts = false;
  bool _completed = false;

  MoneyStory get _s => widget.story;

  Map<String, Object?> get _props => {'story': _s.kind.name, 'key': _s.period.key};

  @override
  void initState() {
    super.initState();
    unawaited(Analytics.track('story_opened', _props));
    unawaited(_recordOpened());
  }

  Future<void> _recordOpened() async {
    final userId = ref.read(currentUserProvider)?.id;
    if (_s.kind == StoryKind.month) {
      await StoryOpenedStore.markOpened(userId, StoryKind.month, _s.period.key);
      if (mounted) ref.invalidate(homeMonthStoryProvider);
      return;
    }
    try {
      await ref.read(storiesRepositoryProvider).markYearViewed(year: _s.period.year);
      if (mounted) ref.invalidate(yearStoryStatusProvider);
    } catch (_) {
      // Not critical: Home keeps offering the year until it is recorded.
    }
  }

  void _onSlideShown(int index, int count) {
    if (index == count - 1 && !_completed) {
      _completed = true;
      unawaited(Analytics.track('story_completed', _props));
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget share(BuildContext _) => StoryShareSlide(
      story: _s,
      amounts: _amounts,
      onAmountsChanged: (v) => setState(() => _amounts = v),
      onInvite: _s.kind == StoryKind.year ? () => context.push(Routes.referral) : null,
    );
    final slides = _s.kind == StoryKind.month
        ? monthStorySlides(_s, amounts: _amounts, share: share)
        : yearStorySlides(_s, amounts: _amounts, share: share);
    return StoryPlayer(
      slides: slides,
      title: storyTitle(_s),
      onClose: widget.onClose,
      onSlideShown: (i) => _onSlideShown(i, slides.length),
    );
  }
}
