import 'package:flutter/material.dart';

/// Renders a chart card from a coach chart API payload.
/// [data] is the `data` field returned by a `/coach/charts/*` endpoint.
class CoachChartWidget extends StatelessWidget {
  const CoachChartWidget({super.key, required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    return switch (data['kind'] as String? ?? '') {
      'category_breakdown' => _CategoryBreakdownChart(data: data),
      'account_balances' => _AccountBalancesChart(data: data),
      'spending_summary' => _SpendingSummaryChart(data: data),
      'savings_rule' => _SavingsRuleChart(data: data),
      _ => const SizedBox.shrink(),
    };
  }
}

// ---------------------------------------------------------------------------
// Category breakdown — horizontal bars per category
// ---------------------------------------------------------------------------

class _CategoryBreakdownChart extends StatelessWidget {
  const _CategoryBreakdownChart({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final currency = data['currency'] as String? ?? '';
    final series = (data['series'] as List<dynamic>?) ?? [];

    return _ChartCard(
      title: data['title'] as String? ?? 'Categories',
      child: Column(
        children: series.map((item) {
          final m = item as Map<String, dynamic>;
          final pct = ((m['percentage'] as num?) ?? 0).toDouble();
          final amount = (m['amount_minor'] as num?)?.toInt() ?? 0;
          return _HBar(
            label: m['label'] as String? ?? '',
            value: pct / 100,
            trailing: _fmt(amount, currency),
            color: scheme.primary,
          );
        }).toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Account balances — bars proportional to max balance
// ---------------------------------------------------------------------------

class _AccountBalancesChart extends StatelessWidget {
  const _AccountBalancesChart({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final currency = data['currency'] as String? ?? '';
    final accounts = (data['accounts'] as List<dynamic>?) ?? [];

    final maxAmount = accounts
        .map((a) => ((a as Map<String, dynamic>)['amount_minor'] as num?)?.abs() ?? 0)
        .fold<num>(1, (m, v) => v > m ? v : m)
        .toDouble();

    return _ChartCard(
      title: data['title'] as String? ?? 'Accounts',
      child: Column(
        children: accounts.map((item) {
          final m = item as Map<String, dynamic>;
          final amount = (m['amount_minor'] as num?)?.toInt() ?? 0;
          return _HBar(
            label: m['label'] as String? ?? '',
            value: (amount.abs() / maxAmount).clamp(0.0, 1.0),
            trailing: _fmt(amount, currency),
            color: amount < 0 ? scheme.error : scheme.primary,
          );
        }).toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Spending summary — 4 metric tiles (income / expense / net / savings rate)
// ---------------------------------------------------------------------------

class _SpendingSummaryChart extends StatelessWidget {
  const _SpendingSummaryChart({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final currency = data['currency'] as String? ?? '';
    final income = (data['income_minor'] as num?)?.toInt() ?? 0;
    final expense = (data['expense_minor'] as num?)?.toInt() ?? 0;
    final net = (data['net_minor'] as num?)?.toInt() ?? 0;
    final savingsRate = ((data['savings_rate'] as num?) ?? 0).toDouble();
    final green = Colors.green.shade700;

    return _ChartCard(
      title: data['title'] as String? ?? 'Income vs spending',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  label: 'Income',
                  value: _fmt(income, currency),
                  color: green,
                  icon: Icons.arrow_downward_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricTile(
                  label: 'Spending',
                  value: _fmt(expense, currency),
                  color: scheme.error,
                  icon: Icons.arrow_upward_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  label: 'Net',
                  value: _fmt(net, currency),
                  color: net >= 0 ? green : scheme.error,
                  icon: net >= 0 ? Icons.trending_up : Icons.trending_down,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricTile(
                  label: 'Savings rate',
                  value: '${savingsRate.toStringAsFixed(1)}%',
                  color: scheme.primary,
                  icon: Icons.savings_outlined,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Savings rule — rate ring + emergency fund info
// ---------------------------------------------------------------------------

class _SavingsRuleChart extends StatelessWidget {
  const _SavingsRuleChart({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final currentRate = ((data['current_rate'] as num?) ?? 0).toDouble();
    final targetRate = ((data['target_rate'] as num?) ?? 0).toDouble();
    final onTrack = (data['on_track'] as bool?) ?? false;
    final ef = (data['emergency_fund'] as Map?)?.cast<String, dynamic>() ?? {};
    final coverage = ((ef['coverage_ratio'] as num?) ?? 0).toDouble();
    final efOnTrack = (ef['on_track'] as bool?) ?? false;
    final strategy = data['strategy'] as String?;
    final ringColor = onTrack ? Colors.green.shade600 : scheme.error;
    final ringValue = targetRate > 0 ? (currentRate / targetRate).clamp(0.0, 1.0) : 0.0;

    return _ChartCard(
      title: 'Your savings${strategy != null ? ' · $strategy' : ''}',
      child: Row(
        children: [
          SizedBox(
            width: 72,
            height: 72,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: ringValue,
                  strokeWidth: 8,
                  backgroundColor: scheme.surfaceContainerHigh,
                  color: ringColor,
                ),
                Text(
                  '${currentRate.toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: ringColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StatRow(
                  label: 'Current',
                  value: '${currentRate.toStringAsFixed(1)}%',
                  color: ringColor,
                ),
                _StatRow(
                  label: 'Target',
                  value: '${targetRate.toStringAsFixed(1)}%',
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(height: 6),
                _StatRow(
                  label: 'Emergency fund',
                  value: '${coverage.toStringAsFixed(1)} mo',
                  color: efOnTrack ? Colors.green.shade600 : scheme.error,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared components
// ---------------------------------------------------------------------------

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _HBar extends StatelessWidget {
  const _HBar({
    required this.label,
    required this.value,
    required this.trailing,
    required this.color,
  });

  final String label;
  final double value;
  final String trailing;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                trailing,
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 8,
              backgroundColor: scheme.surfaceContainerHigh,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Amount formatter (minor units → compact string)
// ---------------------------------------------------------------------------

String _fmt(int minorUnits, String currency) {
  final isNeg = minorUnits < 0;
  final major = minorUnits.abs() / 100;
  final prefix = isNeg ? '-' : '';
  if (major >= 1000000) {
    return '$prefix$currency ${(major / 1000000).toStringAsFixed(1)}M';
  } else if (major >= 1000) {
    return '$prefix$currency ${(major / 1000).toStringAsFixed(1)}K';
  }
  return '$prefix$currency ${major.toStringAsFixed(0)}';
}
