import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/core/security/screenshot_protection.dart';
import 'package:mulinda_mobile/core/widgets/app_sheet.dart';
import 'package:mulinda_mobile/features/auth/data/user.dart';
import 'package:mulinda_mobile/features/auth/providers/auth_controller.dart';
import 'package:mulinda_mobile/features/referral/data/referral_repository.dart';
import 'package:mulinda_mobile/features/referral/screens/referral_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A phone with a gesture bar (bottom inset) and a status bar (top inset).
const _gestureBar = 24.0;
const _statusBar = 32.0;

Future<void> _setScreen(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: _statusBar, bottom: _gestureBar);
  tester.view.viewPadding = const FakeViewPadding(top: _statusBar, bottom: _gestureBar);
  addTearDown(tester.view.reset);
}

Widget _app({required Widget home, double textScale = 1, Brightness brightness = Brightness.light}) => MaterialApp(
  theme: ThemeData(brightness: brightness),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: home,
);

Widget _opener(void Function(BuildContext) open) => Scaffold(
  body: Builder(
    builder: (context) => Center(
      child: TextButton(onPressed: () => open(context), child: const Text('open')),
    ),
  ),
);

void _openSheet(BuildContext context, int lines) => showAppSheet<void>(
  context,
  builder: (_) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [for (var i = 0; i < lines; i++) Text('line $i', key: ValueKey('line-$i'))],
  ),
  footer: (sheet) => FilledButton(
    key: const ValueKey('footer'),
    onPressed: () => Navigator.of(sheet).pop(),
    child: const Text('Done'),
  ),
);

/// The footer is fully on screen and above the gesture bar.
void _expectAboveGestureBar(WidgetTester tester, Finder finder, Size screen) {
  final rect = tester.getRect(finder);
  expect(rect.top, greaterThanOrEqualTo(_statusBar));
  expect(rect.bottom, lessThanOrEqualTo(screen.height - _gestureBar));
}

final _info = ReferralInfo.fromJson({
  'code': 'CHSM27',
  'link': 'https://mulinda-api.sukulusmis.africa/i/CHSM27',
  'signed_up': 3,
  'rewarded': 2,
  'days_earned': 14,
  'reward_days': 7,
});

