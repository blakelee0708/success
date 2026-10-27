import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/guardian_auth_repository.dart';
import 'package:app/features/guardian/presentation/guardian_login_screen.dart';
import 'package:app/features/onboarding/presentation/splash_screen.dart';

import '../../support/pump_app.dart';

/// 비밀번호를 잊으셨나요 — the way back in.
///
/// Until this existed a guardian who forgot their password was locked out
/// **permanently**: the login screen held an email field, a password field
/// and 가입하기, and nothing else. There is no other identifier on the
/// account and no support desk, so the emailed link is the only thing that
/// can tell the right person from anybody else.
///
/// It is also the one auth email that cannot be switched off. Confirming an
/// address at sign-up is optional — the project turns it off — but a reset
/// has to reach the person's inbox or it is not a reset.
Future<InMemoryGuardianAuthRepository> _gotoLogin(WidgetTester tester) async {
  final auth = InMemoryGuardianAuthRepository(confirmationRequired: false);
  await pumpApp(
    tester,
    overrides: [guardianAuthRepositoryProvider.overrideWithValue(auth)],
  );
  // No settle before the splash is left: its tap-prompt animation loops for
  // ever, so `pumpAndSettle` here times out rather than settling.
  await tester.tap(find.byKey(SplashScreen.guardianCardKey));
  await tester.pumpAndSettle();
  await tester.tap(find.text('이메일로 시작하기'));
  await tester.pumpAndSettle();
  return auth;
}

String _said(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .join(' ');

void main() {
  testWidgets('the way back in is on the sign-in form', (tester) async {
    await _gotoLogin(tester);

    expect(find.byKey(GuardianLoginKeys.forgot), findsOneWidget);
  });

  testWidgets('and not while an account is being created', (tester) async {
    // Nobody creating an account has a password to recover, and the row
    // would be one more thing to read on the screen where they are already
    // inventing one.
    await _gotoLogin(tester);
    await tester.tap(find.byKey(GuardianLoginKeys.toggleMode));
    await tester.pumpAndSettle();

    expect(find.byKey(GuardianLoginKeys.forgot), findsNothing);
  });

  testWidgets('an empty address is asked for rather than sent to', (
    tester,
  ) async {
    // The field is already on the screen, so there is no dialog and no
    // second screen — but somebody who came here *because* they are locked
    // out will press this first, with the box still empty.
    final auth = await _gotoLogin(tester);

    await tester.tap(find.byKey(GuardianLoginKeys.forgot));
    await tester.pumpAndSettle();

    expect(auth.resetRequests, isEmpty);
    expect(_said(tester), contains('이메일'));
  });

  testWidgets('a typed address gets the mail, and is told so', (tester) async {
    final auth = await _gotoLogin(tester);
    await tester.enterText(
      find.byKey(GuardianLoginKeys.email),
      'eldest@example.com',
    );
    await tester.tap(find.byKey(GuardianLoginKeys.forgot));
    await tester.pumpAndSettle();

    expect(auth.resetRequests, ['eldest@example.com']);
    expect(_said(tester), contains('메일'));
  });

  testWidgets('an address with no account is answered exactly the same way', (
    tester,
  ) async {
    // Saying `그런 계정은 없습니다` turns this form into a way of asking the
    // server which addresses are registered. Supabase does not answer that
    // question and neither does this screen.
    final auth = await _gotoLogin(tester);
    await tester.enterText(
      find.byKey(GuardianLoginKeys.email),
      'nobody@example.com',
    );
    await tester.tap(find.byKey(GuardianLoginKeys.forgot));
    await tester.pumpAndSettle();

    // Scoped to the notice, not the whole screen: the toggle below it reads
    // `계정이 없어요, 새로 만들래요`, which is about creating one and has no
    // bearing on whether this address has an account.
    final notice = tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(GuardianLoginKeys.message),
            matching: find.byType(Text),
          ),
        )
        .data!;
    expect(auth.resetRequests, ['nobody@example.com']);
    expect(notice, isNot(contains('없')));
    expect(notice, isNot(contains('가입되지')));
    expect(notice, contains('메일'));
  });
}
