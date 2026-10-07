/// One saved response on the phone and how much room it takes.
class CachedEntryUsage {
  const CachedEntryUsage(this.key, this.bytes);

  /// e.g. `GET /v1/accounts?page=1`
  final String key;
  final int bytes;
}

/// One line of the "what is saved" list.
class StorageGroup {
  const StorageGroup({required this.label, required this.items, required this.bytes});

  final String label;
  final int items;
  final int bytes;
}

/// Turns the saved responses into a short, readable list (Transactions, Goals…)
/// instead of showing raw requests.
class StorageBreakdown {
  const StorageBreakdown(this.groups);

  final List<StorageGroup> groups;

  int get totalBytes => groups.fold(0, (a, g) => a + g.bytes);

  bool get isEmpty => groups.isEmpty;

  /// What each part of the API is called to the user. Anything not listed ends up
  /// under "Other".
  static const _labels = <String, String>{
    'dashboard': 'Dashboard',
    'accounts': 'Accounts',
    'categories': 'Categories',
    'transactions': 'Transactions',
    'goals': 'Goals',
    'budgets': 'Budgets',
    'loans': 'Loans',
    'investments': 'Investments',
    'projects': 'Projects',
    'insights': 'Notifications',
    'notifications': 'Notifications',
    'receipt-scans': 'Inbox',
    'inbox': 'Inbox',
    'summaries': 'Daily summaries',
    'daily-summaries': 'Daily summaries',
  };

  static StorageBreakdown from(Iterable<CachedEntryUsage> entries) {
    final items = <String, int>{};
    final bytes = <String, int>{};

    for (final e in entries) {
      final label = labelFor(e.key);
      items[label] = (items[label] ?? 0) + 1;
      bytes[label] = (bytes[label] ?? 0) + e.bytes;
    }

    final groups = [
      for (final label in items.keys) StorageGroup(label: label, items: items[label]!, bytes: bytes[label]!),
    ]..sort((a, b) {
        // "Other" last, then biggest first.
        if (a.label == 'Other') return 1;
        if (b.label == 'Other') return -1;
        return b.bytes.compareTo(a.bytes);
      });

    return StorageBreakdown(groups);
  }

  /// `GET /v1/goals/123?x=1` becomes "Goals".
  static String labelFor(String key) {
    final path = key.split(' ').last.split('?').first;
    final segments = path.split('/').where((s) => s.isNotEmpty && s != 'v1').toList();
    if (segments.isEmpty) return 'Other';
    return _labels[segments.first] ?? 'Other';
  }

  /// 0 B, 812 B, 14.2 KB, 1.3 MB.
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(bytes < 10 * 1024 ? 1 : 0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
