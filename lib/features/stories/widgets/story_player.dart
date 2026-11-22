import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import 'story_motion.dart';

/// One full-screen story slide.
class StorySlide {
  const StorySlide({required this.id, required this.background, required this.builder});

  /// A stable name (`messages`, `share`), for tests and analytics.
  final String id;
  final Color background;
  final WidgetBuilder builder;
}

/// Which slide is showing; moves stay within the slides.
class StoryNav {
  StoryNav(this.count) : assert(count > 0);

  final int count;
  int index = 0;

  bool get isFirst => index == 0;
  bool get isLast => index == count - 1;

  /// Go to the next slide; false on the last one.
  bool next() {
    if (isLast) return false;
    index++;
    return true;
  }

  /// Go to the previous slide; false on the first one.
  bool back() {
    if (isFirst) return false;
    index--;
    return true;
  }

  void restart() => index = 0;
}

/// A full-screen story player: segmented progress bars, the logo and [title]
/// on top with Replay and Close, a background colour per slide and drifting
/// blobs. Each slide waits [slideDuration] and moves on by itself (the last
/// one stays). Tap the right of the screen for the next slide, the left for
/// the previous one, and hold to pause.
///
/// With reduced motion (the system "remove animations" setting) nothing
/// moves on by itself and nothing animates.
class StoryPlayer extends StatefulWidget {
  const StoryPlayer({
    super.key,
    required this.slides,
    required this.title,
    required this.onClose,
    this.onSlideShown,
    this.slideDuration = const Duration(seconds: 5),
  });

  final List<StorySlide> slides;
  final String title;
  final VoidCallback onClose;

  /// Called with the slide index each time a slide appears.
  final ValueChanged<int>? onSlideShown;
  final Duration slideDuration;

  /// The share of the screen width, from the left, that goes back on a tap.
  static const backZone = 0.3;

  @override
  State<StoryPlayer> createState() => StoryPlayerState();
}

