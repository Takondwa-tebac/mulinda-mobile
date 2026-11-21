import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/core/notifications/push_service.dart';
import 'package:mulinda_mobile/core/router/routes.dart';
import 'package:mulinda_mobile/features/admin/data/admin_repository.dart';
import 'package:mulinda_mobile/features/admin/data/audit_models.dart';
import 'package:mulinda_mobile/features/admin/screens/audit_detail_screen.dart';
import 'package:mulinda_mobile/features/admin/screens/audit_trail_screen.dart';

final _now = DateTime.now().toUtc().toIso8601String();

Map<String, dynamic> _row(int id, String event, String icon) => {
  'id': id,
  'event': event,
  'icon': icon,
  'actor': {'id': 'u1', 'name': 'Demo Admin', 'email': 'admin@example.com', 'role': 'admin'},
  'subject': {'type': 'Budget', 'id': 'b$id', 'label': 'Transport'},
  'platform': 'android',
  'created_at': _now,
};

final _detail = {
  'id': 7,
  'event': 'updated',
  'icon': 'updated',
  'created_at': _now,
  'sections': {
    'actor': {'id': 'u1', 'name': 'Demo Admin', 'email': 'admin@example.com', 'role': 'admin'},
    'action': {
      'event': 'updated',
      'label': 'Budget updated',
      'subject_type': 'Budget',
      'subject_id': 'b7',
      'subject_label': 'Transport',
    },
    'changes': [
      {'field': 'limit', 'label': 'Limit', 'old': 'MK 30,000.00', 'new': 'MK 35,000.00'},
    ],
    'device': {'platform': 'android', 'app_version': '1.1.2+6', 'os_version': 'Android 14', 'user_agent': 'Dart/3.10'},
    'network': {'ip_address': '102.70.0.1'},
    'request': {'method': 'PUT', 'url': 'https://api.test/v1/budgets/b7', 'request_id': 'req-123'},
    'meta': {'tags': <String>[], 'auditable_type': 'Budget', 'auditable_id': 'b7'},
  },
};

class _FakeAdmin extends AdminRepository {
  _FakeAdmin() : super(Dio());

  final queries = <AuditQuery>[];
  int exportChecks = 0;
  String? exportFormat;

  @override
  Future<AuditPage> audits(AuditQuery query, {int page = 1, int perPage = 25}) async {
    queries.add(query);
    return AuditPage.fromJson({
      'data': [_row(7, 'updated', 'updated'), _row(6, 'login_failed', 'login_failed')],
      'meta': {'current_page': 1, 'last_page': 1},
    });
  }

  @override
  Future<AuditDetail> audit(String id) async => AuditDetail.fromJson(_detail);

  @override
  Future<AuditFilterOptions> auditFilters() async => AuditFilterOptions.fromJson(const {
    'events': ['updated'],
    'models': [
      {'type': 'Budget', 'label': 'Budget'},
    ],
  });

  @override
  Future<AuditExport> startAuditExport(String format, AuditQuery query) async {
    exportFormat = format;
    return AuditExport.fromJson({'id': 'e1', 'status': 'queued', 'format': format});
  }

  @override
  Future<AuditExport> auditExport(String id) async {
    exportChecks++;
    return AuditExport.fromJson({
      'id': id,
      'status': exportChecks > 1 ? 'ready' : 'processing',
      'format': exportFormat ?? 'csv',
      'row_count': 42,
      'download_url': exportChecks > 1 ? 'https://api.test/download?signature=x' : null,
    });
  }
}

Future<_FakeAdmin> _pump(WidgetTester tester, Widget home) async {
  final fake = _FakeAdmin();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [adminRepositoryProvider.overrideWithValue(fake)],
      child: MaterialApp(home: home),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return fake;
}

void main() {
  test('list rows and details are read from the contract shapes', () {
    final page = AuditPage.fromJson({
      'data': [_row(1, 'login', 'login')],
      'meta': {'current_page': 1, 'last_page': 3},
    });
    expect(page.hasMore, isTrue);
    expect(page.items.single.actor?.email, 'admin@example.com');
    expect(page.items.single.subject.label, 'Transport');

    final d = AuditDetail.fromJson(_detail);
    expect(d.changes.single.oldValue, 'MK 30,000.00');
    expect(d.request['request_id'], 'req-123');
    expect(AuditDetail.fromJson(const {'id': 1}).changes, isEmpty);
  });

  test('each icon key has its own icon', () {
    expect(auditIcon('deleted'), Icons.delete_outline);
    expect(auditIcon('login_failed'), Icons.gpp_bad_outlined);
    expect(auditIcon('something_new'), Icons.history);
  });

  test('the export-ready push opens the audit log on that export', () {
    expect(auditExportLocation('e1'), '${Routes.adminAudit}?export=e1');
    expect(auditExportLocation(null), Routes.adminAudit);
  });

  testWidgets('the list shows entries and opens the detail with its changes', (tester) async {
    await _pump(tester, const AuditTrailScreen());
    expect(find.byType(AuditTile), findsNWidgets(2));
    expect(find.byIcon(Icons.gpp_bad_outlined), findsOneWidget);

    await tester.tap(find.byType(AuditTile).first);
    await tester.pumpAndSettle();
    expect(find.byType(AuditDetailScreen), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('audit-changes')),
      200,
      scrollable: find.descendant(of: find.byType(AuditDetailScreen), matching: find.byType(Scrollable)).first,
    );
    expect(find.byKey(const ValueKey('audit-changes')), findsOneWidget);
    expect(find.text('MK 35,000.00'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('req-123'),
      200,
      scrollable: find.descendant(of: find.byType(AuditDetailScreen), matching: find.byType(Scrollable)).first,
    );
    expect(find.text('req-123'), findsOneWidget);
  });

  testWidgets('an export is started, polled and offers the download when ready', (tester) async {
    final fake = await _pump(tester, const AuditTrailScreen());
    await tester.tap(find.byKey(const ValueKey('audit-export')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('admin2.audit.exportCsv'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(fake.exportFormat, 'csv');
    expect(find.byKey(const ValueKey('audit-export-card')), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('admin2.audit.download'), findsOneWidget);

    // Leave no polling timer behind.
    await tester.pumpWidget(const SizedBox());
  });
}
