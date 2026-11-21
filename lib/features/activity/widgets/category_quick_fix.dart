import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/amount_text.dart';
import '../../../core/widgets/category_icons.dart';
import '../../dashboard/data/dashboard_repository.dart';
import '../../plan/data/plan_repository.dart';
import '../data/activity_models.dart';
import '../data/activity_repository.dart';
import 'category_picker.dart';
import 'txn_view.dart';
import '../../../shared/plural.dart';

/// What the user chose in the quick-fix sheet.
class QuickFixChoice {
  const QuickFixChoice.confirm({required this.applyToSimilar}) : confirm = true, categoryId = null;

  const QuickFixChoice.pick(this.categoryId, {required this.applyToSimilar}) : confirm = false;

  /// "Yes, correct": keep the suggested category.
  final bool confirm;
  final String? categoryId;
  final bool applyToSimilar;
}

/// The bottom sheet: the suggested category with a one-tap "Yes, correct",
/// an "apply to all from this merchant" switch, and the searchable category list
/// (picking one saves immediately).
class CategoryQuickFixSheet extends StatefulWidget {
  const CategoryQuickFixSheet({super.key, required this.txn});

  final Txn txn;

  @override
  State<CategoryQuickFixSheet> createState() => _CategoryQuickFixSheetState();
}

class _CategoryQuickFixSheetState extends State<CategoryQuickFixSheet> {
  bool _applyToSimilar = false;

  /// The search field has focus or text: the suggestion card and the switch
  /// step aside so the results get the room above the keyboard.
  bool _searching = false;

  Txn get txn => widget.txn;

  /// A real merchant name; bank references never get "apply to all".
  String? get _merchant => cleanMerchant(txn);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final kind = txn.isIncome ? 'income' : 'expense';
    final suggestion = txn.categoryId != null && txn.needsCategory;

    Widget collapsible(Widget child) => SliverToBoxAdapter(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: _searching ? const SizedBox(width: double.infinity) : child,
      ),
    );

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'activity2.quickFixTitle'.tr(),
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  displayMerchant(txn),
                  key: const ValueKey('quick-fix-merchant'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          AmountText(txn.amount, direction: txn.isIncome ? MoneyDirection.income : MoneyDirection.expense),
        ],
      ),
    );

    final card = Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: AppRadius.card),
        // The suggestion gets the full width and the button sits below it, so
        // long category names are never cut short.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CategoryAvatar(icon: txn.categoryIcon, color: txn.categoryColor),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('activity2.weThink'.tr(), style: TextStyle(fontSize: 12, color: scheme.onPrimaryContainer)),
                      Text(
                        txn.categoryName ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              key: const ValueKey('quick-fix-confirm'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSpacing.minTouch)),
              onPressed: () => Navigator.of(context).pop(QuickFixChoice.confirm(applyToSimilar: _applyToSimilar)),
              icon: const Icon(Icons.check, size: 18),
              label: Text('activity2.yesCorrect'.tr()),
            ),
          ],
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, box) => Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: SizedBox(
          height: sheetHeight(box, keyboard),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Pinned: always visible, even with the keyboard open.
              header,
              Expanded(
                child: CategoryPickerList(
                  kind: kind,
                  createKind: kind,
                  selectedId: txn.categoryId,
                  showNone: false,
                  onSearchingChanged: (v) => setState(() => _searching = v),
                  onSelected: (choice) =>
                      Navigator.of(context).pop(QuickFixChoice.pick(choice.id, applyToSimilar: _applyToSimilar)),
                  leading: [
                    if (suggestion) collapsible(card),
                    if (_merchant != null)
                      collapsible(
                        SwitchListTile(
                          key: const ValueKey('quick-fix-similar'),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                          value: _applyToSimilar,
                          onChanged: (v) => setState(() => _applyToSimilar = v),
                          title: Text(
                            'activity2.applyToMerchant'.tr(args: [_merchant!]),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text('activity2.applyToMerchantSub'.tr()),
                        ),
                      ),
                    collapsible(
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, AppSpacing.sm, 20, AppSpacing.sm),
                        child: Text(
                          suggestion ? 'activity2.orChooseAnother'.tr() : 'activity2.chooseCategory'.tr(),
                          style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
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
    );
  }
}

/// Opens the quick-fix sheet for [txn] and saves the choice:
/// * "Yes, correct" → `POST /transactions/confirm` (or the category endpoint
///   with `apply_to_similar` when the switch is on);
/// * a picked category → `POST /transactions/{id}/category`.
///
/// [onLocalUpdate] is called first with the optimistic row and again with the
/// server's row; [onRevert] with the original row when saving fails. Returns
/// the saved row, or null when dismissed or failed.
Future<Txn?> openCategoryQuickFix(
  BuildContext context,
  WidgetRef ref,
  Txn txn, {
  void Function(Txn updated)? onLocalUpdate,
  void Function(Txn original)? onRevert,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final choice = await showModalBottomSheet<QuickFixChoice>(
    context: context,
    // Above the shell: the keyboard inset reaches the sheet and no tab button
    // is drawn over it.
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => CategoryQuickFixSheet(txn: txn),
  );
  if (choice == null) return null;
  final categories = ref.read(categoriesProvider).valueOrNull ?? const <Category>[];
  final repo = ref.read(activityRepositoryProvider);

  final targetId = choice.confirm ? txn.categoryId : choice.categoryId;
  final target =
      categories.where((c) => c.id == targetId).firstOrNull ??
      (targetId == txn.categoryId && targetId != null
          ? Category(
              id: targetId,
              name: txn.categoryName ?? '',
              kind: txn.isIncome ? 'income' : 'expense',
              icon: txn.categoryIcon,
              color: txn.categoryColor,
            )
          : null);

  final optimistic = txn.withCategory(target);
  onLocalUpdate?.call(optimistic);

  void snack(String text) => messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  try {
    Txn saved = optimistic;
    var similar = 0;
    if (choice.confirm && !choice.applyToSimilar) {
      await repo.confirmTransactions([txn.id]);
    } else {
      final result = await repo.setCategory(txn.id, targetId, applyToSimilar: choice.applyToSimilar);
      saved = result.txn;
      similar = result.similarUpdated;
    }
    onLocalUpdate?.call(saved);

    ref
      ..invalidate(dashboardProvider)
      ..invalidate(reviewTransactionsProvider)
      ..invalidate(transactionDetailProvider(txn.id))
      ..invalidate(budgetsProvider);
    // Other rows changed on the server too: reload the list.
    if (similar > 0) ref.invalidate(transactionsProvider);

    snack(
      similar > 0
          ? trCount('activity2.updatedSimilar', similar)
          : (choice.confirm ? 'activity2.categoryConfirmed'.tr() : 'activity2.categorySaved'.tr()),
    );
    return saved;
  } on ApiException catch (e) {
    onRevert?.call(txn);
    snack(e.displayMessage);
    return null;
  } catch (_) {
    onRevert?.call(txn);
    snack('activity2.categorySaveFailed'.tr());
    return null;
  }
}
