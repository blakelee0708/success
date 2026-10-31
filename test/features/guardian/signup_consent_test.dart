import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/guardian/data/signup_consent.dart';
import 'package:app/features/guardian/presentation/guardian_start_screen.dart';
import 'package:app/features/onboarding/presentation/splash_screen.dart';
import 'package:app/features/guardian/presentation/widgets/signup_consent_sheet.dart';

import '../../support/pump_app.dart';

/// 약관 동의, before an account can exist.
///
/// The screen had carried one grey line - 시작하면 서비스 이용약관과
/// 개인정보 처리방침에 동의하게 됩니다 - as text, with no link, naming a
/// 이용약관 that did not exist anywhere in the repository. The sign-up form
/// said nothing at all. 개인정보보호법 asks for an act rather than a
/// passage: itemised, 필수 and 선택 apart, each readable first.
Future<InMemorySignupConsentStore> _pumpStart(
  WidgetTester tester, {
  SignupConsent? already,
}) async {
  final store = InMemorySignupConsentStore(already);
  await pumpApp(
    tester,
    overrides: [signupConsentStoreProvider.overrideWithValue(store)],
  );
  // No settle before the tap: the splash animates continuously and
  // `pumpAndSettle` never returns on it, which is why every other test that
  // reaches this screen taps straight away.
  await tester.tap(find.byKey(SplashScreen.guardianCardKey));
  await tester.pumpAndSettle();
  await skipGuardianIntro(tester);
  return store;
}

Future<void> _tapEmail(WidgetTester tester) async {
  await tester.tap(find.byKey(GuardianStartKeys.email));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the start screen no longer claims consent already happened', (
    tester,
  ) async {
    // The old line said 시작하면 ... 동의하게 됩니다, which is the pattern
    // this replaced. Saying it while a sheet also asks would be worse than
    // either on its own.
    await _pumpStart(tester);

    expect(find.textContaining('동의하게 됩니다'), findsNothing);
  });

  testWidgets('every way in raises the sheet, not just the email one', (
    tester,
  ) async {
    // Kakao and Google dead-end in 준비 중 today, which is exactly why they
    // are easy to forget: a consent asked only on the route that finishes
    // is missing from the two a guardian is most likely to press.
    for (final key in [
      GuardianStartKeys.email,
      GuardianStartKeys.kakao,
      GuardianStartKeys.google,
    ]) {
      await _pumpStart(tester);
      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
      expect(
        find.byKey(SignupConsentSheet.sheetKey),
        findsOneWidget,
        reason: '$key did not ask',
      );
    }
  });

  testWidgets('시작하기 is refused until both 필수 are ticked', (tester) async {
    await _pumpStart(tester);
    await _tapEmail(tester);

    final button = find.byKey(SignupConsentSheet.continueKey);
    expect(
      tester
          .widget<Semantics>(
            find.descendant(of: button, matching: find.byType(Semantics)).first,
          )
          .properties
          .enabled,
      isFalse,
    );

    await tester.tap(find.byKey(SignupConsentSheet.termsKey));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Semantics>(
            find.descendant(of: button, matching: find.byType(Semantics)).first,
          )
          .properties
          .enabled,
      isFalse,
      reason: 'one of two is not both',
    );

    await tester.tap(find.byKey(SignupConsentSheet.privacyKey));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Semantics>(
            find.descendant(of: button, matching: find.byType(Semantics)).first,
          )
          .properties
          .enabled,
      isTrue,
    );
  });

  testWidgets('the optional item is not required', (tester) async {
    final store = await _pumpStart(tester);
    await _tapEmail(tester);

    await tester.tap(find.byKey(SignupConsentSheet.termsKey));
    await tester.tap(find.byKey(SignupConsentSheet.privacyKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SignupConsentSheet.continueKey));
    await tester.pumpAndSettle();

    expect(store.consent, isNotNull);
    expect(store.consent!.marketing, isFalse);
  });

  testWidgets('전체 동의 takes the optional one too, and is undoable', (
    tester,
  ) async {
    final store = await _pumpStart(tester);
    await _tapEmail(tester);

    await tester.tap(find.byKey(SignupConsentSheet.allKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SignupConsentSheet.marketingKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SignupConsentSheet.continueKey));
    await tester.pumpAndSettle();

    expect(store.consent!.marketing, isFalse);
  });

  testWidgets('what was agreed to is stored with its version', (tester) async {
    // A bare flag cannot tell an agreement to the old wording from one to
    // the new, and the day the terms change that difference is the whole
    // question.
    final store = await _pumpStart(tester);
    await _tapEmail(tester);
    await tester.tap(find.byKey(SignupConsentSheet.allKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SignupConsentSheet.continueKey));
    await tester.pumpAndSettle();

    expect(store.consent!.version, signupConsentVersion);
    expect(store.consent!.marketing, isTrue);
  });

  testWidgets('agreeing lets the email route through', (tester) async {
    await _pumpStart(tester);
    await _tapEmail(tester);
    await tester.tap(find.byKey(SignupConsentSheet.allKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SignupConsentSheet.continueKey));
    await tester.pumpAndSettle();

    expect(find.byKey(SignupConsentSheet.sheetKey), findsNothing);
    expect(find.byKey(GuardianStartKeys.email), findsNothing);
  });

  testWidgets('a phone that already agreed is not asked again', (tester) async {
    await _pumpStart(
      tester,
      already: SignupConsent(
        version: signupConsentVersion,
        agreedAt: DateTime(2026, 10, 1),
        marketing: false,
      ),
    );
    await _tapEmail(tester);

    expect(find.byKey(SignupConsentSheet.sheetKey), findsNothing);
  });

  testWidgets('an agreement to older wording does not count', (tester) async {
    await _pumpStart(
      tester,
      already: SignupConsent(
        version: signupConsentVersion - 1,
        agreedAt: DateTime(2026, 10, 1),
        marketing: true,
      ),
    );
    await _tapEmail(tester);

    expect(find.byKey(SignupConsentSheet.sheetKey), findsOneWidget);
  });

  testWidgets('dismissing the sheet is a no', (tester) async {
    // A swipe down must not hand anybody an account.
    final store = await _pumpStart(tester);
    await _tapEmail(tester);

    Navigator.of(tester.element(find.byKey(SignupConsentSheet.sheetKey))).pop();
    await tester.pumpAndSettle();

    expect(store.consent, isNull);
    expect(find.byKey(GuardianStartKeys.email), findsOneWidget);
  });
}
