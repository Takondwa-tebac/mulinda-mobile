import 'package:flutter/material.dart';

/// The icon names the server hands out (Material icon names) and the icons they
/// stand for. A name that is not here shows the generic label icon, so a category
/// added later on the server still shows something.
const _icons = <String, IconData>{
  'restaurant': Icons.restaurant,
  'directions_bus': Icons.directions_bus,
  'home': Icons.home,
  'bolt': Icons.bolt,
  'wifi': Icons.wifi,
  'phone_android': Icons.phone_android,
  'school': Icons.school,
  'favorite': Icons.favorite,
  'store': Icons.store,
  'movie': Icons.movie,
  'trending_up': Icons.trending_up,
  'savings': Icons.savings,
  'account_balance': Icons.account_balance,
  'gavel': Icons.gavel,
  'payments': Icons.payments,
  'work': Icons.work,
  'card_giftcard': Icons.card_giftcard,
  'label': Icons.label_outline,
  // Common ones for categories people add themselves.
  'shopping_cart': Icons.shopping_cart,
  'local_gas_station': Icons.local_gas_station,
  'pets': Icons.pets,
  'child_care': Icons.child_care,
  'flight': Icons.flight,
  'build': Icons.build,
  'fitness_center': Icons.fitness_center,
  'church': Icons.church,
  'checkroom': Icons.checkroom,
  'local_hospital': Icons.local_hospital,
  // Investment types.
  'pie_chart': Icons.pie_chart,
  'show_chart': Icons.show_chart,
  'groups': Icons.groups,
  'diversity_3': Icons.diversity_3,
  'shield': Icons.shield_outlined,
  'holiday_village': Icons.holiday_village,
  'elderly': Icons.elderly,
  'home_work': Icons.home_work,
  'description': Icons.description,
  'category': Icons.category,
};

IconData categoryIcon(String? name) => _icons[name] ?? Icons.label_outline;

/// `#RRGGBB` (or `#AARRGGBB`) to a colour, or null when it is missing or not valid.
Color? parseHexColor(String? hex) {
  if (hex == null) return null;
  final clean = hex.replaceFirst('#', '');
  if (clean.length != 6 && clean.length != 8) return null;
  final value = int.tryParse(clean, radix: 16);
  if (value == null) return null;
  return Color(clean.length == 6 ? 0xFF000000 | value : value);
}
