// Sample payloads from the stories contract (stories-contract.md).

String _group(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

Map<String, dynamic> money(int major) => {
  'minor_units': major * 100,
  'currency': 'MWK',
  'amount': major,
  'formatted': 'MK ${_group(major)}.00',
};

Map<String, dynamic> monthJson({bool available = true, String key = '2026-10'}) => {
  'period': {'type': 'month', 'key': key, 'starts_on': '2026-10-01', 'ends_on': '2026-10-31'},
  'available': available,
  'messages_recorded': 182,
  'transactions_count': 201,
  'income': money(310000),
  'spending': money(201300),
  'kept_ratio': 0.35,
  'top_categories': [
    {'slug': 'sent-to-people', 'name': 'Sent to people', 'amount': money(62000), 'share': 0.31},
    {'slug': 'food', 'name': 'Food', 'amount': money(48200), 'share': 0.24},
    {'slug': 'transport', 'name': 'Transport', 'amount': money(31500), 'share': 0.16},
  ],
  'biggest_day': {'date': '2026-10-24', 'amount': money(38500), 'share': 0.19},
  'change_vs_previous': {'previous_key': '2026-09', 'ratio': -0.12},
  'budgets': {'kept': 3, 'total': 4},
  'money_style': 'steady_planner',
  'top_counterparty': {'name': 'Thoko', 'count': 9},
  'top_merchant': {'name': 'Shoprite', 'count': 7},
  'goals_reached': {'count': 0, 'names': <String>[], 'saved': money(0)},
};

Map<String, dynamic> yearJson() => {
  ...monthJson(),
  'period': {'type': 'year', 'key': '2026', 'starts_on': '2026-01-01', 'ends_on': '2026-10-31'},
  'messages_recorded': 1846,
  'months': [
    {'key': '2026-01', 'spending': money(104000), 'share_of_max': 0.52},
    {'key': '2026-03', 'spending': money(200000), 'share_of_max': 1},
  ],
  'biggest_month': '2026-03',
  'top_counterparty': {'name': 'Thoko', 'count': 41},
  'top_merchant': {'name': 'Shoprite', 'count': 63, 'top_weekday': 'saturday'},
  'messages_per_day': 6.1,
  'money_style': 'family_builder',
  'goals_reached': {
    'count': 2,
    'names': ['School fees', 'New phone'],
    'saved': money(650000),
  },
};

const statusJson = <String, dynamic>{
  'year': 2026,
  'release_at': '2026-11-25T07:00:00+02:00',
  'countdown_from': '2026-11-01',
  'days_left': 3,
  'ready': false,
  'viewed': false,
  'reminders_enabled': true,
};
