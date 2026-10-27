import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/guardian/presentation/widgets/guardian_nav_bar.dart';
import 'package:app/core/supabase/supabase_config.dart';
import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/guardian_auth_repository.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/features/guardian/presentation/guardian_login_screen.dart';
import 'package:app/features/guardian/presentation/guardian_start_screen.dart';
import 'package:app/features/onboarding/presentation/splash_screen.dart';

import '../../support/pump_app.dart';

/// A build that believes it has a project, so the start screen takes the
/// Phase 4 path instead of the Phase 3 mock one.
const _configured = SupabaseConfig(
  url: 'https://example.supabase.co',
  anonKey: 'test-key',
);

/// Walks the real route: splash → 보호자 시작하기 → 이메일로 시작하기 → login.
///
/// The third button goes straight to the form. The walk used to go through
/// the Kakao sheet's 이메일로 계속하기 button instead, and that stopped being a
/// route the moment the provider buttons started asking the server: a
/// provider that answers raises no sheet, so the tap had nothing to hit.
Future<void> _gotoLogin(
  WidgetTester tester,
  InMemoryGuardianAuthRepository auth,
) async {
  addTearDown(auth.dispose);
  await pumpApp(
    tester,
    overrides: [
      supabaseConfigProvider.overrideWithValue(_configured),
      guardianAuthRepositoryProvider.overrideWithValue(auth),
      // Also overridden: with the config claiming a project exists, the real
      // provider would reach for a Supabase singleton that was never
      // initialised, and sign-in would fail on the account step.
      seniorLinkRepositoryProvider.overrideWithValue(
        InMemorySeniorLinkRepository(),
      ),
    ],
  );
  await tester.tap(find.byKey(SplashScreen.guardianCardKey));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(GuardianStartKeys.email));
  await tester.pumpAndSettle();
}

Future<void> _submit(
  WidgetTester tester, {
  required String email,
  required String password,
  bool createAccount = false,
}) async {
  if (createAccount) {
    await tester.tap(find.byKey(GuardianLoginKeys.toggleMode));
    await tester.pumpAndSettle();
  }
  await tester.enterText(find.byKey(GuardianLoginKeys.email), email);
  await tester.enterText(find.byKey(GuardianLoginKeys.password), password);
  await tester.tap(find.byKey(GuardianLoginKeys.submit));
  // Bounded pumps rather than `pumpAndSettle`: a successful sign-in lands on
  // the dashboard, whose 부모님 상태 card animates continuously, so settling
  // would spin until it times out.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

String _messageText(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(GuardianLoginKeys.message),
        matching: find.byType(Text),
      ),
    )
    .data!;

void main() {
  testWidgets('the guardian reaches a login form', (tester) async {
    await _gotoLogin(tester, InMemoryGuardianAuthRepository());

    expect(find.text('보호자 로그인'), findsOneWidget);
    expect(find.byKey(GuardianLoginKeys.email), findsOneWidget);
    expect(find.byKey(GuardianLoginKeys.password), findsOneWidget);
  });

  testWidgets('an address with no @ is refused without a round trip', (
    tester,
  ) async {
    final auth = InMemoryGuardianAuthRepository();
    await _gotoLogin(tester, auth);

    await _submit(tester, email: 'not-an-address', password: 'hunter2');

    expect(_messageText(tester), '이메일 주소를 확인해 주세요.');
    expect(auth.currentSession, isNull);
  });

  testWidgets('a short password is refused before it reaches the server', (
    tester,
  ) async {
    await _gotoLogin(tester, InMemoryGuardianAuthRepository());

    await _submit(tester, email: 'guardian@example.com', password: '123');

    expect(_messageText(tester), '비밀번호는 6자 이상이어야 해요.');
  });

  testWidgets('a wrong password says so and stays on the form', (tester) async {
    final auth = InMemoryGuardianAuthRepository(confirmationRequired: false);
    await _gotoLogin(tester, auth);
    await auth.signUp(email: 'guardian@example.com', password: 'hunter2');
    await auth.signOut();

    await _submit(tester, email: 'guardian@example.com', password: 'wrongpass');

    expect(_messageText(tester), '이메일이나 비밀번호가 맞지 않아요.');
    expect(find.text('보호자 로그인'), findsOneWidget);
  });

  testWidgets(
    'signing up says to check the mail rather than reporting failure',
    (tester) async {
      // The project requires email confirmation, so sign-up yields no session.
      // That is a state to explain, not an error to show.
      await _gotoLogin(tester, InMemoryGuardianAuthRepository());

      await _submit(
        tester,
        email: 'new@example.com',
        password: 'hunter2',
        createAccount: true,
      );

      expect(_messageText(tester), contains('new@example.com 으로 인증 메일을 보냈어요'));
    },
  );

  testWidgets('signing up twice on the same address is refused', (
    tester,
  ) async {
    final auth = InMemoryGuardianAuthRepository();
    await _gotoLogin(tester, auth);
    await auth.signUp(email: 'taken@example.com', password: 'hunter2');

    await _submit(
      tester,
      email: 'taken@example.com',
      password: 'hunter2',
      createAccount: true,
    );

    expect(_messageText(tester), '이미 가입된 이메일이에요. 로그인해 주세요.');
  });

  testWidgets('an unconfirmed account cannot sign in yet', (tester) async {
    final auth = InMemoryGuardianAuthRepository();
    await _gotoLogin(tester, auth);
    await auth.signUp(email: 'guardian@example.com', password: 'hunter2');

    await _submit(tester, email: 'guardian@example.com', password: 'hunter2');

    expect(_messageText(tester), '메일함에서 인증 메일을 먼저 확인해 주세요.');
  });

  testWidgets('a confirmed guardian signs in and lands on the dashboard', (
    tester,
  ) async {
    final auth = InMemoryGuardianAuthRepository();
    await _gotoLogin(tester, auth);
    await auth.signUp(email: 'guardian@example.com', password: 'hunter2');
    auth.confirm('guardian@example.com');

    await _submit(tester, email: 'guardian@example.com', password: 'hunter2');

    expect(auth.currentSession, isNotNull);
    expect(find.byKey(GuardianNavKeys.bar), findsOneWidget);
  });

  testWidgets('the email is trimmed and case-folded before it is used', (
    tester,
  ) async {
    final auth = InMemoryGuardianAuthRepository();
    await _gotoLogin(tester, auth);
    await auth.signUp(email: 'guardian@example.com', password: 'hunter2');
    auth.confirm('guardian@example.com');

    await _submit(
      tester,
      email: '  Guardian@Example.com ',
      password: 'hunter2',
    );

    expect(auth.currentSession?.email, 'guardian@example.com');
  });
}
