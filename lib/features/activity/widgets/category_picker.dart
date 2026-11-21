import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../data/activity_models.dart';
import '../data/activity_repository.dart';
import '../../../core/widgets/category_icons.dart';

/// What the user chose in the picker: a category, or none. Returned wrapped so
/// that closing the sheet without choosing (null) is different from choosing none.
class CategoryChoice {
  const CategoryChoice(this.id);

  final String? id;
}

/// The categories that match what was typed, ignoring capitals. Runs on the list
/// already on the phone, so searching never calls the server.
List<Category> filterCategories(List<Category> all, String query, {String? kind, bool Function(Category)? where}) {
  final q = query.trim().toLowerCase();
  return all
      .where((c) => kind == null || c.kind == kind)
      .where((c) => where == null || where(c))
      .where((c) => q.isEmpty || c.name.toLowerCase().contains(q))
      .toList();
}

/// Whether what was typed is worth offering as a new category: something was
/// typed and no category already has exactly that name.
bool canCreateCategory(List<Category> all, String query, {String? kind}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return false;
  return !all.any((c) => (kind == null || c.kind == kind) && c.name.trim().toLowerCase() == q);
}

/// A form field that shows the chosen category (with its icon) and opens the
/// searchable picker. Replaces the plain dropdowns.
class CategoryPickerField extends ConsumerWidget {
  const CategoryPickerField({
    super.key,
    required this.value,
    required this.onChanged,
    this.kind,
    this.createKind = 'expense',
    this.enabled = true,
    this.where,
  });

  final String? value;
  final ValueChanged<String?> onChanged;

  /// Only offer categories of this kind (expense | income); null offers all.
  final String? kind;

  /// The kind a newly created category gets.
  final String createKind;
  final bool enabled;