void main() {
  group('app sheet', () {
    testWidgets('short content: sized to it, footer above the gesture bar', (tester) async {
      const screen = Size(360, 780);
      await _setScreen(tester, screen);
      await tester.pumpWidget(_app(home: _opener((c) => _openSheet(c, 3))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('app-sheet-draggable')), findsNothing);
      _expectAboveGestureBar(tester, find.byKey(const ValueKey('footer')), screen);
      expect(tester.getRect(find.byType(BottomSheet)).top, greaterThan(screen.height / 2));
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('footer')));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
    });

    for (final (name, size, scale) in [
      ('landscape at 1.3x text', const Size(780, 360), 1.3),
      ('a small phone at 1.3x text', const Size(320, 568), 1.3),
    ]) {
      testWidgets('tall content on $name: opens part way, drags up, scrolls, footer reachable', (tester) async {
        await _setScreen(tester, size);
        await tester.pumpWidget(_app(home: _opener((c) => _openSheet(c, 40)), textScale: scale));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('app-sheet-draggable')), findsOneWidget);
        expect(tester.takeException(), isNull);
        final sheet = find.byType(BottomSheet);
        final startTop = tester.getRect(sheet).top;
        // Never under the status bar.
        expect(startTop, greaterThanOrEqualTo(_statusBar));

        // Drag up: the sheet grows.
        await tester.drag(find.byKey(const ValueKey('line-0')), const Offset(0, -150));
        await tester.pumpAndSettle();
        expect(tester.getRect(sheet).top, lessThan(startTop));
        expect(tester.getRect(sheet).top, greaterThanOrEqualTo(_statusBar));

        // The last line can be scrolled to.
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('line-39')),
          100,
          scrollable: find.descendant(
            of: find.byKey(const ValueKey('app-sheet-scroll')),
            matching: find.byType(Scrollable),
          ),
        );
        expect(find.byKey(const ValueKey('line-39')), findsOneWidget);

        // The footer stays tappable above the gesture bar.
        _expectAboveGestureBar(tester, find.byKey(const ValueKey('footer')), size);
        await tester.tap(find.byKey(const ValueKey('footer')));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
      });
    }
  });

  group('referral sheets', () {
    Widget screen({double textScale = 1, Brightness brightness = Brightness.light}) => ProviderScope(
      overrides: [
        referralInfoProvider.overrideWith((ref) async => _info),
        currentUserProvider.overrideWithValue(null),
      ],
      child: _app(home: const ReferralScreen(), textScale: textScale, brightness: brightness),
    );

    for (final (name, size, scale, brightness) in [
      ('A34 portrait, light', const Size(412, 915), 1.0, Brightness.light),
      ('A34 portrait at 1.3x, dark', const Size(412, 915), 1.3, Brightness.dark),
      ('small phone at 1.3x', const Size(320, 568), 1.3, Brightness.light),
      ('landscape at 1.3x', const Size(915, 412), 1.3, Brightness.dark),
    ]) {
      testWidgets('QR sheet fits on $name', (tester) async {
        SharedPreferences.setMockInitialValues({});
        await _setScreen(tester, size);
        await tester.pumpWidget(screen(textScale: scale, brightness: brightness));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('referral-qr')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('referral-qr-code')), findsOneWidget);
        expect(find.text('CHSM27'), findsWidgets);

        final scrollable = find.descendant(
          of: find.byKey(const ValueKey('app-sheet-scroll')),
          matching: find.byType(Scrollable),
        );
        for (final key in ['referral-qr-save', 'referral-qr-share']) {
          await tester.scrollUntilVisible(find.byKey(ValueKey(key)), 80, scrollable: scrollable);
          final button = tester.getRect(find.byKey(ValueKey(key)));
          expect(button.height, greaterThanOrEqualTo(44));
          expect(button.bottom, lessThanOrEqualTo(size.height - _gestureBar));
        }

        final done = find.byKey(const ValueKey('referral-sheet-done'));
        await tester.scrollUntilVisible(done, 80, scrollable: scrollable, maxScrolls: 100);
        _expectAboveGestureBar(tester, done, size);
        await tester.tap(done);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('referral-qr-code')), findsNothing);
      });
    }

    for (final key in ['referral-how', 'referral-signed-up', 'referral-days-earned']) {
      testWidgets('$key sheet closes with Done on a small phone at 1.3x', (tester) async {
        SharedPreferences.setMockInitialValues({});
        const size = Size(320, 568);
        await _setScreen(tester, size);
        await tester.pumpWidget(screen(textScale: 1.3));
        await tester.pumpAndSettle();

        // Scroll the row well clear of the pinned invite buttons.
        final row = find.byKey(ValueKey(key));
        await tester.scrollUntilVisible(row, 80, scrollable: find.byType(Scrollable).first);
        if (key == 'referral-how') {
          await tester.drag(find.byType(ListView), const Offset(0, -200));
          await tester.pumpAndSettle();
        }
        await tester.tap(row);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final done = find.byKey(const ValueKey('referral-sheet-done'));
        _expectAboveGestureBar(tester, done, size);
        await tester.tap(done);
        await tester.pumpAndSettle();
        expect(done, findsNothing);
      });
    }
  });

  group('screenshots on the referral screen', () {
    test('allowed while an exempt screen is open, protected otherwise', () {
      expect(effectiveScreenshotProtection(protectedSetting: true, exemptions: 0), isTrue);
      expect(effectiveScreenshotProtection(protectedSetting: true, exemptions: 1), isFalse);
      expect(effectiveScreenshotProtection(protectedSetting: true, exemptions: 2), isFalse);
      // A super-admin who switched protection off stays unprotected.
      expect(effectiveScreenshotProtection(protectedSetting: false, exemptions: 0), isFalse);
    });

    testWidgets('opening the screen lifts FLAG_SECURE and leaving restores it', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final calls = <bool>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('mulinda/screen_security'),
        (call) async {
          if (call.method == 'setSecure') calls.add((call.arguments as Map)['secure'] as bool);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('mulinda/screen_security'),
          null,
        ),
      );

      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            referralInfoProvider.overrideWith((ref) async => _info),
            currentUserProvider.overrideWithValue(
              const User(
                id: 'u1',
                firstName: 'Test',
                lastName: 'User',
                username: 'test',
                email: 't@example.com',
                fullName: 'Test User',
              ),
            ),
          ],
          child: MaterialApp(
            navigatorKey: navigatorKey,
            builder: (context, child) => ScreenshotGuard(child: child!),
            home: const Scaffold(body: Text('home')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, [true]);

      navigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => const ReferralScreen()));
      await tester.pumpAndSettle();
      expect(calls.last, isFalse);

      // A sheet on top keeps screenshots allowed (people screenshot the QR).
      await tester.tap(find.byKey(const ValueKey('referral-qr')));
      await tester.pumpAndSettle();
      expect(calls.last, isFalse);
      await tester.tap(find.byKey(const ValueKey('referral-sheet-done')));
      await tester.pumpAndSettle();

      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(calls.last, isTrue);
      expect(calls, [true, false, true]);
    });
  });
}
