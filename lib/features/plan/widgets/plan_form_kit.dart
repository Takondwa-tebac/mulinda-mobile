import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Shared form helpers for the Plan create/edit screens.

Widget pkText({
  required TextEditingController controller,
  required String label,
  String? Function(String?)? validator,
  TextInputType? keyboard,
  int maxLines = 1,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controller,
      keyboardType: keyboard,
      maxLines: maxLines,
      validator: validator,
      decoration: InputDecoration(labelText: label),
    ),
  );
}

Widget pkMoney({
  required TextEditingController controller,
  required String label,
  bool required = true,
}) {
  return pkText(
    controller: controller,
    label: label,
    keyboard: const TextInputType.numberWithOptions(decimal: true),
    validator: required
        ? (v) {
            final n = double.tryParse((v ?? '').trim());
            if (n == null || n <= 0) return 'auth.required'.tr();
            return null;
          }
        : null,
  );
}

Widget pkDropdown<T>({
  required T value,
  required String label,
  required List<(T, String)> entries,
  required ValueChanged<T> onChanged,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: DropdownButtonFormField<T>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: entries.map((e) => DropdownMenuItem(value: e.$1, child: Text(e.$2))).toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    ),
  );
}

Widget pkDate({
  required BuildContext context,
  required String label,
  required DateTime? value,
  required ValueChanged<DateTime> onPick,
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: firstDate ?? DateTime(2015),
          lastDate: lastDate ?? DateTime(2100),
        );
        if (picked != null) onPick(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text(value == null ? '—' : value.toIso8601String().split('T').first),
      ),
    ),
  );
}

Widget pkSubmit({required bool loading, required String label, required VoidCallback? onPressed}) {
  return Builder(builder: (context) {
    return FilledButton(
      onPressed: loading ? null : onPressed,
      child: loading
          ? SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: Theme.of(context).colorScheme.onPrimary),
            )
          : Text(label),
    );
  });
}

String? dateToApi(DateTime? d) => d?.toIso8601String().split('T').first;
DateTime? apiToDate(String? s) => (s == null || s.isEmpty) ? null : DateTime.tryParse(s);