  /// Only offer categories that pass this test (e.g. spending categories for a budget).
  final bool Function(Category)? where;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];
    final selected = categories.where((c) => c.id == value).firstOrNull;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: !enabled
          ? null
          : () async {
              final choice = await showCategoryPicker(
                context,
                kind: kind,
                createKind: createKind,
                selectedId: value,
                where: where,
              );
              if (choice != null) onChanged(choice.id);
            },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'categoryPicker.label'.tr(),
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        child: Row(
          children: [
            if (selected != null) ...[_CategoryAvatar(category: selected, size: 28), const SizedBox(width: 10)],
            Expanded(
              child: Text(
                selected?.name ?? 'categoryPicker.none'.tr(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: selected == null ? scheme.onSurfaceVariant : null),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<CategoryChoice?> showCategoryPicker(
  BuildContext context, {
  String? kind,
  String createKind = 'expense',
  String? selectedId,
  bool Function(Category)? where,
}) {
  return showModalBottomSheet<CategoryChoice>(
    context: context,
    // Above the shell, so the keyboard inset reaches the sheet and no tab
    // button is drawn over it.
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => _CategorySheet(kind: kind, createKind: createKind, selectedId: selectedId, where: where),
  );
}

/// Height for a tall bottom sheet: up to [fraction] of the space the sheet is
/// given, minus the keyboard. Measured from the sheet's own constraints, never
/// from the screen size, so it is right wherever the sheet is hosted.
double sheetHeight(BoxConstraints box, double keyboard, {double fraction = 0.9}) {
  final room = (box.maxHeight - keyboard).clamp(0.0, double.infinity);
  final wanted = box.maxHeight * fraction;
  return wanted < room ? wanted : room;
}

class _CategorySheet extends StatelessWidget {
  const _CategorySheet({required this.kind, required this.createKind, required this.selectedId, this.where});

  final bool Function(Category)? where;
  final String? kind;
  final String createKind;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return LayoutBuilder(
      builder: (context, box) => Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: SizedBox(
          height: sheetHeight(box, keyboard),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  'categoryPicker.title'.tr(),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Expanded(
                child: CategoryPickerList(
                  kind: kind,
                  createKind: createKind,
                  selectedId: selectedId,
                  where: where,
                  autofocus: true,
                  onSelected: (choice) => Navigator.of(context).pop(choice),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The searchable category list: a search field above one scroll view with the
/// rows and the "create" row, usable inside any sheet. [leading] slivers scroll
/// above the rows (e.g. a suggestion card). Needs a bounded height.
class CategoryPickerList extends ConsumerStatefulWidget {
  const CategoryPickerList({
    super.key,
    required this.onSelected,
    this.kind,
    this.createKind = 'expense',
    this.selectedId,
    this.autofocus = false,
    this.showNone = true,
    this.enabled = true,
    this.where,
    this.leading = const [],
    this.onSearchingChanged,
  });

  final ValueChanged<CategoryChoice> onSelected;
  final bool Function(Category)? where;
  final String? kind;
  final String createKind;
  final String? selectedId;
  final bool autofocus;

  /// Offer "No category" at the top.
  final bool showNone;
  final bool enabled;

  /// Slivers shown before the search field, in the same scroll view.
  final List<Widget> leading;

  /// Called with true while the search field has focus or text.
  final ValueChanged<bool>? onSearchingChanged;

  @override
  ConsumerState<CategoryPickerList> createState() => _CategoryPickerListState();
}

class _CategoryPickerListState extends ConsumerState<CategoryPickerList> {
  final _search = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  bool _creating = false;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_report);
  }

  void _report() {
    final now = _focus.hasFocus || _search.text.trim().isNotEmpty;
    if (now != _searching) {
      _searching = now;
      widget.onSearchingChanged?.call(now);
      _toTop();
    }
  }

  /// Results start at the top: after the content above collapses, or the
  /// query changes, nothing is left hidden under the pinned search field.
  void _toTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients && _scroll.offset != 0) _scroll.jumpTo(0);
    });
  }

  @override
  void dispose() {
    _focus.removeListener(_report);
    _focus.dispose();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _create(String name) async {
    setState(() => _creating = true);
    try {
      final created = await ref
          .read(activityRepositoryProvider)
          .createCategory(name: name.trim(), kind: widget.createKind);
      // Wait for the refreshed list, so the field can show the new category at once.
      ref.invalidate(categoriesProvider);
      await ref.read(categoriesProvider.future);
      if (mounted) widget.onSelected(CategoryChoice(created.id));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.displayMessage)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(categoriesProvider);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final enabled = widget.enabled && !_creating;

    final search = Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: TextField(
        key: const ValueKey('category-search'),
        controller: _search,
        focusNode: _focus,
        autofocus: widget.autofocus,
        textInputAction: TextInputAction.search,
        onChanged: (_) {
          setState(() {});
          _report();
          _toTop();
        },
        decoration: InputDecoration(
          hintText: 'categoryPicker.search'.tr(),
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'common.clear'.tr(),
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(_search.clear);
                    _report();
                  },
                ),
        ),
      ),
    );

    final List<Widget> rows = async.when(
      loading: () => const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ],
      error: (_, _) => [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: Text('categoryPicker.loadError'.tr())),
          ),
        ),
      ],
      data: (all) {
        final matches = filterCategories(all, _search.text, kind: widget.kind, where: widget.where);
        final query = _search.text.trim();
        final offerCreate = canCreateCategory(all, query, kind: widget.kind ?? widget.createKind);
        return [
          SliverList.list(
            children: [
              if (query.isEmpty && widget.showNone)
                ListTile(
                  enabled: enabled,
                  leading: CircleAvatar(
                    backgroundColor: scheme.surfaceContainerHigh,
                    child: Icon(Icons.block, size: 18, color: scheme.onSurfaceVariant),
                  ),
                  title: Text('categoryPicker.none'.tr()),
                  trailing: widget.selectedId == null ? const Icon(Icons.check) : null,
                  onTap: () => widget.onSelected(const CategoryChoice(null)),
                ),
              for (final c in matches)
                ListTile(
                  enabled: enabled,
                  leading: CategoryAvatar(icon: c.icon, color: c.color),
                  title: Text(c.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: c.id == widget.selectedId ? const Icon(Icons.check) : null,
                  onTap: () => widget.onSelected(CategoryChoice(c.id)),
                ),
              if (matches.isEmpty && query.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                  child: Column(
                    children: [
                      Icon(Icons.search_off, size: 40, color: scheme.onSurfaceVariant),
                      const SizedBox(height: 8),
                      Text('categoryPicker.notFound'.tr(), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              if (offerCreate)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: scheme.primaryContainer,
                    child: _creating
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(Icons.add, color: scheme.onPrimaryContainer),
                  ),
                  title: Text(
                    'categoryPicker.createNamed'.tr(args: [query]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text('categoryPicker.createHint'.tr()),
                  enabled: enabled,
                  onTap: () => _create(query),
                ),
            ],
          ),
        ];
      },
    );

    // The search field stays put above the scrolling part, so it is always in
    // reach and focusing it never scrolls the list away.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        search,
        Expanded(
          child: CustomScrollView(
            key: const ValueKey('category-picker-scroll'),
            controller: _scroll,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              ...widget.leading,
              ...rows,
              SliverPadding(
                padding: EdgeInsets.only(bottom: 24 + (keyboard > 0 ? 0 : MediaQuery.paddingOf(context).bottom)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CategoryAvatar extends StatelessWidget {
  const _CategoryAvatar({required this.category, this.size = 40});

  final Category category;
  final double size;

  @override
  Widget build(BuildContext context) => CategoryAvatar(icon: category.icon, color: category.color, size: size);
}
