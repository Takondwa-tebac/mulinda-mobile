import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/semantic_colors.dart';
import '../../../core/widgets/app_date_field.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/skeleton.dart';
import '../../activity/widgets/txn_view.dart';
import '../data/admin_repository.dart';
import '../data/audit_models.dart';
import 'audit_detail_screen.dart';

/// The icon for an audit's `icon` key.
IconData auditIcon(String key) => switch (key) {
  'created' => Icons.add_circle_outline,
  'updated' => Icons.edit_outlined,
  'deleted' => Icons.delete_outline,
  'restored' => Icons.restore,
  'login' => Icons.login,
  'login_failed' => Icons.gpp_bad_outlined,
  'logout' => Icons.logout,
  'export' => Icons.file_download_outlined,
  'role' => Icons.admin_panel_settings_outlined,
  'subscription' => Icons.workspace_premium_outlined,
  'credit' => Icons.card_giftcard_outlined,
  _ => Icons.history,
};

/// "14:05 Today", "09:12 Tue 3 Nov".
String auditTime(DateTime? at) => at == null ? '' : '${timeOfDay(at)} · ${dayHeaderLabel(at)}';

/// The audit trail: search, filters, newest first with infinite scroll, a tap
/// opens the detail, and an export (CSV or PDF) prepared on the server.
class AuditTrailScreen extends ConsumerStatefulWidget {
  const AuditTrailScreen({super.key, this.exportId});

  /// Opened from the "export ready" notification: show that export.
  final String? exportId;

  @override
  ConsumerState<AuditTrailScreen> createState() => _AuditTrailScreenState();
}

class _AuditTrailScreenState extends ConsumerState<AuditTrailScreen> {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  Timer? _debounce;
  Timer? _poll;

