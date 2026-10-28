import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/guardian/presentation/widgets/signup_consent_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app/app.dart';
import 'package:app/features/onboarding/presentation/splash_screen.dart';

/// Marks the root so a test can rasterise whatever is on screen.
const appRootKey = Key('app-root');

/// Pumps the real [App] (router + theme) inside a ProviderScope so tests can
/// drive the actual navigation flow. Pass [overrides] to inject fakes.
///
/// Does not settle: the splash loops its tap-prompt animation forever, so
/// `pumpAndSettle` would spin until it times out. Screens reached after the
/// splash can be settled normally.
///
/// Note: In Riverpod 3.x [Override] is not publicly exported; callers pass
/// values produced by `provider.overrideWith(...)` / `provider.overrideWithValue(...)`,
/// which implement the internal Override interface accepted by [ProviderScope].
Future<void> pumpApp(
  WidgetTester tester, {
  List<Object> overrides = const [],
  Map<String, Object> prefs = const {},
}) async {
  // Settings now go through shared_preferences, whose platform channel does
  // not exist under `flutter test` — without a mock store every save throws
  // and navigation stalls on the screen-mode choice. Pass [prefs] to start the
  // app as though a previous run had already saved something.
  //
  // The reset matters: SharedPreferences caches its instance for the life of
  // the isolate, so without it the second test in a file silently reads the
  // first test's store and passes for the wrong reason.
  SharedPreferences.resetStatic();
  SharedPreferences.setMockInitialValues(prefs);

  // The screens are laid out for a phone; the 800x600 default would push the
  // illustration off the top.
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  // Tear the previous tree down first. Pumping a second App straight over the
  // first updates the existing elements instead of replacing them, so the
  // ProviderScope keeps its container and the router keeps its stack: the new
  // overrides and the new prefs are read by nobody and the test quietly
  // re-examines the first app. That is how every 아주 크게 screenshot came out
  // byte-identical to its normal-size twin.
  await tester.pumpWidget(const SizedBox.shrink());

  await tester.pumpWidget(
    RepaintBoundary(
      key: appRootKey,
      child: ProviderScope(
        // ignore: invalid_use_of_internal_member
        overrides: overrides.cast(),
        child: const App(),
      ),
    ),
  );
  await tester.pump();
}

/// Advances past the splash's entering pause and the route transition that
/// follows it, leaving the splash disposed so later `pumpAndSettle` calls are
/// safe.
Future<void> settleAfterSplashTap(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(SplashScreen.enteringPause);
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// Lets the hand finish swinging up before anything touches it.
///
/// The illustration enters tilted and rotates upright, and the tap target
/// rides along with it — mid-swing it is somewhere off to the left, which is
/// not where a test aiming at it expects to find it.
Future<void> settleSplashEntrance(WidgetTester tester) =>
    tester.pump(SplashScreen.entrance + const Duration(milliseconds: 50));

/// Taps the phone in the illustration and lands on the screen-mode choice.
Future<void> enterSeniorFlow(WidgetTester tester) async {
  await pumpApp(tester);
  await settleSplashEntrance(tester);
  await tester.tap(find.byKey(SplashScreen.tapTargetKey));
  await settleAfterSplashTap(tester);
}

/// Walks the 약관 동의 sheet every way in now raises.
///
/// Added in bulk rather than per test: the sheet sits in front of **all
/// three** providers, so every path that reached a provider screen before
/// 2026-10-28 goes through here now.
Future<void> agreeToTerms(WidgetTester tester) async {
  await tester.tap(find.byKey(SignupConsentSheet.allKey));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(SignupConsentSheet.continueKey));
  await tester.pumpAndSettle();
}
