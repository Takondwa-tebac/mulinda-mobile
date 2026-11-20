import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'category_icons.dart';

/// An icon and colour picked for a category. Both null means "let Mulinda
/// choose" (the server picks ones that fit the name).
class CategoryStyleChoice {
  const CategoryStyleChoice({this.icon, this.color});

  final String? icon;
  final String? color;

  bool get isAuto => icon == null && color == null;
}

/// Ask for an icon and colour for the category [name]. Returns null when
/// dismissed. With [allowAuto] the sheet starts on "Let Mulinda choose", so
/// picking a look stays optional.
Future<CategoryStyleChoice?> showCategoryStyleSheet(
  BuildContext context, {
  required String name,
  String? icon,
  String? color,
  bool allowAuto = true,
}) {
  return showModalBottomSheet<CategoryStyleChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => CategoryStyleSheet(name: name, icon: icon, color: color, allowAuto: allowAuto),
  );
}

class CategoryStyleSheet extends StatefulWidget {
  const CategoryStyleSheet({super.key, required this.name, this.icon, this.color, this.allowAuto = true});

  final String name;
  final String? icon;
  final String? color;
  final bool allowAuto;

  @override
  State<CategoryStyleSheet> createState() => _CategoryStyleSheetState();
}

class _CategoryStyleSheetState extends State<CategoryStyleSheet> {
  late String? _icon = widget.icon ?? (widget.allowAuto ? null : categoryIconChoices.first);
  late String? _color = widget.color ?? (widget.allowAuto ? null : categoryColorChoices.first);

  bool get _auto => _icon == null && _color == null;

  void _pickIcon(String icon) => setState(() {
        _icon = icon;
        _color ??= categoryColorChoices.first;
      });

  void _pickColor(String color) => setState(() {
        _color = color;
        _icon ??= 'category';
      });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final previewColor = parseHexColor(_color) ?? scheme.primary;
    final height = (media.size.height * 0.8).clamp(0.0, media.size.height - media.padding.top - 56);

    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: previewColor.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: Icon(
                    // Until an icon is picked, a plain palette (the server
                    // picks the real icon from the name).
                    _auto ? Icons.palette_outlined : categoryIcon(_icon),
                    color: previewColor,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('categoryStyle.title'.tr(), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                      Text(widget.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              children: [
                if (widget.allowAuto)
                  Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    color: _auto ? scheme.primaryContainer : scheme.surfaceContainerHigh,
                    child: ListTile(
                      key: const ValueKey('category-style-auto'),
                      leading: const Icon(Icons.tune),
                      title: Text('categoryStyle.auto'.tr()),
                      subtitle: Text('categoryStyle.autoHint'.tr()),
                      trailing: _auto ? const Icon(Icons.check) : null,
                      onTap: () => setState(() {
                        _icon = null;
                        _color = null;
                      }),
                    ),
                  ),
                Text('categoryStyle.icon'.tr(), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final name in categoryIconChoices)
                      _Choice(
                        key: ValueKey('category-icon-$name'),
                        selected: _icon == name,
                        onTap: () => _pickIcon(name),
                        child: Icon(categoryIcon(name), color: _icon == name ? previewColor : scheme.onSurfaceVariant),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Text('categoryStyle.color'.tr(), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final hex in categoryColorChoices)
                      _Choice(
                        key: ValueKey('category-color-$hex'),
                        selected: _color == hex,
                        onTap: () => _pickColor(hex),
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(color: parseHexColor(hex), shape: BoxShape.circle),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('category-style-save'),
                  onPressed: () => Navigator.of(context).pop(CategoryStyleChoice(icon: _icon, color: _color)),
                  child: Text('categoryStyle.save'.tr()),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({super.key, required this.selected, required this.onTap, required this.child});

  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.surfaceContainerHigh,
          border: Border.all(color: selected ? scheme.primary : Colors.transparent, width: 2),
        ),
        child: child,
      ),
    );
  }
}
