import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/currencies.dart';
import '../data/insights_repository.dart';

/// Full view of one notification: image (if any), then title, message, any
/// extra details and delivery info. Opening it marks the notification as read.
class NotificationDetailScreen extends ConsumerStatefulWidget {
  const NotificationDetailScreen({super.key, required this.notificationId, this.initial});

  final String notificationId;

  /// The notification passed from the list, for an instant first paint. When
  /// absent (e.g. opened from a push tap) it is looked up from the list.
  final Insight? initial;

  @override
  ConsumerState<NotificationDetailScreen> createState() => _NotificationDetailScreenState();
}

class _NotificationDetailScreenState extends ConsumerState<NotificationDetailScreen> {
  bool _markedRead = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) _markReadOnce(initial);
  }

  /// Marks the notification as read the first time it is shown, then refreshes
  /// the list and the unread badge.
  Future<void> _markReadOnce(Insight insight) async {
    if (_markedRead || insight.isRead) return;
    _markedRead = true;
    try {
      await ref.read(insightsRepositoryProvider).markRead(insight.id);
    } catch (_) {
      // Best-effort: it will simply stay unread and can be opened again.
      _markedRead = false;
      return;
    }
    ref
      ..invalidate(insightsProvider)
      ..invalidate(unreadInsightsCountProvider);
  }

  @override
  Widget build(BuildContext context) {
    // Prefer the live copy from the list (it reflects the read state once
    // refreshed); fall back to what we were given.
    final fromList = ref.watch(insightsProvider).valueOrNull?.where((i) => i.id == widget.notificationId).firstOrNull;
    final insight = fromList ?? widget.initial;

    if (insight == null) {
      return Scaffold(
        appBar: AppBar(title: Text('insights.title'.tr())),
        body: ref.watch(insightsProvider).isLoading
            ? const Center(child: CircularProgressIndicator())
            : Center(child: Text('insights.notFound'.tr())),
      );
    }

    // Reached via a push tap (no `initial`): mark read once it is loaded.
    if (widget.initial == null && !insight.isRead) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _markReadOnce(insight));
    }

    return Scaffold(
      appBar: AppBar(title: Text('insights.detailTitle'.tr())),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: _Body(insight: insight),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.insight});

  final Insight insight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final hasImage = insight.imageUrl != null && insight.imageUrl!.isNotEmpty;

    // Friendly rows built from the notification's payload: amounts formatted as
    // currency, dates readable, internal ids and raw fields hidden.
    final extras = _detailRows(insight.details);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        // 1. Type + when
        Row(
          children: [
            _TypeChip(type: insight.type),
            const Spacer(),
            Icon(Icons.schedule, size: 14, color: scheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              _formatDateTime(insight.createdAt),
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // 2. Image
        if (hasImage) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: CachedNetworkImage(
              imageUrl: insight.imageUrl!,
              width: double.infinity,
              fit: BoxFit.cover,
              placeholder: (_, _) => SizedBox(
                height: 200,
                child: ColoredBox(
                  color: scheme.surfaceContainerHigh,
                  child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              ),
              errorWidget: (_, _, _) => SizedBox(
                height: 120,
                child: ColoredBox(
                  color: scheme.surfaceContainerHigh,
                  child: Center(
                    child: Icon(Icons.broken_image_outlined, color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
        ],

        // 3. Title
        Text(
          insight.title,
          style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, height: 1.25),
        ),
        const SizedBox(height: 12),

        // 4. Message
        SelectableText(
          insight.body,
          style: text.bodyLarge?.copyWith(height: 1.55, color: scheme.onSurface.withValues(alpha: 0.9)),
        ),

        // 5. Extra details
        if (extras.isNotEmpty) ...[
          const SizedBox(height: 22),
          _SectionLabel('insights.moreDetails'.tr()),
          _InfoCard(
            rows: extras,
          ),
        ],

        // 6. Delivery info
        const SizedBox(height: 22),
        _SectionLabel('insights.about'.tr()),
        _InfoCard(
          rows: [
            ('insights.received'.tr(), _formatDateTime(insight.createdAt)),
            ('insights.typeLabel'.tr(), 'insights.type.${insight.type}'.tr()),
            ('insights.status'.tr(), insight.isRead ? 'insights.read'.tr() : 'insights.unread'.tr()),
          ],
        ),
      ],
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconForInsightType(type), size: 15, color: scheme.onPrimaryContainer),
          const SizedBox(width: 6),
          Text(
            'insights.type.$type'.tr(),
            style: TextStyle(
              color: scheme.onPrimaryContainer,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
      );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.rows});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(rows[i].$1, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 6,
                    child: Text(
                      rows[i].$2,
                      textAlign: TextAlign.end,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Turns the raw payload into display rows, ordered amounts → dates → the rest.
///
/// * `amount_minor` (minor units, e.g. tambala) becomes "Amount" in major units
///   formatted with the currency symbol, e.g. `MK 12,500.00`.
/// * Other amount-like numbers (savings, balances, totals…) are formatted the
///   same way, using the payload's `currency` (MWK when absent).
/// * Dates read like `6 Oct 2026`; ids, the image URL and the currency code
///   itself are not shown.
List<(String, String)> _detailRows(Map<String, dynamic> details) {
  final currency = (details['currency'] ?? 'MWK').toString();
  final amounts = <(String, String)>[];
  final dates = <(String, String)>[];
  final other = <(String, String)>[];

  for (final e in details.entries) {
    final key = e.key;
    final value = e.value;
    if (value == null || value is Map || value is List) continue;
    final text = value.toString();
    if (text.isEmpty) continue;
    if (key == 'image_url' || key == 'currency' || key == 'id' || key.endsWith('_id')) continue;

    if (key.endsWith('_minor') && value is num) {
      amounts.add((_humanize(key.substring(0, key.length - '_minor'.length)), _formatMoney(value / 100, currency)));
    } else if (value is num && _amountKey.hasMatch(key)) {
      amounts.add((_humanize(key), _formatMoney(value.toDouble(), currency)));
    } else if (key.endsWith('_date') || key.endsWith('_at') || _isoDate.hasMatch(text)) {
      dates.add((_humanize(key), _formatDate(text)));
    } else {
      other.add((_humanize(key), text));
    }
  }
  return [...amounts, ...dates, ...other];
}

final _amountKey = RegExp(r'(amount|saving|balance|total|spent|limit|budget|price|fee|cost|value|premium)');
final _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}');

/// `MK 12,500.00` — symbol, thousands separators, two decimals.
String _formatMoney(double major, String currency) {
  final symbol = currencyInfo(currency).symbol;
  final negative = major < 0;
  final parts = major.abs().toStringAsFixed(2).split('.');
  final grouped = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  return '${negative ? '-' : ''}$symbol $grouped.${parts[1]}';
}

String _formatDate(String raw) {
  final d = DateTime.tryParse(raw);
  if (d == null) return raw;
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

/// `daily_summary` → `Daily summary`.
String _humanize(String key) {
  final spaced = key.replaceAll('_', ' ').trim();
  return spaced.isEmpty ? key : spaced[0].toUpperCase() + spaced.substring(1);
}

String _formatDateTime(String? iso) {
  final d = DateTime.tryParse(iso ?? '')?.toLocal();
  if (d == null) return '—';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return '${d.day} ${months[d.month - 1]} ${d.year} · $hh:$mm';
}

/// Icon for each notification type (shared with the list).
IconData iconForInsightType(String type) => switch (type) {
      'savings_opportunity' => Icons.lightbulb_outline,
      'spending_spike' => Icons.trending_up,
      'budget_alert' => Icons.warning_amber_rounded,
      'bill_due' => Icons.event_outlined,
      'loan_repayment_due' => Icons.account_balance_outlined,
      'announcement' => Icons.campaign_outlined,
      _ => Icons.insights_outlined,
    };
