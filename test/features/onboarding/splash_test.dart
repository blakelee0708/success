import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/onboarding/presentation/splash_screen.dart';

import '../../support/pump_app.dart';

void main() {
  /// The tap target rides up with the hand, so a tap aimed at it mid-swing
  /// misses the widget entirely — which means a test that taps and checks
  /// nothing happened passes whether the gate exists or not. Read the handler
  /// instead.
  GestureDetector phone(WidgetTester tester) =>
      tester.widget<GestureDetector>(find.byKey(SplashScreen.tapTargetKey));

  testWidgets('the phone does not answer while it is still swinging up', (
    tester,
  ) async {
    // Nothing invites the tap yet either — the screen is dark until the hand
    // arrives — because a control that asks to be pressed and then ignores
    // the press is worse than one that waits.
    await pumpApp(tester);

    expect(phone(tester).onTap, isNull);
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      0,
    );
  });

  testWidgets('and answers once it has arrived', (tester) async {
    await pumpApp(tester);
    await settleSplashEntrance(tester);

    expect(phone(tester).onTap, isNotNull);
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      1,
    );
  });

  testWidgets('splash shows the wordmark, tagline and tap prompt', (
    tester,
  ) async {
    await pumpApp(tester);

    expect(find.text('잘보이네'), findsOneWidget);
    expect(find.text('크게 보고 쉽게 쓰는'), findsOneWidget);
    expect(find.text('눌러보세요'), findsOneWidget);
    expect(find.text('스마트폰이\n쉬워져요'), findsOneWidget);
  });

  testWidgets('splash offers the guardian card instead of a 시작하기 button', (
    tester,
  ) async {
    await pumpApp(tester);

    expect(find.text('가족 및 보호자분들은'), findsOneWidget);
    expect(find.text('여기를 눌러주세요'), findsOneWidget);
    // The large CTA is replaced by the phone inside the illustration.
    expect(find.text('시작하기'), findsNothing);
  });

  testWidgets('tapping the phone shows the entering state before navigating', (
    tester,
  ) async {
    await pumpApp(tester);

    await settleSplashEntrance(tester);
    await tester.tap(find.byKey(SplashScreen.tapTargetKey));
    await tester.pump();

    expect(find.text('준비하고 있어요\n잠시만 기다려 주세요'), findsOneWidget);
    expect(find.text('눌러보세요'), findsNothing);
    // Still on the splash — the pause is what tells the user the tap landed.
    expect(find.text('화면을 골라주세요'), findsNothing);

    // Let the queued navigation run so the test does not end mid-timer.
    await settleAfterSplashTap(tester);
  });

  testWidgets('the entering state gives way to the screen-mode choice', (
    tester,
  ) async {
    await pumpApp(tester);

    await settleSplashEntrance(tester);
    await tester.tap(find.byKey(SplashScreen.tapTargetKey));
    await settleAfterSplashTap(tester);

    expect(find.text('화면을 골라주세요'), findsOneWidget);
  });

  testWidgets('tapping twice while entering only navigates once', (
    tester,
  ) async {
    await pumpApp(tester);

    await settleSplashEntrance(tester);
    await tester.tap(find.byKey(SplashScreen.tapTargetKey));
    await tester.pump();
    await settleSplashEntrance(tester);
    await tester.tap(find.byKey(SplashScreen.tapTargetKey));
    await settleAfterSplashTap(tester);

    expect(find.text('화면을 골라주세요'), findsOneWidget);
  });

  testWidgets('the guardian card opens the guardian start screen', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.byKey(SplashScreen.guardianCardKey));
    await tester.pumpAndSettle();

    // The first of the three intro pages.
    expect(find.text('스마트폰이 어려운 부모님,\n이제 걱정하지 마세요'), findsOneWidget);
  });

  testWidgets("the guardian card clears the phone's own navigation bar", (
    tester,
  ) async {
    // Found on a real Galaxy. This screen is a bare `Stack` filling the
    // window with no `SafeArea`, so a card 34px from the bottom sat 34px from
    // the *physical* edge - underneath the three-button bar, which is where
    // 가족 및 보호자분들은 ended up.
    const bar = 48.0;
    tester.view.viewPadding = const FakeViewPadding(bottom: bar);
    tester.view.padding = const FakeViewPadding(bottom: bar);
    await pumpApp(tester);

    final card = tester.getRect(find.byKey(SplashScreen.guardianCardKey));
    final screen =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(screen - card.bottom, greaterThanOrEqualTo(bar));
  });
}
