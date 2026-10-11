import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/summary_models.dart';
import '../data/summary_repository.dart';
import 'daily_summary_detail_screen.dart';

/// Day-by-day history of the user's spending summaries — the screen the daily
/// notification opens, and reachable from notification settings.
class DailySummariesScreen extends ConsumerWidget {
  const DailySummariesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaries = ref.watch(dailySummariesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Daily summaries')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(dailySummariesProvider);
          await ref.read(dailySummariesProvider.future);
        },
        child: summaries.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ListView(
            children: const [
              SizedBox(height: 120),
              Center(child: Text('Could not load your summaries.')),
            ],
          ),
          data: (list) {
            if (list.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  Icon(Icons.receipt_long_outlined, size: 56, color: Colors.grey),
                  SizedBox(height: 12),
                  Center(child: Text('No summaries yet.')),
                  SizedBox(height: 6),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      'Once you have activity, a recap appears here each day at your chosen time.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ),
                ],
              );
            }
            return ListView.builder(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 32 + MediaQuery.of(context).padding.bottom),
              itemCount: list.length,
              itemBuilder: (_, i) => _SummaryCard(summary: list[i]),
            );
          },
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final DailySummary summary;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DailySummaryDetailScreen(summary: summary),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(_prettyDate(summary.date),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 8),
                  Text('${summary.transactionCount} txns',
                      style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                ],
              ),
              const SizedBox(height: 10),
              // One line per figure, label left and amount right. The amount shrinks
              // to fit instead of being cut off, whatever the screen width.
              _Line(label: 'Net', value: summary.net.formatted, color: null, bold: true),
              const SizedBox(height: 4),
              _Line(label: 'Spent', value: summary.expense.formatted, color: Colors.red.shade700),
              const SizedBox(height: 2),
              _Line(label: 'In', value: summary.income.formatted, color: Colors.green.shade700),
              if (summary.topCategory != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.local_offer_outlined, size: 14, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text(
                      'Most on ${summary.topCategory}'
                      '${summary.topCategoryAmount != null ? ' · ${summary.topCategoryAmount!.formatted}' : ''}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// "2026-08-31" → "Sun, 31 Aug 2026" (best-effort, no intl dependency).
  String _prettyDate(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, required this.color, this.bold = false});

  final String label;
  final String value;
  final Color? color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: TextStyle(fontSize: bold ? 13 : 12, color: Colors.grey)),
        const SizedBox(width: 12),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                fontSize: bold ? 17 : 14,
                color: color,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
