import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// A soft shimmer that sweeps across its [SkeletonBox] children. Built on a
/// plain [AnimationController] (no package). Stays still when the platform
/// asks for reduced motion.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHigh;
    final highlight = scheme.surfaceContainerLowest;
    return Semantics(
      label: MaterialLocalizations.of(context).refreshIndicatorSemanticLabel,
      child: AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) {
          final t = _controller.value;
          return ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (bounds) => LinearGradient(
              begin: Alignment(-1.5 + 3 * t, 0),
              end: Alignment(-0.5 + 3 * t, 0),
              colors: [base, highlight, base],
            ).createShader(bounds),
            child: child,
          );
        },
      ),
    );
  }
}

/// A grey rounded placeholder block.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = AppRadius.sm, this.circle = false});

  final double? width;
  final double height;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: circle ? height : width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(radius),
      ),
    );
  }
}

/// Placeholder rows shaped like transaction tiles.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 6, this.header = false, this.shrinkWrap = false});

  final int count;

  /// Adds card-shaped blocks on top (for dashboard-like screens).
  final bool header;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView(
        shrinkWrap: shrinkWrap,
        physics: shrinkWrap ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm, AppSpacing.screen, AppSpacing.lg),
        children: [
          if (header) ...[
            const SkeletonBox(height: 132, radius: AppRadius.xl),
            const SizedBox(height: AppSpacing.lg),
            const SkeletonBox(height: 168, radius: AppRadius.lg),
            const SizedBox(height: AppSpacing.xl),
          ],
          for (var i = 0; i < count; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Row(
                children: [
                  const SkeletonBox(height: 40, circle: true),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FractionallySizedBox(widthFactor: i.isEven ? 0.6 : 0.45, child: const SkeletonBox()),
                        const SizedBox(height: AppSpacing.sm),
                        const FractionallySizedBox(widthFactor: 0.35, child: SkeletonBox(height: 10)),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  const SkeletonBox(width: 64),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