  AuditQuery _query = AuditQuery.none;
  final List<AuditItem> _items = [];
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  Object? _error;
  AuditExport? _export;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.hasClients && _scroll.position.extentAfter < 400) _loadMore();
    });
    _reload();
    if (widget.exportId != null) _watchExport(widget.exportId!);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _poll?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _items.clear();
      _page = 0;
      _hasMore = true;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final page = await ref.read(adminRepositoryProvider).audits(_query, page: _page + 1);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _page = page.page;
        _hasMore = page.hasMore;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setQuery(AuditQuery q) {
    _query = q;
    _reload();
  }

  void _onSearch(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _setQuery(
        AuditQuery(
          q: text,
          event: _query.event,
          model: _query.model,
          platform: _query.platform,
          actor: _query.actor,
          from: _query.from,
          to: _query.to,
        ),
      );
    });
  }

  Future<void> _openFilters() async {
    final picked = await showModalBottomSheet<AuditQuery>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AuditFilterSheet(initial: _query),
    );
    if (picked != null) _setQuery(picked);
  }

  Future<void> _startExport() async {
    final format = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.table_view_outlined),
              title: Text('admin2.audit.exportCsv'.tr()),
              onTap: () => Navigator.of(c).pop('csv'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: Text('admin2.audit.exportPdf'.tr()),
              subtitle: Text('admin2.audit.exportPdfNote'.tr()),
              onTap: () => Navigator.of(c).pop('pdf'),
            ),
          ],
        ),
      ),
    );
    if (format == null) return;
    try {
      final export = await ref.read(adminRepositoryProvider).startAuditExport(format, _query);
      if (!mounted) return;
      setState(() => _export = export);
      _watchExport(export.id);
    } on ApiException catch (e) {
      _snack(e.displayMessage);
    } catch (_) {
      _snack('admin2.audit.exportFailed'.tr());
    }
  }

  /// Polls the export until it is ready or failed (about 3 s apart, at most 5 min).
  void _watchExport(String id) {
    _poll?.cancel();
    var tries = 0;
    Future<void> check() async {
      tries++;
      try {
        final e = await ref.read(adminRepositoryProvider).auditExport(id);
        if (!mounted) return;
        setState(() => _export = e);
        if (e.isDone || tries > 100) _poll?.cancel();
      } catch (_) {
        if (tries > 100) _poll?.cancel();
      }
    }

    unawaited(check());
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => check());
  }

  Future<void> _download(AuditExport e) async {
    final ok = await launchUrl(Uri.parse(e.downloadUrl!), mode: LaunchMode.externalApplication);
    if (!ok) _snack('admin2.audit.openFailed'.tr());
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final extra = _query.count;
    return Scaffold(
      appBar: AppBar(
        title: Text('admin2.audit.title'.tr()),
        actions: [
          IconButton(
            tooltip: 'admin2.audit.filters'.tr(),
            onPressed: _openFilters,
            icon: Badge(isLabelVisible: extra > 0, label: Text('$extra'), child: const Icon(Icons.tune)),
          ),
          IconButton(
            key: const ValueKey('audit-export'),
            tooltip: 'admin2.audit.export'.tr(),
            onPressed: _startExport,
            icon: const Icon(Icons.file_download_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
              sliver: SliverList.list(
                children: [
                  if (_export != null) ...[
                    _ExportCard(export: _export!, onDownload: _download),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  TextField(
                    controller: _search,
                    onChanged: _onSearch,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'admin2.audit.searchHint'.tr(),
                      prefixIcon: const Icon(Icons.search),
                    ),
                  ),
                ],
              ),
            ),
            if (_items.isEmpty && _loading)
              const SliverToBoxAdapter(child: SkeletonList(count: 8, shrinkWrap: true))
            else if (_items.isEmpty && _error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: ErrorRetry(message: 'admin2.audit.loadError'.tr(), onRetry: _reload),
                ),
              )
            else if (_items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: EmptyState(icon: Icons.history, title: 'admin2.audit.emptyTitle'.tr()),
                ),
              )
            else ...[
              SliverList.builder(
                itemCount: _items.length,
                itemBuilder: (_, i) => AuditTile(
                  item: _items[i],
                  onTap: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute<void>(builder: (_) => AuditDetailScreen(id: _items[i].id))),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Center(
                    child: _loading
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
                        : (_error != null ? ErrorRetry(compact: true, onRetry: _loadMore) : const SizedBox.shrink()),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One audit: event icon, what happened to what, who and when.
class AuditTile extends StatelessWidget {
  const AuditTile({super.key, required this.item, required this.onTap});

  final AuditItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final danger = item.icon == 'deleted' || item.icon == 'login_failed';
    final tint = danger ? context.semantic.danger : scheme.primary;
    final who = item.actor?.display ?? 'admin2.audit.system'.tr();
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: tint.withValues(alpha: 0.12),
        child: Icon(auditIcon(item.icon), color: tint, size: 20),
      ),
      title: Text(
        [auditEventLabel(item.event), item.subject.display].where((e) => e.isNotEmpty).join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        [who, if (item.platform != null) item.platform!, auditTime(item.createdAt)].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

/// A readable event name ("login_failed" → "Failed sign-in"), raw as fallback.
String auditEventLabel(String event) {
  final key = 'admin2.audit.event.$event';
  final label = key.tr();
  return label == key ? event.replaceAll('_', ' ') : label;
}

class _ExportCard extends StatelessWidget {
  const _ExportCard({required this.export, required this.onDownload});

  final AuditExport export;
  final void Function(AuditExport) onDownload;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final failed = export.status == 'failed';
    return Card(
      key: const ValueKey('audit-export-card'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            if (!export.isDone)
              const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
            else
              Icon(
                failed ? Icons.error_outline : Icons.check_circle_outline,
                color: failed ? context.semantic.danger : context.semantic.success,
              ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'admin2.audit.exportStatus.${export.status}'.tr(args: [export.format.toUpperCase()]),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (export.isReady && export.rowCount != null)
                    Text(
                      export.truncated
                          ? 'admin2.audit.rowsTruncated'.tr(args: ['${export.rowCount}'])
                          : 'admin2.audit.rows'.tr(args: ['${export.rowCount}']),
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            if (export.isReady)
              FilledButton.tonal(onPressed: () => onDownload(export), child: Text('admin2.audit.download'.tr())),
          ],
        ),
      ),
    );
  }
}

/// Event, record type, platform and dates. Options come from the server.
class AuditFilterSheet extends ConsumerStatefulWidget {
  const AuditFilterSheet({super.key, required this.initial});

  final AuditQuery initial;

  @override
  ConsumerState<AuditFilterSheet> createState() => _AuditFilterSheetState();
}

final auditFilterOptionsProvider = FutureProvider.autoDispose<AuditFilterOptions>(
  (ref) => ref.read(adminRepositoryProvider).auditFilters(),
);

class _AuditFilterSheetState extends ConsumerState<AuditFilterSheet> {
  late String? _event = widget.initial.event;
  late String? _model = widget.initial.model;
  late String? _platform = widget.initial.platform;
  late DateTime? _from = widget.initial.from;
  late DateTime? _to = widget.initial.to;

  @override
  Widget build(BuildContext context) {
    final options = ref.watch(auditFilterOptionsProvider).valueOrNull ?? const AuditFilterOptions();
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, keyboard + AppSpacing.lg),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'admin2.audit.filters'.tr(),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.lg),
              DropdownButtonFormField<String?>(
                initialValue: options.events.contains(_event) ? _event : null,
                isExpanded: true,
                decoration: InputDecoration(labelText: 'admin2.audit.eventLabel'.tr()),
                items: [
                  DropdownMenuItem<String?>(value: null, child: Text('admin2.audit.any'.tr())),
                  for (final e in options.events) DropdownMenuItem<String?>(value: e, child: Text(auditEventLabel(e))),
                ],
                onChanged: (v) => setState(() => _event = v),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String?>(
                initialValue: options.models.any((m) => m.$1 == _model) ? _model : null,
                isExpanded: true,
                decoration: InputDecoration(labelText: 'admin2.audit.record'.tr()),
                items: [
                  DropdownMenuItem<String?>(value: null, child: Text('admin2.audit.any'.tr())),
                  for (final m in options.models) DropdownMenuItem<String?>(value: m.$1, child: Text(m.$2)),
                ],
                onChanged: (v) => setState(() => _model = v),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String?>(
                initialValue: _platform,
                decoration: InputDecoration(labelText: 'admin2.audit.platform'.tr()),
                items: [
                  DropdownMenuItem<String?>(value: null, child: Text('admin2.audit.any'.tr())),
                  for (final p in const ['android', 'ios', 'web']) DropdownMenuItem<String?>(value: p, child: Text(p)),
                ],
                onChanged: (v) => setState(() => _platform = v),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: AppDateField(
                      compact: true,
                      label: 'common.from'.tr(),
                      value: _from,
                      lastDate: _to ?? DateTime.now(),
                      clearable: true,
                      onChanged: (d) => setState(() => _from = d),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: AppDateField(
                      compact: true,
                      label: 'common.to'.tr(),
                      value: _to,
                      firstDate: _from ?? DateTime(2015),
                      lastDate: DateTime.now(),
                      clearable: true,
                      onChanged: (d) => setState(() => _to = d),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(AuditQuery(q: widget.initial.q)),
                      child: Text('activity2.clear'.tr()),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(
                        AuditQuery(
                          q: widget.initial.q,
                          event: _event,
                          model: _model,
                          platform: _platform,
                          actor: widget.initial.actor,
                          from: _from,
                          to: _to,
                        ),
                      ),
                      child: Text('activity2.apply'.tr()),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
