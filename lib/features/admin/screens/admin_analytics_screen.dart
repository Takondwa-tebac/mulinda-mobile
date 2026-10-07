import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../data/admin_repository.dart';

/// Fetches the analytics payload. `refresh` bypasses the API's short cache.
final _analyticsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) {
  return ref.read(adminRepositoryProvider).analytics();
});

/// Platform analytics for admins: users, subscribers (paid vs gifted),
/// subscription revenue and usage. Gifted subscriptions never count as revenue.
class AdminAnalyticsScreen extends ConsumerWidget {
  const AdminAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_analyticsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Platform Analytics'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: async.isLoading
                ? null
                : () => ref.read(adminRepositoryProvider).analytics(refresh: true).then(
                      (_) => ref.invalidate(_analyticsProvider),
                      onError: (_) => ref.invalidate(_analyticsProvider),
                    ),
          ),
        ],
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    e is ApiException ? e.displayMessage : 'Could not load analytics.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => ref.invalidate(_analyticsProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
          data: (data) => RefreshIndicator(
            onRefresh: () async {
              await ref.read(adminRepositoryProvider).analytics(refresh: true);
              ref.invalidate(_analyticsProvider);
              await ref.read(_analyticsProvider.future);
            },
            child: _AnalyticsBody(data: data),
          ),
        ),
      ),
    );
  }
}

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? v.cast<String, dynamic>() : const <String, dynamic>{};

int _int(dynamic v) => (v as num?)?.toInt() ?? 0;

String _money(dynamic v) => _map(v)['formatted']?.toString() ?? '—';

double _major(dynamic v) => (_map(v)['amount'] as num?)?.toDouble() ?? 0;

String _pct(dynamic v) => '${(((v as num?) ?? 0) * 100).toStringAsFixed(1)}%';

String _count(int n) => n.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (m) => ',',
    );

class _AnalyticsBody extends StatelessWidget {
  const _AnalyticsBody({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final users = _map(data['users']);
    final subs = _map(data['subscriptions']);
    final revenue = _map(data['revenue']);
    final gifts = _map(data['gifts']);
    final engagement = _map(data['engagement']);
    final offline = _map(data['offline']);
    final scheme = Theme.of(context).colorScheme;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            // ---- Revenue headline -------------------------------------------
            _Headline(
              label: 'Revenue this month',
              value: _money(revenue['this_month']),
              sub: 'Last month ${_money(revenue['last_month'])}',
            ),
            const SizedBox(height: 12),
            _TileGrid(tiles: [
              _Stat('Today', _money(revenue['today']), Icons.today_outlined),
              _Stat('Since inception', _money(revenue['all_time']), Icons.account_balance_wallet_outlined),
              _Stat('Paid invoices (all time)', _count(_int(revenue['paid_invoices_all_time'])), Icons.receipt_long_outlined),
              _Stat('Avg per paying customer', _money(revenue['average_per_paying_customer']), Icons.person_outline),
            ]),
            const SizedBox(height: 8),
            Text(
              'Gifted subscriptions are never counted as revenue.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),

            // ---- Subscribers ------------------------------------------------
            const _SectionTitle('Subscribers right now'),
            _SubscriberBar(
              paid: _int(subs['active_paid']),
              gifted: _int(subs['active_gifted']),
              trial: _int(subs['active_trial']),
              free: _int(subs['free_users']),
            ),
            const SizedBox(height: 12),
            _TileGrid(tiles: [
              _Stat('Paid subscribers', _count(_int(subs['active_paid'])), Icons.workspace_premium_outlined),
              _Stat('Gifted subscribers', _count(_int(subs['active_gifted'])), Icons.card_giftcard_outlined),
              _Stat('On free trial', _count(_int(subs['active_trial'])), Icons.hourglass_bottom_outlined),
              _Stat('Free users', _count(_int(subs['free_users'])), Icons.person_outline),
              _Stat('Paid conversion', _pct(subs['paid_conversion_rate']), Icons.trending_up),
              _Stat('Paying customers ever', _count(_int(subs['paying_customers_all_time'])), Icons.groups_outlined),
            ]),

            // ---- Users ------------------------------------------------------
            const _SectionTitle('Users'),
            _TileGrid(tiles: [
              _Stat('Total users', _count(_int(users['total'])), Icons.people_outline),
              _Stat('New this month', _count(_int(users['new_this_month'])), Icons.person_add_alt_outlined),
              _Stat('New today', _count(_int(users['new_today'])), Icons.today_outlined),
              _Stat('Active (30 days)', _count(_int(users['active_last_30_days'])), Icons.bolt_outlined),
            ]),

            // ---- Trend ------------------------------------------------------
            const _SectionTitle('Revenue — last 6 months'),
            _MonthlyChart(months: (revenue['monthly'] as List?) ?? const []),

            // ---- By plan ----------------------------------------------------
            const _SectionTitle('By plan'),
            _PlanTable(plans: (revenue['by_plan'] as List?) ?? const []),

            // ---- Gifts ------------------------------------------------------
            const _SectionTitle('Gifted subscriptions'),
            _TileGrid(tiles: [
              _Stat('Given this month', _count(_int(gifts['given_this_month'])), Icons.card_giftcard_outlined),
              _Stat('Given all time', _count(_int(gifts['given_all_time'])), Icons.redeem_outlined),
              _Stat('Recipients', _count(_int(gifts['recipients_all_time'])), Icons.group_outlined),
              _Stat('Retail value (not revenue)', _money(gifts['retail_value_all_time']), Icons.sell_outlined),
            ]),

            // ---- Usage ------------------------------------------------------
            const _SectionTitle('Usage'),
            _TileGrid(tiles: [
              _Stat('SMS captured', _count(_int(engagement['sms_captured_total'])), Icons.sms_outlined),
              _Stat('SMS this month', _count(_int(engagement['sms_captured_this_month'])), Icons.sms_outlined),
              _Stat('Transactions', _count(_int(engagement['transactions_total'])), Icons.swap_horiz),
              _Stat('Transactions this month', _count(_int(engagement['transactions_this_month'])), Icons.swap_horiz),
              _Stat('Coach conversations', _count(_int(engagement['coach_conversations'])), Icons.auto_awesome_outlined),
            ]),

            // ---- Offline mode -----------------------------------------------
            if (offline.isNotEmpty) ...[
              const _SectionTitle('Offline mode'),
              _TileGrid(tiles: [
                _Stat('Eligible users', _count(_int(offline['eligible_users'])), Icons.verified_user_outlined),
                _Stat('Turned it on', _count(_int(offline['users_with_offline_on'])), Icons.cloud_off_outlined),
                _Stat('Conflicts and failures', _pct(offline['conflict_failure_rate']), Icons.warning_amber_outlined),
                _Stat('Batches (24h)', _count(_int(offline['batches_last_24h'])), Icons.sync_outlined),
                _Stat('Failed batches (24h)', _count(_int(offline['batches_failed_last_24h'])), Icons.sync_problem_outlined),
                _Stat('Changes synced (14 days)', _count(_sumSeries(offline['series'], 'applied')), Icons.done_all),
              ]),
            ],
            const SizedBox(height: 16),
            Text(
              'Updated ${_updated(data['generated_at'])} · figures refresh every few minutes',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  int _sumSeries(dynamic series, String key) =>
      series is List ? series.fold<int>(0, (a, e) => a + (e is Map ? _int(e[key]) : 0)) : 0;

  String _updated(dynamic iso) {
    final d = DateTime.tryParse(iso?.toString() ?? '')?.toLocal();
    if (d == null) return 'just now';
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 10),
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
        ),
      );
}

class _Headline extends StatelessWidget {
  const _Headline({required this.label, required this.value, required this.sub});

  final String label;
  final String value;
  final String sub;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.8), fontSize: 13)),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: scheme.onPrimaryContainer,
                    ),
              ),
            ),
            const SizedBox(height: 2),
            Text(sub,
                style: TextStyle(
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.8), fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _Stat {
  const _Stat(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;
}

/// Two columns on phones, three on wider screens.
class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.tiles});

  final List<_Stat> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final columns = c.maxWidth >= 560 ? 3 : 2;
      const gap = 10.0;
      final width = (c.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final t in tiles) SizedBox(width: width, child: _StatTile(stat: t))],
      );
    });
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.stat});

  final _Stat stat;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(stat.icon, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  stat.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              stat.value,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
          ),
        ],
      ),
    );
  }
}

