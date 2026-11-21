import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// A country a phone number can come from: ISO 3166 code and dialling code.
/// The display name is a translation under `countries.<iso>`.
class Country {
  const Country(this.iso, this.dialCode);

  /// Two-letter ISO code, e.g. `MW`.
  final String iso;

  /// Digits only, without the plus, e.g. `265`.
  final String dialCode;

  String get name => 'countries.$iso'.tr();
  String get dialLabel => '+$dialCode';

  @override
  bool operator ==(Object other) => other is Country && other.iso == iso;

  @override
  int get hashCode => iso.hashCode;
}

/// Malawi, the default and the country Mulinda reads messages for best.
const malawi = Country('MW', '265');

/// The curated list shown in the picker: Malawi first, then the region, then
/// the two most common diaspora countries.
const kCountries = <Country>[
  malawi,
  Country('ZM', '260'),
  Country('MZ', '258'),
  Country('TZ', '255'),
  Country('ZW', '263'),
  Country('ZA', '27'),
  Country('KE', '254'),
  Country('UG', '256'),
  Country('BW', '267'),
  Country('GB', '44'),
  Country('US', '1'),
];

/// Countries matching [query] by name (any part, any case), ISO code, or
/// dialling code (`265`, `+265`). An empty query returns everything.
/// [nameOf] gives the display name (the translation, by default).
List<Country> filterCountries(String query, {List<Country> from = kCountries, String Function(Country)? nameOf}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return from;
  final digits = q.replaceAll(RegExp(r'\D'), '');
  final name = nameOf ?? (Country c) => c.name;
  return from.where((c) {
    if (digits.isNotEmpty && digits == q.replaceAll('+', '').trim()) {
      return c.dialCode.startsWith(digits);
    }
    return name(c).toLowerCase().contains(q) || c.iso.toLowerCase() == q;
  }).toList();
}

/// The full international number: the dialling code plus the local number
/// without spaces, punctuation or a leading trunk zero (`0991 23 45 67` in
/// Malawi becomes `+265991234567`).
String internationalNumber(Country country, String local) {
  final digits = local.replaceAll(RegExp(r'\D'), '').replaceFirst(RegExp(r'^0+'), '');
  return '+${country.dialCode}$digits';
}

/// A small drawn flag (no emoji, no image assets). Simplified to the main
/// bands of each flag so it reads at 20 to 28 px.
class CountryFlag extends StatelessWidget {
  const CountryFlag(this.country, {super.key, this.width = 24});

  final Country country;
  final double width;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        width: width,
        height: width * 2 / 3,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, width: 0.5),
            borderRadius: BorderRadius.circular(3),
          ),
          child: CustomPaint(painter: _FlagPainter(country.iso)),
        ),
      ),
    );
  }
}

// Flag colours are part of each flag, not the app theme.
const _black = Color(0xFF000000);
const _white = Color(0xFFFFFFFF);
const _red = Color(0xFFCE1126);
const _green = Color(0xFF339E35);
const _yellow = Color(0xFFFCD116);

class _FlagPainter extends CustomPainter {
  _FlagPainter(this.iso);

  final String iso;

  void _bands(Canvas c, Size s, List<Color> colors) {
    final h = s.height / colors.length;
    for (var i = 0; i < colors.length; i++) {
      c.drawRect(Rect.fromLTWH(0, h * i, s.width, h + 0.5), Paint()..color = colors[i]);
    }
  }

