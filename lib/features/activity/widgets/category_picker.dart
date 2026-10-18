import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../data/activity_models.dart';
import '../data/activity_repository.dart';
import 'category_icons.dart';

/// What the user chose in the picker: a category, or none. Returned wrapped so
/// that closing the sheet without choosing (null) is different from choosing none.
class CategoryChoice {
  const CategoryChoice(this.id);

  final String? id;
}

/// The categories that match what was typed, ignoring capitals. Runs on the list
/// already on the phone, so searching never calls the server.
List<Category> filterCategories(List<Category> all, String query, {String? kind}) {
  final q = query.trim().toLowerCase();
  return all
      .where((c) => kind == null || c.kind == kind)
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
  });

  final String? value;
  final ValueChanged<String?> onChanged;

  /// Only offer categories of this kind (expense | income); null offers all.
  final String? kind;

  /// The kind a newly created category gets.
  final String createKind;
  final bool enabled;

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
              final choice = await showCategoryPicker(context, kind: kind, createKind: createKind, selectedId: value);
              if (choice != null) onChanged(choice.id);
            },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'categoryPicker.label'.tr(),
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        child: Row(
          children: [
            if (selected != null) ...[
              _CategoryAvatar(category: selected, size: 28),
              const SizedBox(width: 10),
            ],
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
}) {
  return showModalBottomSheet<CategoryChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => _CategorySheet(kind: kind, createKind: createKind, selectedId: selectedId),
  );
}

class _CategorySheet extends ConsumerStatefulWidget {
  const _CategorySheet({required this.kind, required this.createKind, required this.selectedId});

  final String? kind;
  final String createKind;
  final String? selectedId;

  @override
  ConsumerState<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends ConsumerState<_CategorySheet> {
  final _search = TextEditingController();
  bool _creating = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _create(String name) async {
    setState(() => _creating = true);
    try {
      final created = await ref.read(activityRepositoryProvider).createCategory(name: name.trim(), kind: widget.createKind);
      // Wait for the refreshed list, so the field can show the new category at once.
      ref.invalidate(categoriesProvider);
      await ref.read(categoriesProvider.future);
      if (mounted) Navigator.of(context).pop(CategoryChoice(created.id));
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
    final media = MediaQuery.of(context);
    // Tall, but never taller than what the keyboard and the status bar leave free.
    final height = (media.size.height * 0.85).clamp(0.0, media.size.height - media.viewInsets.bottom - media.padding.top - 56);

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('categoryPicker.title'.tr(), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _search,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'categoryPicker.search'.tr(),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => setState(_search.clear),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: async.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => Center(child: Text('categoryPicker.loadError'.tr())),
                data: (all) {
                  final matches = filterCategories(all, _search.text, kind: widget.kind);
                  final query = _search.text.trim();
                  final offerCreate = canCreateCategory(all, query, kind: widget.kind ?? widget.createKind);

                  return ListView(
                    padding: EdgeInsets.only(bottom: 24 + (media.viewInsets.bottom > 0 ? 0 : media.padding.bottom)),
                    children: [
                      if (query.isEmpty)
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: scheme.surfaceContainerHigh,
                            child: Icon(Icons.block, size: 18, color: scheme.onSurfaceVariant),
                          ),
                          title: Text('categoryPicker.none'.tr()),
                          trailing: widget.selectedId == null ? const Icon(Icons.check) : null,
                          onTap: () => Navigator.of(context).pop(const CategoryChoice(null)),
                        ),
                      for (final c in matches)
                        ListTile(
                          leading: _CategoryAvatar(category: c),
                          title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: c.id == widget.selectedId ? const Icon(Icons.check) : null,
                          onTap: () => Navigator.of(context).pop(CategoryChoice(c.id)),
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
                          title: Text('categoryPicker.createNamed'.tr(args: [query]), maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text('categoryPicker.createHint'.tr()),
                          enabled: !_creating,
                          onTap: () => _create(query),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryAvatar extends StatelessWidget {
  const _CategoryAvatar({required this.category, this.size = 40});

  final Category category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = parseHexColor(category.color) ?? scheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
      child: Icon(categoryIcon(category.icon), color: color, size: size * 0.55),
    );
  }
}
