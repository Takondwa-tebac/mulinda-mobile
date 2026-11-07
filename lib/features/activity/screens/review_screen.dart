import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/semantic_colors.dart';
import '../../../core/widgets/amount_text.dart';
import '../../../core/widgets/category_icons.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_chip.dart';
import '../data/activity_models.dart';
import '../data/activity_repository.dart';
import '../widgets/category_quick_fix.dart';
import '../widgets/txn_view.dart';
import '../../../shared/plural.dart';
import '../../../core/theme/app_icons.dart';

/// Review queue for transactions auto-recorded from SMS. The user confirms the
/// ones that are right and bulk-deletes (soft) the ones that aren't, and can fix
/// each one's category in place. Each principal shows its fee/levy split.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key, this.highlightId});

  /// Opened from a notification about this transaction: shown first and outlined.
  final String? highlightId;

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  final Set<String> _selected = {};

  /// Rows changed on this screen before the list reloads (optimistic).
  final Map<String, Txn> _local = {};
  bool _busy = false;

  /// The highlighted transaction first, then the rest in their order.
  List<Txn> _highlightFirst(List<Txn> items) {
    final id = widget.highlightId;
    if (id == null) return items;
    final hit = items.where((t) => t.id == id).toList();
    return [...hit, ...items.where((t) => t.id != id)];
  }

  Future<void> _refresh() async {
    _local.clear();
    ref.invalidate(reviewTransactionsProvider);
    await ref.read(reviewTransactionsProvider.future);
  }

  void _toggle(String id) {
    setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id));
  }

  void _selectAll(List<Txn> items) {
    setState(() {
      if (_selected.length == items.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(items.map((t) => t.id));
      }
    });
  }

  Future<void> _run(Future<void> Function(List<String>) action, String done) async {
    if (_selected.isEmpty || _busy) return;
    setState(() => _busy = true);
    final ids = _selected.toList();
    try {
      await action(ids);
      _selected.clear();
      ref.invalidate(reviewTransactionsProvider);
      ref.invalidate(transactionsProvider);
      ref.invalidate(accountsProvider);
      await ref.read(reviewTransactionsProvider.future);
      _snack(done);
    } on ApiException catch (e) {
      _snack(e.displayMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDelete() async {
    final count = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('activity2.deleteSelectedTitle'.tr()),
        content: Text(trCount('activity2.deleteSelectedBody', count)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text('common.cancel'.tr())),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(c).colorScheme.error,
              foregroundColor: Theme.of(c).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(c, true),
            child: Text('common.delete'.tr()),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _run((ids) => ref.read(activityRepositoryProvider).bulkDeleteTransactions(ids), 'activity2.deleted'.tr());
    }
  }

  /// Let the user pick a time today/tomorrow to be reminded to review.
  Future<void> _scheduleReminder() async {
    final granted = await NotificationService.requestReminderPermissions();
    if (!granted) {
      _snack('activity2.enableNotifications'.tr());
      return;
    }
    if (!mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 19, minute: 0),
      helpText: 'activity2.remindAt'.tr(),
    );
    if (time == null) return;

    final now = DateTime.now();
    var when = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    if (when.isBefore(now)) when = when.add(const Duration(days: 1));

    await NotificationService.scheduleReviewReminder(when);
    if (mounted) {
      final day = when.day == now.day ? 'common.today'.tr() : 'common.tomorrow'.tr();
      _snack('activity2.reminderSet'.tr(args: [day, time.format(context)]));
    }
  }

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _fixCategory(Txn t) => openCategoryQuickFix(
    context,
    ref,
    t,
    onLocalUpdate: (u) => mounted ? setState(() => _local[u.id] = u) : null,
    onRevert: (o) => mounted ? setState(() => _local.remove(o.id)) : null,
  );

  @override
  Widget build(BuildContext context) {
    final review = ref.watch(reviewTransactionsProvider);
    // A fresh list from the server replaces any local edits.
    ref.listen(reviewTransactionsProvider, (_, next) {
      if (next.hasValue && !next.isLoading) _local.clear();
    });

    return Scaffold(
      appBar: AppBar(
        title: Text('activity2.reviewTitle'.tr()),
        actions: [
          IconButton(
            tooltip: 'activity2.remindMe'.tr(),
            onPressed: _scheduleReminder,
            icon: const Icon(Icons.alarm_add_outlined),
          ),
          review.maybeWhen(
            data: (items) => items.isEmpty
                ? const SizedBox.shrink()
                : TextButton(
                    onPressed: () => _selectAll(items),
                    child: Text(
                      _selected.length == items.length ? 'activity2.selectNone'.tr() : 'activity2.selectAll'.tr(),
                    ),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: review.when(
          loading: () => const SkeletonList(count: 6),
          error: (_, _) => ScrollFill(
            child: ErrorRetry(
              message: 'activity2.reviewLoadError'.tr(),
              onRetry: () => ref.invalidate(reviewTransactionsProvider),
            ),
          ),
          data: (items) {
            if (items.isEmpty) {
              return ScrollFill(
                child: EmptyState(
                  icon: Icons.verified_outlined,
                  title: 'activity2.reviewEmptyTitle'.tr(),
                  body: 'activity2.reviewEmptyBody'.tr(),
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 120),
              itemCount: items.length,
              itemBuilder: (_, i) {
                final ordered = _highlightFirst(items);
                final t = _local[ordered[i].id] ?? ordered[i];
                return _ReviewCard(
                  highlighted: t.id == widget.highlightId,
                  txn: t,
                  selected: _selected.contains(t.id),
                  onToggle: () => _toggle(t.id),
                  onOpen: () => context.push(Routes.transactionById(t.id)),
                  onFixCategory: t.type == 'transfer' ? null : () => _fixCategory(t),
                );
              },
            );
          },
        ),
      ),
      bottomNavigationBar: _selected.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _confirmDelete,
                        icon: const Icon(Icons.delete_outline),
                        label: Text('activity2.deleteCount'.tr(args: ['${_selected.length}'])),
                        style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _run(
                                (ids) => ref.read(activityRepositoryProvider).confirmTransactions(ids),
                                'activity2.confirmed'.tr(),
                              ),
                        icon: _busy
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.check),
                        label: Text('activity2.confirmCount'.tr(args: ['${_selected.length}'])),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.txn,
    required this.selected,
    this.highlighted = false,
    required this.onToggle,
    required this.onOpen,
    required this.onFixCategory,
  });

  final Txn txn;
  final bool selected;

  /// The transaction a notification pointed at.
  final bool highlighted;
  final VoidCallback onToggle;
  final VoidCallback onOpen;
  final VoidCallback? onFixCategory;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final direction = txn.isIncome ? MoneyDirection.income : MoneyDirection.expense;
    final title = displayMerchant(txn);
    final meta = [
      if (txn.accountName != null) txn.accountName!,
      if (txn.occurredLocal != null) '${dayHeaderLabel(txn.occurredLocal)} ${timeOfDay(txn.occurredLocal)}',
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: selected
            ? BorderSide(color: scheme.primary, width: 1.5)
            : (highlighted ? BorderSide(color: scheme.secondary, width: 2) : BorderSide.none),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        onLongPress: onToggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: selected,
                    onChanged: (_) => onToggle(),
                    semanticLabel: 'activity2.selectRow'.tr(args: [title]),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                              AmountText(txn.amount, direction: direction),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          if (meta.isNotEmpty) Text(meta, style: TextStyle(fontSize: 12, color: muted)),
                          const SizedBox(height: AppSpacing.xs),
                          Wrap(
                            spacing: AppSpacing.sm,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _CategoryButton(txn: txn, onTap: onFixCategory),
                              if (txn.fromSms) StatusChip(label: txn.sender!, icon: Icons.sms_outlined),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              // Fee / levy split, shown as read-only nested rows.
              for (final child in txn.children)
                Padding(
                  padding: const EdgeInsets.fromLTRB(48, 0, 0, AppSpacing.xs),
                  child: Row(
                    children: [
                      Icon(
                        child.isLevy ? Icons.account_balance_outlined : Icons.receipt_long_outlined,
                        size: 14,
                        color: muted,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          child.isLevy ? 'activity2.levy'.tr() : 'activity2.fee'.tr(),
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ),
                      Text('-${child.amount.formatted}', style: TextStyle(fontSize: 12, color: muted)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The category as a tappable pill: its icon and name, highlighted when it
/// needs a look.
class _CategoryButton extends StatelessWidget {
  const _CategoryButton({required this.txn, required this.onTap});

  final Txn txn;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final needs = txn.needsCategory || txn.categoryId == null;
    final fg = needs ? context.semantic.warning : scheme.onSurface;
    final bg = needs ? context.semantic.warningContainer : scheme.surfaceContainerHigh;
    final label = txn.categoryName ?? 'activity2.addCategory'.tr();
    return Semantics(
      button: onTap != null,
      label: '${'categoryPicker.label'.tr()}: $label',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.chip,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Container(
            padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
            decoration: BoxDecoration(color: bg, borderRadius: AppRadius.chip),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CategoryAvatar(
                  icon: txn.categoryIcon,
                  color: txn.categoryColor,
                  size: 24,
                  fallbackIcon: Icons.help_outline,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: fg),
                ),
                if (txn.hasSuggestedCategory) ...[
                  const SizedBox(width: 4),
                  Icon(AppIcons.suggestion, size: 13, color: fg),
                ],
                if (onTap != null) ...[const SizedBox(width: 2), Icon(Icons.expand_more, size: 16, color: fg)],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