/// Proportional bar of paid / gifted / trial / free users.
class _SubscriberBar extends StatelessWidget {
  const _SubscriberBar({
    required this.paid,
    required this.gifted,
    required this.trial,
    required this.free,
  });

  final int paid;
  final int gifted;
  final int trial;
  final int free;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = paid + gifted + trial + free;
    final segments = [
      ('Paid', paid, scheme.primary),
      ('Gifted', gifted, scheme.tertiary),
      ('Trial', trial, scheme.secondary),
      ('Free', free, scheme.outlineVariant),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 14,
            child: total == 0
                ? ColoredBox(color: scheme.surfaceContainerHigh)
                : Row(
                    children: [
                      for (final s in segments)
                        if (s.$2 > 0) Expanded(flex: s.$2, child: ColoredBox(color: s.$3)),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            for (final s in segments)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: s.$3, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text('${s.$1} ${_count(s.$2)}', style: const TextStyle(fontSize: 12)),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _MonthlyChart extends StatelessWidget {
  const _MonthlyChart({required this.months});

  final List months;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final points = months.map((m) => _map(m)).toList();
    if (points.isEmpty) return const SizedBox.shrink();

    final values = points.map((p) => _major(p['revenue'])).toList();
    final maxValue = values.fold<double>(0, (a, b) => b > a ? b : a);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
        child: SizedBox(
          height: 190,
          child: BarChart(
            BarChartData(
              maxY: maxValue == 0 ? 1 : maxValue * 1.2,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                topTitles: const AxisTitles(),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i < 0 || i >= points.length) return const SizedBox.shrink();
                      final month = points[i]['month']?.toString() ?? '';
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          month.length >= 7 ? month.substring(5) : month,
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                    _money(points[group.x]['revenue']),
                    TextStyle(color: scheme.onInverseSurface, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < values.length; i++)
                  BarChartGroupData(x: i, barRods: [
                    BarChartRodData(
                      toY: values[i],
                      width: 18,
                      color: i == values.length - 1
                          ? scheme.primary
                          : scheme.primary.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlanTable extends StatelessWidget {
  const _PlanTable({required this.plans});

  final List plans;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < plans.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            Builder(builder: (context) {
              final p = _map(plans[i]);
              return ListTile(
                dense: true,
                title: Text(p['label']?.toString() ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  '${_count(_int(p['purchases_this_month']))} this month · '
                  '${_count(_int(p['purchases_all_time']))} all time',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_money(p['revenue_this_month']),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('${_money(p['revenue_all_time'])} total',
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11)),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
