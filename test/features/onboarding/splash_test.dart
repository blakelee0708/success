import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/onboarding/presentation/splash_screen.dart';

import '../../support/pump_app.dart';

void main() {
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

    expect(find.text('부모님께 이런 걸\n해드릴 수 있어요'), findsOneWidget);
  });
}
