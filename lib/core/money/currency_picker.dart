import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'currencies.dart';

/// Bottom-sheet currency chooser: each row shows the flag, code, and name.
/// Returns the selected ISO code, or null if dismissed.
Future<String?> showCurrencyPicker(BuildContext context, {String? selected}) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (_, controller) => ListView(
        controller: controller,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text('currency.select'.tr(),
                style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final c in kCurrencies)
            ListTile(
              leading: Text(c.flag, style: const TextStyle(fontSize: 26)),
              title: Text('${c.code} · ${c.symbol}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(c.name),
              trailing: c.code == selected ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(context).pop(c.code),
            ),
        ],
      ),
    ),
  );
}

/// A tappable form field that shows the chosen currency (flag + code) and opens
/// the picker. Use in forms where a currency must be selected.
class CurrencyField extends StatelessWidget {
  const CurrencyField({
    super.key,
    required this.value,
    required this.label,
    required this.onChanged,
  });

  final String value;
  final String label;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final info = currencyInfo(value);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final picked = await showCurrencyPicker(context, selected: value);
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        child: Row(
          children: [
            Text(info.flag, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Text('${info.code} · ${info.name}'),
          ],
        ),
      ),
    );
  }
}