class StoryPlayerState extends State<StoryPlayer> with TickerProviderStateMixin {
  late StoryNav _nav = StoryNav(widget.slides.length);
  late final AnimationController _progress = AnimationController(vsync: this, duration: widget.slideDuration)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) next();
    });
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (StoryMotion.entranceSeconds * 1000).round()),
  );
  late final AnimationController _drift = AnimationController(vsync: this, duration: const Duration(seconds: 6));

  bool _reduced = false;
  bool _paused = false;
  bool _started = false;

  /// Bumped on every slide change so the slide's widgets start fresh.
  int _run = 0;

  int get index => _nav.index;
  bool get paused => _paused;
  bool get reducedMotion => _reduced;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!_started || reduced != _reduced) {
      _reduced = reduced;
      _started = true;
      _show();
    }
  }

  @override
  void didUpdateWidget(StoryPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slides.length != widget.slides.length) {
      final i = _nav.index.clamp(0, widget.slides.length - 1);
      _nav = StoryNav(widget.slides.length)..index = i;
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    _entrance.dispose();
    _drift.dispose();
    super.dispose();
  }

  /// Start the current slide: entrance, blobs and the countdown to the next.
  void _show() {
    _progress.stop();
    _progress.value = 0;
    if (_reduced) {
      _entrance.value = 1;
      _drift.stop();
    } else {
      _entrance.forward(from: 0);
      if (!_drift.isAnimating) _drift.repeat();
      if (!_nav.isLast && !_paused) _progress.forward(from: 0);
    }
    final i = _nav.index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _nav.index == i) widget.onSlideShown?.call(i);
    });
  }

  void _changed() {
    setState(() => _run++);
    _show();
  }

  void next() {
    if (_nav.next()) _changed();
  }

  /// The previous slide; on the first one, that slide starts again.
  void back() {
    _nav.back();
    _changed();
  }

  void restart() {
    _paused = false;
    _nav.restart();
    _changed();
  }

  void pause() {
    if (_paused) return;
    setState(() => _paused = true);
    _progress.stop();
  }

  void resume() {
    if (!_paused) return;
    setState(() => _paused = false);
    if (!_reduced && !_nav.isLast) _progress.forward();
  }

  void _onTapUp(TapUpDetails d, double width) {
    if (d.localPosition.dx < width * StoryPlayer.backZone) {
      back();
    } else {
      next();
    }
  }

  @override
  Widget build(BuildContext context) {
    final slide = widget.slides[_nav.index];
    final white = AppColors.white;
    return StoryMotion(
      entrance: _reduced ? StoryMotion.still : _entrance,
      drift: _reduced ? StoryMotion.still : _drift,
      reduced: _reduced,
      child: DefaultTextStyle.merge(
        style: TextStyle(color: white, height: 1.2),
        child: IconTheme.merge(
          data: IconThemeData(color: white),
          child: AnimatedContainer(
            duration: _reduced ? Duration.zero : const Duration(milliseconds: 600),
            color: slide.background,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Two soft blobs, as in the prototype; never in the way of taps.
                IgnorePointer(
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      Positioned(
                        right: -90,
                        top: 90,
                        child: StoryBlob(size: 260, color: AppColors.orange.withValues(alpha: 0.22)),
                      ),
                      Positioned(
                        left: -70,
                        bottom: 120,
                        child: StoryBlob(size: 200, color: AppColors.teal.withValues(alpha: 0.25), phase: 0.5),
                      ),
                    ],
                  ),
                ),
                SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
                        child: _Segments(
                          count: widget.slides.length,
                          index: _nav.index,
                          progress: _progress,
                          // Nothing counts down on the last slide or with reduced motion.
                          currentFull: _nav.isLast || _reduced,
                        ),
                      ),
                      _Header(title: widget.title, onReplay: restart, onClose: widget.onClose),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, box) => Semantics(
                            customSemanticsActions: {
                              CustomSemanticsAction(label: 'stories.player.next'.tr()): next,
                              CustomSemanticsAction(label: 'stories.player.back'.tr()): back,
                            },
                            child: GestureDetector(
                              key: const ValueKey('story-tap-area'),
                              behavior: HitTestBehavior.opaque,
                              onTapUp: (d) => _onTapUp(d, box.maxWidth),
                              onLongPressStart: (_) => pause(),
                              onLongPressEnd: (_) => resume(),
                              onLongPressCancel: resume,
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(28, AppSpacing.lg, 28, AppSpacing.xxl),
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minHeight: (box.maxHeight - AppSpacing.lg - AppSpacing.xxl).clamp(0, double.infinity),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      KeyedSubtree(
                                        key: ValueKey('story-slide-${slide.id}-$_run'),
                                        child: Builder(builder: slide.builder),
                                      ),
                                    ],
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Segments extends StatelessWidget {
  const _Segments({required this.count, required this.index, required this.progress, required this.currentFull});

  final int count;
  final int index;
  final Animation<double> progress;
  final bool currentFull;

  @override
  Widget build(BuildContext context) {
    Widget segment(double value) => Expanded(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: SizedBox(
          height: 3,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: AppColors.white.withValues(alpha: 0.3)),
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: value.clamp(0.0, 1.0),
                child: const ColoredBox(color: AppColors.white),
              ),
            ],
          ),
        ),
      ),
    );

    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: progress,
        builder: (_, _) => Row(
          children: [
            for (var k = 0; k < count; k++) ...[
              if (k > 0) const SizedBox(width: AppSpacing.xs),
              segment(k < index ? 1 : (k > index ? 0 : (currentFull ? 1 : progress.value))),
            ],
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onReplay, required this.onClose});

  final String title;
  final VoidCallback onReplay;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xs, AppSpacing.xs, 0),
      child: Row(
        children: [
          const StoryLogo(size: 26),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          Flexible(
            child: TextButton(
              key: const ValueKey('story-replay'),
              onPressed: onReplay,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.white,
                backgroundColor: AppColors.white.withValues(alpha: 0.15),
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                shape: const StadiumBorder(),
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              child: Text('stories.player.replay'.tr(), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          IconButton(
            key: const ValueKey('story-close'),
            tooltip: 'stories.player.close'.tr(),
            onPressed: onClose,
            color: AppColors.white,
            constraints: const BoxConstraints(minWidth: AppSpacing.minTouch, minHeight: AppSpacing.minTouch),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

/// The Mulinda logo on its small white tile, as on the story header and card.
class StoryLogo extends StatelessWidget {
  const StoryLogo({super.key, required this.size});

  static const asset = AssetImage('assets/logo.png');

  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.08),
        decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(size * 0.27)),
        child: const Image(image: asset),
      ),
    );
  }
}
