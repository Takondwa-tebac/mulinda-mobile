import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../money/money.dart';
import '../theme/app_spacing.dart';
import 'amount_text.dart';
import 'category_icons.dart';
import 'status_chip.dart';
import '../theme/app_icons.dart';

/// What a [TransactionTile] shows. Kept free of feature models so Home
/// (dashboard rows) and Activity (full transactions) can both use it.
class TransactionTileData {
  const TransactionTileData({
    required this.id,
    required this.title,
    required this.amount,
    required this.type,
    this.categoryName,
    this.categoryIcon,
    this.categoryColor,
    this.meta,
    this.needsAttention = false,
    this.pending = false,
    this.needsReview = false,
    this.notSpending = false,
  });

  final String id;
  final String title;
  final Money amount;

  /// income | expense | transfer
  final String type;
  final String? categoryName;
  final String? categoryIcon;
  final String? categoryColor;

  /// The time or date shown after the category ("14:05", "3 Nov").
  final String? meta;

  /// The category is a guess or missing: shows the "Confirm category" chip.
  final bool needsAttention;

  /// Saved offline, waiting to sync.
  final bool pending;

  /// Auto-recorded and waiting for the user's review.
  final bool needsReview;

  /// An expense in a category that is not spending (e.g. moving your own
  /// money): drawn in the neutral colour with a "Not counted as spending" label.
  final bool notSpending;

  MoneyDirection get direction => notSpending
      ? MoneyDirection.neutral
      : switch (type) {
          'income' => MoneyDirection.income,
          'expense' => MoneyDirection.expense,
          _ => MoneyDirection.neutral,
        };
}

/// One transaction in a list: category icon in a tinted circle, merchant,
/// "category · time", signed amount, a subtle "Confirm category" chip when the
/// category needs a look, and a sync marker for offline rows.
class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.data,
    this.onTap,
    this.onLongPress,
    this.onConfirmCategory,
    this.dense = false,
  });

  final TransactionTileData data;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Tapping the "Confirm category" chip. The chip is shown (non-tappable)
  /// even without it, so the state is still visible.
  final VoidCallback? onConfirmCategory;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final d = data;
    final categoryLabel =
        d.categoryName ?? (d.type == 'transfer' ? 'activity2.transfer'.tr() : 'activity2.uncategorised'.tr());
    final subtitle = [categoryLabel, if (d.meta != null && d.meta!.isNotEmpty) d.meta!].join(' · ');
    final fallback = switch (d.type) {
      'income' => Icons.south_west,
      'transfer' => Icons.swap_horiz,
      _ => Icons.north_east,
    };

    return Semantics(
      button: onTap != null,
      label:
          '${d.title}, $subtitle, ${AmountText.label(d.amount, d.direction)}'
          '${d.needsAttention ? ', ${'activity2.confirmCategory'.tr()}' : ''}'
          '${d.pending ? ', ${'activity2.waitingToSync'.tr()}' : ''}',
      excludeSemantics: onConfirmCategory == null,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: dense ? AppSpacing.xs : AppSpacing.sm),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CategoryAvatar(icon: d.categoryIcon, color: d.categoryColor, fallbackIcon: fallback),
                    if (d.pending)
                      Positioned(
                        right: -4,
                        bottom: -4,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(color: scheme.surface, shape: BoxShape.circle),
                          child: Icon(Icons.cloud_upload_outlined, size: 14, color: scheme.onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      // The category gives way before the time does; on a very narrow row
                      // the two share one line that ends in "...".
                      LayoutBuilder(
                        builder: (context, box) => box.maxWidth < 140
                            ? Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                              )
                            : Row(
                                children: [
                                  Flexible(
                                    flex: 3,
                                    child: Text(
                                      categoryLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                                    ),
                                  ),
                                  if (d.meta != null && d.meta!.isNotEmpty)
                                    // A clock time is short and always shown in full; a longer label may shrink.
                                    d.meta!.length <= 8
                                        ? _meta(d.meta!, theme)
                                        : Flexible(child: _meta(d.meta!, theme)),
                                ],
                              ),
                      ),
                      if (d.notSpending)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                          child: StatusChip(
                            key: const ValueKey('not-spending-label'),
                            label: 'activity2.notSpending'.tr(),
                            icon: Icons.swap_horiz,
                          ),
                        ),
                      if (d.needsAttention)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: StatusChip(
                            key: const ValueKey('confirm-category-chip'),
                            label: d.categoryName == null
                                ? 'activity2.addCategory'.tr()
                                : 'activity2.confirmCategory'.tr(),
                            icon: AppIcons.suggestion,
                            tone: StatusTone.warning,
                            onTap: onConfirmCategory,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    AmountText(d.amount, direction: d.direction),
                    if (d.needsReview)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xxs),
                        child: Text(
                          'activity2.toReview'.tr(),
                          style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _meta(String meta, ThemeData theme) => Text(
  ' · $meta',
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
);
