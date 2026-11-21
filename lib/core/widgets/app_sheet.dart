import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/app_spacing.dart';

/// Opens a modal bottom sheet that behaves on every phone: it stays clear of
/// the status bar, notches and the gesture bar or nav buttons, scrolls when
/// its content is taller than the screen, and works at large text sizes and
/// in landscape. Snack bars shown from inside it appear on the sheet.
///
/// Short content gets a sheet sized to it. Content taller than [peek] of the
/// screen opens at [peek] and can be dragged up to its full height (or
/// scrolled), and dragged down to close.
///
/// [footer] (usually the sheet's buttons) stays pinned under the scrolling
/// body so it is always reachable, unless it would take up too much of a
/// short screen, in which case it scrolls with the body.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  WidgetBuilder? footer,
  bool useRootNavigator = true,
  double peek = AppSheet.defaultPeek,
}) {
  return showAppSheetWith<T>(
    context,
    useRootNavigator: useRootNavigator,
    builder: (sheet) => AppSheet(
      peek: peek,
      footer: footer == null ? null : Builder(builder: footer),
      body: Builder(builder: builder),
    ),
  );
}

/// Like [showAppSheet], for sheets with their own state: [builder] returns a
/// widget that builds an [AppSheet].
Future<T?> showAppSheetWith<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool useRootNavigator = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: builder,
  );
}

/// The body of a sheet opened with [showAppSheet] (public for tests and for
/// callers that build the modal route themselves).
class AppSheet extends StatefulWidget {
  const AppSheet({super.key, required this.body, this.footer, this.peek = defaultPeek});

  /// The share of the available height a tall sheet opens at.
  static const double defaultPeek = 0.7;

  /// A pinned footer is moved into the scrolling body when it is taller than
  /// this share of the available height (landscape, very large text).
  static const double maxPinnedFooter = 0.4;

  final Widget body;
  final Widget? footer;
  final double peek;

  @override
  State<AppSheet> createState() => _AppSheetState();
}

class _AppSheetState extends State<AppSheet> {
  // Keep the body and footer state (busy flags, scroll-free content) when the
  // sheet switches between its short and draggable layouts.
  final _bodyKey = GlobalKey(debugLabel: 'app-sheet-body');
  final _footerKey = GlobalKey(debugLabel: 'app-sheet-footer');

  double? _bodyHeight;
  double? _footerHeight;

  void _measuredBody(Size size) {
    if (mounted && _bodyHeight != size.height) setState(() => _bodyHeight = size.height);
  }

  void _measuredFooter(Size size) {
    if (mounted && _footerHeight != size.height) setState(() => _footerHeight = size.height);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // The modal keeps the status bar clear (useSafeArea) but leaves the
    // bottom inset to the content: the gesture bar or nav buttons.
    final bottomInset = media.padding.bottom;

    final content = Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxHeight = constraints.maxHeight;
          final hasFooter = widget.footer != null;
          // Measured without the padding below, which depends on pinning, so
          // the decision cannot flip back and forth.
          final pinnedFooterHeight =
              _footerHeight == null ? 0.0 : _footerHeight! + AppSpacing.md + AppSpacing.lg + bottomInset;
          final pinFooter = hasFooter &&
              (!maxHeight.isFinite || pinnedFooterHeight <= maxHeight * AppSheet.maxPinnedFooter);
          final total = (_bodyHeight ?? 0) + (pinFooter ? pinnedFooterHeight : (_footerHeight ?? 0));
          final tall = _bodyHeight != null && maxHeight.isFinite && total > maxHeight * widget.peek;

          final footer = !hasFooter
              ? null
              : Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    pinFooter ? AppSpacing.md : 0,
                    AppSpacing.xl,
                    pinFooter ? AppSpacing.lg + bottomInset : 0,
                  ),
                  child: _MeasureSize(key: _footerKey, onSize: _measuredFooter, child: widget.footer!),
                );

          Widget scroller(ScrollController? controller) => SingleChildScrollView(
                key: const ValueKey('app-sheet-scroll'),
                controller: controller,
                padding: EdgeInsets.fromLTRB(
                  0,
                  0,
                  0,
                  pinFooter ? 0 : AppSpacing.lg + bottomInset,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _MeasureSize(
                      key: _bodyKey,
                      onSize: _measuredBody,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          AppSpacing.xl,
                          0,
                          AppSpacing.xl,
                          hasFooter && !pinFooter ? AppSpacing.xl : 0,
                        ),
                        child: widget.body,
                      ),
                    ),
                    if (footer != null && !pinFooter) footer,
                  ],
                ),
              );

          if (!tall) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(child: scroller(null)),
                if (footer != null && pinFooter) footer,
              ],
            );
          }

          final full = math.min(1.0, math.max(widget.peek, total / maxHeight));
          return DraggableScrollableSheet(
            key: const ValueKey('app-sheet-draggable'),
            expand: false,
            initialChildSize: widget.peek,
            minChildSize: math.min(0.3, widget.peek),
            maxChildSize: full,
            snap: true,
            snapSizes: [if (widget.peek < full) widget.peek],
            builder: (context, controller) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: scroller(controller)),
                if (footer != null && pinFooter) footer,
              ],
            ),
          );
        },
      ),
    );

    // Snack bars from inside the sheet show on the sheet, not behind it on
    // the screen underneath. The transparent scaffold is exactly the sheet's
    // size and lets every tap through to the content.
    return ScaffoldMessenger(
      child: Stack(
        children: [
          content,
          const Positioned.fill(
            child: IgnorePointer(
              child: Scaffold(backgroundColor: Colors.transparent, resizeToAvoidBottomInset: false),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reports its child's laid-out size after the frame.
class _MeasureSize extends SingleChildRenderObjectWidget {
  const _MeasureSize({super.key, required this.onSize, required super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMeasureSize(onSize);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasureSize renderObject) {
    renderObject.onSize = onSize;
  }
}

class _RenderMeasureSize extends RenderProxyBox {
  _RenderMeasureSize(this.onSize);

  ValueChanged<Size> onSize;
  Size? _last;

  @override
  void performLayout() {
    super.performLayout();
    if (size == _last) return;
    _last = size;
    final reported = size;
    WidgetsBinding.instance.addPostFrameCallback((_) => onSize(reported));
  }
}
