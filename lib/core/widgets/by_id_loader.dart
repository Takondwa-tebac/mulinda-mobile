import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../network/api_exception.dart';
import 'error_retry.dart';
import 'skeleton.dart';

/// The item no longer exists or is not this user's (HTTP 404 / 403).
bool isGoneError(Object? e) => e is ApiException && (e.statusCode == 404 || e.statusCode == 403);

/// Tell the user the item is gone and go to its list instead.
void leaveForList(BuildContext context, String listRoute) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('common.itemGone'.tr())));
    GoRouter.of(context).go(listRoute);
  });
}

/// Shows a detail screen for an item opened by id (from a notification or a
/// link): uses [initial] when the caller already has the item, otherwise
/// fetches it. While loading it shows a skeleton; a deleted or forbidden item
/// sends the user to [listRoute] with a short message; other errors offer a
/// retry.
class ByIdLoader<T> extends ConsumerStatefulWidget {
  const ByIdLoader({
    super.key,
    required this.id,
    required this.load,
    required this.builder,
    required this.listRoute,
    required this.title,
    this.initial,
  });

  final String id;
  final T? initial;
  final Future<T> Function(WidgetRef ref, String id) load;
  final Widget Function(T item) builder;
  final String listRoute;
  final String title;

  @override
  ConsumerState<ByIdLoader<T>> createState() => _ByIdLoaderState<T>();
}

class _ByIdLoaderState<T> extends ConsumerState<ByIdLoader<T>> {
  T? _item;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _item = widget.initial;
    if (_item == null) _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _error = null);
    try {
      final item = await widget.load(ref, widget.id);
      if (mounted) setState(() => _item = item);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
      if (isGoneError(e)) leaveForList(context, widget.listRoute);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    if (item != null) return widget.builder(item);
    final error = _error;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: error == null || isGoneError(error)
          ? const SkeletonList(count: 5, header: true)
          : Center(
              child: ErrorRetry(message: error is ApiException ? error.displayMessage : null, onRetry: _fetch),
            ),
    );
  }
}
