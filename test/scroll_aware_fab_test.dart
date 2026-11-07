import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mulinda_mobile/core/network/dio_client.dart';
import 'package:mulinda_mobile/core/offline/offline_status.dart';
import 'package:mulinda_mobile/core/theme/app_theme.dart';
import 'package:mulinda_mobile/core/widgets/scroll_aware_fab.dart';
import 'package:mulinda_mobile/features/activity/data/activity_models.dart';
import 'package:mulinda_mobile/features/activity/data/activity_repository.dart';
import 'package:mulinda_mobile/features/activity/screens/activity_screen.dart';
import 'package:mulinda_mobile/features/auth/providers/auth_controller.dart';
import 'package:mulinda_mobile/features/capture/data/inbox_repository.dart';
import 'package:mulinda_mobile/features/dashboard/data/dashboard_models.dart';
import 'package:mulinda_mobile/features/dashboard/data/dashboard_repository.dart';
import 'package:mulinda_mobile/features/shell/app_shell.dart';

const _fabKey = ValueKey('fab');
const _delay = Duration(milliseconds: 650);

/// A screen shaped like the app's: a scope around the Scaffold, a long
/// vertical list, a horizontal strip, and a scroll-aware button.
Widget _screen({bool reduced = false, bool screenReader = false, VoidCallback? onTap}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(size: const Size(400, 800), disableAnimations: reduced, accessibleNavigation: screenReader),
    child: ScrollAwareFabScope(
      child: Scaffold(
        body: ListView(
          children: [
            SizedBox(
              height: 60,
              child: ListView(
                key: const ValueKey('strip'),
                scrollDirection: Axis.horizontal,
                children: [for (var i = 0; i < 30; i++) SizedBox(width: 80, child: Text('chip $i'))],
              ),
            ),
            for (var i = 0; i < 80; i++) SizedBox(height: 56, child: Text('row $i')),
          ],
        ),
        floatingActionButton: ScrollAwareFab(
          child: FloatingActionButton(key: _fabKey, onPressed: onTap ?? () {}, child: const Icon(Icons.add)),
        ),
      ),
    ),
  ),
);

bool _ignored(WidgetTester tester) => tester
    .widget<IgnorePointer>(find.ancestor(of: find.byKey(_fabKey), matching: find.byType(IgnorePointer)).first)
    .ignoring;

double _opacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(find.ancestor(of: find.byKey(_fabKey), matching: find.byType(AnimatedOpacity)))
    .opacity;

/// Drag the main list up by [dy] with the finger kept down (no fling).
Future<TestGesture> _dragAndHold(WidgetTester tester, double dy) async {
  final gesture = await tester.startGesture(tester.getCenter(find.text('row 5')));
  for (var i = 0; i < 6; i++) {
    await gesture.moveBy(Offset(0, -dy / 6));
    await tester.pump(const Duration(milliseconds: 16));
  }
  return gesture;
}

