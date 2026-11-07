import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/core/money/money_json.dart';
import 'package:mulinda_mobile/core/theme/app_theme.dart';
import 'package:mulinda_mobile/features/onboarding/screens/onboarding_screen.dart';
import 'package:mulinda_mobile/features/onboarding/widgets/onboarding_illustrations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FileLoader extends AssetLoader {
  const _FileLoader();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('assets/translations/${locale.languageCode}.json').readAsStringSync()) as Map<String, dynamic>;
}

Future<void> _pump(WidgetTester tester, {bool reduced = false}) async {
  tester.view.physicalSize = const Size(360 * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.runAsync(() async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('ny')],
        startLocale: const Locale('en'),
        fallbackLocale: const Locale('en'),
        path: 'assets/translations',
        assetLoader: const _FileLoader(),
        child: Builder(
          builder: (context) => MaterialApp(
            theme: AppTheme.light,
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: child!,
            ),
            home: const OnboardingScreen(),
          ),
        ),
      ),
    );
    // Let the translations load.
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });
}

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.byType(FilledButton));
  await tester.pumpAndSettle();
}

/// The dot's own width (without its 4 px side margins).
double _dotWidth(WidgetTester tester, int i) => tester
    .getSize(find.descendant(of: find.byKey(ValueKey('onboarding-dot-$i')), matching: find.byType(DecoratedBox)))
    .width;

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    // Lay out with the app's real font (the test font draws every glyph as a wide box).
    final inter = FontLoader('Inter');
    for (final w in [400, 500, 600, 700]) {
      inter.addFont(Future.value(ByteData.sublistView(File('assets/fonts/Inter-$w.ttf').readAsBytesSync())));
    }
    await inter.load();
  });

  testWidgets('each slide plays to its final state', (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();

    // Slide 1: the balance has counted all the way up.
    expect(find.text(formatMoney(kDemoBalance, 'MWK')), findsOneWidget);

    // Slide 2: the suggested category ends confirmed.
    await _next(tester);
    expect(find.byKey(const ValueKey('onboarding-chip-confirmed')), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding-chip-suggested')), findsNothing);
    expect(find.text('Food'), findsOneWidget);

    // Slide 3: the goal ring reaches 60% and the pill shows what is left.
    await _next(tester);
    expect(find.text('60%'), findsOneWidget);
    expect(find.text('${formatMoney(kDemoGoalLeft, 'MWK')} to go'), findsOneWidget);

    // Slide 4: the trial benefits and the honest "no card" line.
    await _next(tester);
    expect(find.text('Unlimited SMS capture'), findsOneWidget);
    expect(find.text('No card. Nothing renews by itself.'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
  });

  testWidgets('slide 2 shows the suggestion before confirming it', (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    // Part-way: the page has turned and the chip has popped in as a question.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 1300));
    expect(find.byKey(const ValueKey('onboarding-chip-suggested')), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('onboarding-chip-confirmed')), findsOneWidget);
  });

  testWidgets('with reduced motion the final state shows on the first frame', (tester) async {
    await _pump(tester, reduced: true);
    await tester.pump();

    expect(find.text(formatMoney(kDemoBalance, 'MWK')), findsOneWidget);

    // The next slide is already finished as soon as the page has turned
    // (normally its chip confirms ~2.4 s in).
    await tester.pumpAndSettle();
    final before = tester.binding.clock.now();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('onboarding-chip-confirmed')), findsOneWidget);
    // Only the page turn took time, not the slide's 2.4 s timeline.
    expect(tester.binding.clock.now().difference(before), lessThan(const Duration(milliseconds: 1000)));
  });

  testWidgets('the active page dot widens to a pill', (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();
    expect(_dotWidth(tester, 0), 24);
    expect(_dotWidth(tester, 1), 8);

    await _next(tester);
    expect(_dotWidth(tester, 0), 8);
    expect(_dotWidth(tester, 1), 24);
  });

  testWidgets('a slide replays when you come back to it', (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();
    await _next(tester);

    await tester.drag(find.byType(PageView), const Offset(400, 0));
    await tester.pump(const Duration(milliseconds: 350));
    // Counting up again from the start, not yet at the final amount.
    expect(find.text(formatMoney(kDemoBalance, 'MWK')), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text(formatMoney(kDemoBalance, 'MWK')), findsOneWidget);
  });

  test('timeline windows ease from 0 to 1', () {
    expect(seg(0.1, 0.2, 0.4), 0);
    expect(seg(0.5, 0.2, 0.4), 1);
    expect(seg(0.3, 0.2, 0.4), greaterThan(0.5)); // ease-out is ahead at the midpoint
  });
}
