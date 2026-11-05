import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Whether the floating action button should be showing. Hidden while the
/// user scrolls, shown again shortly after scrolling stops.
class ScrollAwareFabController extends ChangeNotifier {
  ScrollAwareFabController({this.showDelay = const Duration(milliseconds: 650)});

  /// How long after scrolling stops before the button comes back.
  final Duration showDelay;

  bool _visible = true;
  Timer? _timer;

  bool get visible => _visible;

  void hide() {
    _timer?.cancel();
    if (_visible) {
      _visible = false;
      notifyListeners();
    }
  }

  /// Show now (cancels a pending delayed show).
  void show() {
    _timer?.cancel();
    if (!_visible) {
      _visible = true;
      notifyListeners();
    }
  }

  /// Show after [showDelay], unless scrolling starts again first.
  void showLater() {
    _timer?.cancel();
    if (_visible) return;
    _timer = Timer(showDelay, show);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// Listens to the vertical scrolling below it and drives the
/// [ScrollAwareFab]s below it. Wrap a whole `Scaffold` with it: the Scaffold's
/// `floatingActionButton` is not inside `body`, but both are below this.
class ScrollAwareFabScope extends StatefulWidget {
  const ScrollAwareFabScope({super.key, required this.child, this.controller, this.threshold = 8});

  final Widget child;

  /// Supply one to show/hide the button from outside (e.g. on tab switches).
  final ScrollAwareFabController? controller;

  /// How far (logical px) a drag must move before the button hides, so small
  /// jitters do not toggle it.
  final double threshold;

  /// The nearest scope's controller, or null when there is none.
  static ScrollAwareFabController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_FabScope>()?.notifier;

  @override
  State<ScrollAwareFabScope> createState() => _ScrollAwareFabScopeState();
}

class _ScrollAwareFabScopeState extends State<ScrollAwareFabScope> {
  ScrollAwareFabController? _own;
  ScrollAwareFabController get _controller => widget.controller ?? (_own ??= ScrollAwareFabController());

  /// Where the current drag started; null when no user drag is in progress.
  double? _origin;

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    final m = n.metrics;
    // Horizontal strips (filter chips, account cards) never hide the button.
    if (m.axis != Axis.vertical) return false;

    final atTop = m.pixels <= m.minScrollExtent;
    final scrollable = m.maxScrollExtent > m.minScrollExtent;
    if (!scrollable) {
      _origin = null;
      _controller.show();
      return false;
    }

    if (n is ScrollStartNotification) {
      // Only drags by the user count; programmatic scrolls (animateTo,
      // nested lists moved by code) carry no drag details.
      _origin = n.dragDetails != null ? m.pixels : null;
    } else if (n is ScrollUpdateNotification) {
      if (atTop) {
        _controller.show();
      } else if (n.dragDetails != null) {
        _origin ??= m.pixels;
        if ((m.pixels - _origin!).abs() > widget.threshold) _controller.hide();
      }
    } else if (n is UserScrollNotification && n.direction == ScrollDirection.idle) {
      _origin = null;
      atTop ? _controller.show() : _controller.showLater();
    } else if (n is ScrollEndNotification) {
      _origin = null;
      atTop ? _controller.show() : _controller.showLater();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: _FabScope(notifier: _controller, child: widget.child),
    );
  }
}

class _FabScope extends InheritedNotifier<ScrollAwareFabController> {
  const _FabScope({required super.notifier, required super.child});
}

/// A floating action button that slides down and fades out while the user
/// scrolls (see [ScrollAwareFabScope]) and comes back when scrolling pauses.
/// With a screen reader on it always stays; with reduced motion it switches
/// instantly; while hidden it cannot be tapped or focused.
class ScrollAwareFab extends StatelessWidget {
  const ScrollAwareFab({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final controller = ScrollAwareFabScope.maybeOf(context);
    final media = MediaQuery.maybeOf(context);
    final screenReader = media?.accessibleNavigation ?? false;
    final reduced = media?.disableAnimations ?? false;
    final visible = screenReader || (controller?.visible ?? true);
    final duration = reduced ? Duration.zero : Duration(milliseconds: visible ? 250 : 200);

    return IgnorePointer(
      ignoring: !visible,
      child: ExcludeSemantics(
        excluding: !visible,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, 1.5),
          duration: duration,
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: duration,
            curve: Curves.easeOutCubic,
            child: child,
          ),
        ),
      ),
    );
  }
}