void main() {
  testWidgets('hides once a drag passes the threshold, not before', (tester) async {
    await tester.pumpWidget(_screen());
    expect(_opacity(tester), 1);

    final small = await _dragAndHold(tester, 6);
    await tester.pump();
    expect(_opacity(tester), 1, reason: 'a small jitter should not hide it');
    await small.up();
    await tester.pumpAndSettle();

    final big = await _dragAndHold(tester, 200);
    await tester.pump();
    expect(_opacity(tester), 0);
    expect(_ignored(tester), isTrue);
    await big.up();
    await tester.pump(_delay);
    await tester.pumpAndSettle();
  });

  testWidgets('comes back after scrolling pauses', (tester) async {
    await tester.pumpWidget(_screen());
    final g = await _dragAndHold(tester, 200);
    await g.up();
    await tester.pumpAndSettle(); // fling settles, timer still pending
    expect(_opacity(tester), 0);

    await tester.pump(_delay);
    await tester.pumpAndSettle();
    expect(_opacity(tester), 1);
    expect(_ignored(tester), isFalse);
  });

  testWidgets('shows at once when scrolled back to the top', (tester) async {
    await tester.pumpWidget(_screen());
    final g = await _dragAndHold(tester, 200);
    await g.moveBy(const Offset(0, 400));
    await tester.pump();
    expect(_opacity(tester), 1);
    await g.up();
    await tester.pumpAndSettle();
  });

  testWidgets('horizontal scrolling does not hide it', (tester) async {
    await tester.pumpWidget(_screen());
    await tester.drag(find.byKey(const ValueKey('strip')), const Offset(-300, 0));
    await tester.pump();
    expect(_opacity(tester), 1);
    await tester.pumpAndSettle();
  });

  testWidgets('switches instantly with reduced motion', (tester) async {
    await tester.pumpWidget(_screen(reduced: true));
    final g = await _dragAndHold(tester, 200);
    await tester.pump();
    final slide = tester.widget<AnimatedSlide>(
      find.ancestor(of: find.byKey(_fabKey), matching: find.byType(AnimatedSlide)),
    );
    expect(slide.duration, Duration.zero);
    expect(_opacity(tester), 0);
    await g.up();
    await tester.pump(_delay);
    await tester.pumpAndSettle();
  });

  testWidgets('stays visible for screen-reader users', (tester) async {
    await tester.pumpWidget(_screen(screenReader: true));
    final g = await _dragAndHold(tester, 200);
    await tester.pump();
    expect(_opacity(tester), 1);
    expect(_ignored(tester), isFalse);
    await g.up();
    await tester.pump(_delay);
    await tester.pumpAndSettle();
  });

  testWidgets('cannot be tapped while hidden', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_screen(onTap: () => taps++));
    final g = await _dragAndHold(tester, 200);
    await tester.pump(const Duration(milliseconds: 100)); // mid-fade
    await tester.tap(find.byKey(_fabKey), warnIfMissed: false);
    expect(taps, 0);
    await g.up();
    await tester.pump(_delay);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_fabKey));
    expect(taps, 1);
  });

  testWidgets('scrolling the Activity list hides the shell capture button', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    Map<String, dynamic> money(int major) => {
      'minor_units': major * 100,
      'currency': 'MWK',
      'amount': major,
      'formatted': 'MK $major.00',
    };
    final now = DateTime.now();
    final txns = [
      for (var i = 0; i < 40; i++)
        Txn.fromJson({
          'id': 't$i',
          'type': 'expense',
          'merchant': 'Shop $i',
          'amount': money(100 + i),
          'occurred_at': now.subtract(Duration(hours: i * 5)).toIso8601String(),
        }),
    ];

    final router = GoRouter(
      initialLocation: '/activity',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => AppShell(navigationShell: shell),
          branches: [
            for (final path in ['/home', '/activity', '/plan', '/profile'])
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: path,
                    builder: (_, _) => path == '/activity' ? const ActivityScreen() : Scaffold(body: Text(path)),
                  ),
                ],
              ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dioProvider.overrideWithValue(Dio()..httpClientAdapter = _Offline()),
          offlineBannerVisibleProvider.overrideWith((ref) => false),
          currentUserProvider.overrideWith((ref) => null),
          transactionsProvider.overrideWith((ref) async => txns),
          accountsProvider.overrideWith((ref) async => const <Account>[]),
          reviewTransactionsProvider.overrideWith((ref) async => const <Txn>[]),
          categoriesProvider.overrideWith((ref) async => const <Category>[]),
          pendingCountProvider.overrideWith((ref) => 0),
          dashboardProvider.overrideWith((ref) async => DashboardSummary.fromJson(const {})),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    double fabOpacity() => tester
        .widget<AnimatedOpacity>(
          find.ancestor(of: find.byType(FloatingActionButton), matching: find.byType(AnimatedOpacity)),
        )
        .opacity;

    expect(fabOpacity(), 1);
    final gesture = await tester.startGesture(tester.getCenter(find.text('Shop 3')));
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(fabOpacity(), 0);
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.pump(_delay);
    await tester.pumpAndSettle();
    expect(fabOpacity(), 1);

    // The Plan tab has no capture button (it uses its app-bar "+").
    await tester.tap(find.text('nav.plan'));
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsNothing);
  });
}

/// Answers every request with an empty body, so nothing reaches the network.
class _Offline implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async =>
      ResponseBody.fromString(
        jsonEncode({'data': null}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}
