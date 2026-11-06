import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// [date] moved inside `[first, last]` (date-only comparison), so a date
/// picker never receives an initial date outside its range (which asserts).
DateTime clampDate(DateTime date, DateTime first, DateTime last) {
  final d = DateUtils.dateOnly(date);
  final f = DateUtils.dateOnly(first);
  final l = DateUtils.dateOnly(last);
  if (d.isBefore(f)) return f;
  if (d.isAfter(l)) return l;
  return d;
}

/// `5 Nov 2026`, with the month name from the translations.
String formatDay(DateTime d) => '${d.day} ${'common.monthShort.${d.month}'.tr()} ${d.year}';

/// A tappable date field: a read-only text field with a calendar icon that
/// opens the date picker. It has real ink, focus and button semantics, shows
/// "Choose a date" when empty, can be cleared, and always opens the picker on a
/// date inside `[firstDate, lastDate]`.
class AppDateField extends StatefulWidget {
  const AppDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
    this.required = false,
    this.clearable = false,
    this.enabled = true,
  });

  final String label;
  final DateTime? value;

  /// Called with the picked date, or null when cleared.
  final ValueChanged<DateTime?> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final bool required;
  final bool clearable;
  final bool enabled;

  @override
  State<AppDateField> createState() => _AppDateFieldState();
}

class _AppDateFieldState extends State<AppDateField> {
  late final _text = TextEditingController(text: _label(widget.value));

  String _label(DateTime? d) => d == null ? '' : formatDay(d);

  @override
  void didUpdateWidget(covariant AppDateField old) {
    super.didUpdateWidget(old);
    final next = _label(widget.value);
    if (_text.text != next) _text.text = next;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Month names follow the language.
    _text.text = _label(widget.value);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final first = widget.firstDate ?? DateTime(2015);
    final last = widget.lastDate ?? DateTime(2100);
    final picked = await showDatePicker(
      context: context,
      initialDate: clampDate(widget.value ?? DateTime.now(), first, last),
      firstDate: first,
      lastDate: last,
    );
    if (picked != null) widget.onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final canClear = widget.clearable && widget.value != null && widget.enabled;
    return TextFormField(
      controller: _text,
      readOnly: true,
      enabled: widget.enabled,
      onTap: _pick,
      validator: widget.required ? (_) => widget.value == null ? 'auth.required'.tr() : null : null,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: 'common.chooseDate'.tr(),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        prefixIcon: const Icon(Icons.calendar_today_outlined),
        suffixIcon: canClear
            ? IconButton(
                tooltip: 'common.clear'.tr(),
                icon: const Icon(Icons.close),
                onPressed: () => widget.onChanged(null),
              )
            : null,
      ),
    );
  }
}
