import '../../activity/data/activity_models.dart';

/// The account a money message most likely came from, by its sender (or an
/// account's own name): Airtel Money and TNM Mpamba are mobile money, NBM,
/// FDH and Centenary are banks. Null for senders Mulinda does not know.
({String name, String type})? suggestedAccountFor(String? sender) {
  final s = (sender ?? '').toLowerCase();
  if (s.contains('airtel')) return (name: 'Airtel Money', type: 'mobile_money');
  if (s.contains('mpamba') || s.contains('tnm')) return (name: 'TNM Mpamba', type: 'mobile_money');
  if (s.contains('nbm') || s.contains('natbank') || s.contains('national bank')) return (name: 'NBM', type: 'bank');
  if (s.contains('fdh')) return (name: 'FDH Bank', type: 'bank');
  if (s.contains('cente')) return (name: 'Centenary Bank', type: 'bank');
  return null;
}

/// Whether the user already has an account for [suggestion] (matched by what
/// the account's own name suggests, so "My Airtel" counts as Airtel Money).
bool hasAccountFor(({String name, String type}) suggestion, Iterable<Account> accounts) =>
    accounts.any((a) => suggestedAccountFor(a.name)?.name == suggestion.name);

/// The accounts to create so every known sender in [senders] has one, in
/// first-seen order and without repeats.
List<({String name, String type})> accountsToCreate(Iterable<String?> senders, Iterable<Account> existing) {
  final out = <({String name, String type})>[];
  for (final sender in senders) {
    final suggestion = suggestedAccountFor(sender);
    if (suggestion == null || out.contains(suggestion) || hasAccountFor(suggestion, existing)) continue;
    out.add(suggestion);
  }
  return out;
}

/// One row of the import summary: who sent the messages and how many.
class SenderCount {
  const SenderCount({required this.label, required this.count, this.account});

  /// The known account name ("Airtel Money") or the raw sender address.
  final String label;
  final int count;

  /// The suggested account when the sender is known.
  final ({String name, String type})? account;
}

/// Messages counted per sender, known senders grouped under their account
/// name, most messages first.
List<SenderCount> countBySender(Iterable<String?> senders) {
  final counts = <String, int>{};
  final accounts = <String, ({String name, String type})?>{};
  for (final sender in senders) {
    final suggestion = suggestedAccountFor(sender);
    final raw = (sender ?? '').trim();
    final label = suggestion?.name ?? (raw.isEmpty ? '?' : raw);
    counts[label] = (counts[label] ?? 0) + 1;
    accounts[label] = suggestion;
  }
  final rows = [
    for (final e in counts.entries) SenderCount(label: e.key, count: e.value, account: accounts[e.key]),
  ]..sort((a, b) => b.count.compareTo(a.count));
  return rows;
}