  void _hoistTriangle(Canvas c, Size s, Color color, {double depth = 0.4}) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(s.width * depth, s.height / 2)
      ..lineTo(0, s.height)
      ..close();
    c.drawPath(path, Paint()..color = color);
  }

  @override
  void paint(Canvas canvas, Size s) {
    switch (iso) {
      case 'MW':
        _bands(canvas, s, const [_black, _red, _green]);
        canvas.drawCircle(Offset(s.width / 2, s.height / 6 + s.height * 0.05), s.height * 0.12, Paint()..color = _red);
      case 'ZM':
        canvas.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF198A00));
        final w = s.width * 0.1;
        final top = s.height * 0.4;
        for (final (i, color) in const [_red, _black, Color(0xFFEF7D00)].indexed) {
          canvas.drawRect(Rect.fromLTWH(s.width * 0.7 + w * i, top, w, s.height - top), Paint()..color = color);
        }
      case 'MZ':
        _bands(canvas, s, const [Color(0xFF007168), _white, _black, _white, _yellow]);
        _hoistTriangle(canvas, s, _red);
      case 'TZ':
        canvas.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF00A3DD));
        canvas.drawPath(
          Path()
            ..moveTo(0, 0)
            ..lineTo(s.width, 0)
            ..lineTo(0, s.height)
            ..close(),
          Paint()..color = const Color(0xFF1EB53A),
        );
        canvas.drawLine(
          Offset(0, s.height),
          Offset(s.width, 0),
          Paint()
            ..color = _yellow
            ..strokeWidth = s.height * 0.4,
        );
        canvas.drawLine(
          Offset(0, s.height),
          Offset(s.width, 0),
          Paint()
            ..color = _black
            ..strokeWidth = s.height * 0.25,
        );
      case 'ZW':
        _bands(canvas, s, const [_green, _yellow, _red, _black, _red, _yellow, _green]);
        _hoistTriangle(canvas, s, _white, depth: 0.45);
      case 'ZA':
        _bands(canvas, s, const [Color(0xFFE03C31), Color(0xFF001489)]);
        canvas.drawRect(Rect.fromLTWH(0, s.height * 0.38, s.width, s.height * 0.24), Paint()..color = _white);
        canvas.drawRect(Rect.fromLTWH(0, s.height * 0.42, s.width, s.height * 0.16), Paint()..color = const Color(0xFF007749));
        _hoistTriangle(canvas, s, _yellow, depth: 0.42);
        _hoistTriangle(canvas, s, _black, depth: 0.34);
      case 'KE':
        _bands(canvas, s, const [_black, _white, _red, _white, Color(0xFF006600)]);
      case 'UG':
        _bands(canvas, s, const [_black, _yellow, _red, _black, _yellow, _red]);
        canvas.drawCircle(Offset(s.width / 2, s.height / 2), s.height * 0.22, Paint()..color = _white);
      case 'BW':
        _bands(canvas, s, const [Color(0xFF75AADB), Color(0xFF75AADB), _white, _black, _white, Color(0xFF75AADB), Color(0xFF75AADB)]);
      case 'GB':
        canvas.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF012169));
        final diag = Paint()
          ..color = _white
          ..strokeWidth = s.height * 0.2;
        canvas.drawLine(Offset.zero, Offset(s.width, s.height), diag);
        canvas.drawLine(Offset(0, s.height), Offset(s.width, 0), diag);
        canvas.drawRect(Rect.fromLTWH(0, s.height * 0.33, s.width, s.height * 0.34), Paint()..color = _white);
        canvas.drawRect(Rect.fromLTWH(s.width * 0.4, 0, s.width * 0.2, s.height), Paint()..color = _white);
        canvas.drawRect(Rect.fromLTWH(0, s.height * 0.4, s.width, s.height * 0.2), Paint()..color = const Color(0xFFC8102E));
        canvas.drawRect(Rect.fromLTWH(s.width * 0.44, 0, s.width * 0.12, s.height), Paint()..color = const Color(0xFFC8102E));
      case 'US':
        _bands(canvas, s, const [Color(0xFFB22234), _white, Color(0xFFB22234), _white, Color(0xFFB22234), _white, Color(0xFFB22234)]);
        canvas.drawRect(Rect.fromLTWH(0, 0, s.width * 0.42, s.height * 4 / 7), Paint()..color = const Color(0xFF3C3B6E));
      default:
        canvas.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF8C9A97));
    }
  }

  @override
  bool shouldRepaint(covariant _FlagPainter old) => old.iso != iso;
}

/// The flag and dialling code beside a phone field; opens [showCountryPicker].
class CountryCodeButton extends StatelessWidget {
  const CountryCodeButton({super.key, required this.country, required this.onChanged});

  final Country country;
  final ValueChanged<Country> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'auth.countryCode'.tr(args: ['${country.name} ${country.dialLabel}']),
      excludeSemantics: true,
      child: OutlinedButton(
        key: const ValueKey('country-code-button'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 56),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
        onPressed: () async {
          final picked = await showCountryPicker(context, selected: country);
          if (picked != null) onChanged(picked);
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CountryFlag(country),
            const SizedBox(width: AppSpacing.sm),
            Text(country.dialLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
            const Icon(Icons.arrow_drop_down, size: 20),
          ],
        ),
      ),
    );
  }
}

/// A searchable bottom sheet of [kCountries]. Returns the chosen country, or
/// null when dismissed.
Future<Country?> showCountryPicker(BuildContext context, {Country? selected}) {
  return showModalBottomSheet<Country>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => CountryPickerSheet(selected: selected),
  );
}

class CountryPickerSheet extends StatefulWidget {
  const CountryPickerSheet({super.key, this.selected});

  final Country? selected;

  @override
  State<CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<CountryPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final results = filterCountries(_query);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
            child: Text(
              'auth.chooseCountry'.tr(),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: TextField(
              key: const ValueKey('country-search'),
              autofocus: false,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'auth.searchCountry'.tr(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Flexible(
            child: results.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Text(
                      'auth.noCountryMatch'.tr(),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final c in results)
                        ListTile(
                          key: ValueKey('country-${c.iso}'),
                          leading: CountryFlag(c, width: 28),
                          title: Text(c.name),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(c.dialLabel, style: TextStyle(color: scheme.onSurfaceVariant)),
                              if (c == widget.selected) ...[
                                const SizedBox(width: AppSpacing.sm),
                                Icon(Icons.check, color: scheme.primary, size: 20),
                              ],
                            ],
                          ),
                          onTap: () => Navigator.of(context).pop(c),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}
