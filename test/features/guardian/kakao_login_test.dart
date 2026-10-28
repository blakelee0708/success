import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/supabase/supabase_config.dart';
import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/guardian_auth_repository.dart';
import 'package:app/features/guardian/presentation/guardian_login_screen.dart';
import 'package:app/features/guardian/presentation/guardian_start_screen.dart';
import 'package:app/features/guardian/presentation/widgets/guardian_nav_bar.dart';
import 'package:app/features/onboarding/presentation/splash_screen.dart';

import '../../support/pump_app.dart';

/// 카카오로 시작하기, once there is a project to ask.
///
/// The button used to open a sheet saying the provider was being prepared.
/// That sentence was **hardcoded**, so it would have gone on claiming Kakao
/// was unavailable for as long as nobody remembered to delete it — including
/// the day after it started working. The button calls the real thing now and
/// the sheet says whatever the server said.
Future<InMemoryGuardianAuthRepository> _gotoStart(
  WidgetTester tester, {
  required bool hasProject,
  String? providerFails,
}) async {
  final auth = InMemoryGuardianAuthRepository(confirmationRequired: false)
    ..oauthFailure = providerFails;
  await pumpApp(
    tester,
    overrides: [
      guardianAuthRepositoryProvider.overrideWithValue(auth),
      supabaseConfigProvider.overrideWithValue(
        hasProject
            ? const SupabaseConfig(url: 'https://x.supabase.co', anonKey: 'k')
            : const SupabaseConfig(url: '', anonKey: ''),
      ),
    ],
  );
  await tester.tap(find.byKey(SplashScreen.guardianCardKey));
  await tester.pumpAndSettle();
  return auth;
}

void main() {
  testWidgets('with no project it still opens the dashboard', (tester) async {
    // Phases 1–3 were built with no backend and that has to keep working:
    // a build carrying no keys must still reach every screen.
    final auth = await _gotoStart(tester, hasProject: false);

    await tester.tap(find.text('카카오로 시작하기'));
    await tester.pumpAndSettle();
    await agreeToTerms(tester);

    expect(find.byKey(GuardianNavKeys.bar), findsOneWidget);
    expect(auth.oauthAttempts, isEmpty);
  });

  testWidgets('with a project it actually asks Kakao', (tester) async {
    final auth = await _gotoStart(tester, hasProject: true);

    await tester.tap(find.text('카카오로 시작하기'));
    await tester.pumpAndSettle();
    await agreeToTerms(tester);

    expect(auth.oauthAttempts, [GuardianOAuthProvider.kakao]);
  });

  testWidgets('구글 goes to Google, not to Kakao', (tester) async {
    // One handler serves both buttons; passing the wrong provider is the
    // kind of thing that looks right on the screen and signs you in to the
    // other account.
    final auth = await _gotoStart(tester, hasProject: true);

    await tester.tap(find.text('구글로 시작하기'));
    await tester.pumpAndSettle();
    await agreeToTerms(tester);

    expect(auth.oauthAttempts, [GuardianOAuthProvider.google]);
  });

  testWidgets('a provider the project has not set up says what the server said', (
    tester,
  ) async {
    // Not a sentence written here. Until the owner finishes the Kakao
    // console work the project answers that the provider is not enabled,
    // and the day they finish it this screen stops saying so by itself.
    await _gotoStart(
      tester,
      hasProject: true,
      providerFails: '아직 준비 중이에요. 이메일로 시작해 주세요.',
    );

    await tester.tap(find.text('카카오로 시작하기'));
    await tester.pumpAndSettle();
    await agreeToTerms(tester);

    // The screen names the provider; the rest is the server's own words.
    expect(
      find.text('카카오 로그인은 아직 준비 중이에요. 이메일로 시작해 주세요.'),
      findsOneWidget,
    );
    // And the one route that does work is offered rather than left to guess.
    expect(find.byKey(GuardianStartKeys.emailFallback), findsOneWidget);
  });

  testWidgets('that offer leads to the email form', (tester) async {
    await _gotoStart(
      tester,
      hasProject: true,
      providerFails: '아직 준비 중이에요. 이메일로 시작해 주세요.',
    );

    await tester.tap(find.text('카카오로 시작하기'));
    await tester.pumpAndSettle();
    await agreeToTerms(tester);
    await tester.tap(find.byKey(GuardianStartKeys.emailFallback));
    await tester.pumpAndSettle();

    expect(find.byKey(GuardianLoginKeys.email), findsOneWidget);
  });

  testWidgets('a working provider raises no sheet at all', (tester) async {
    final auth = await _gotoStart(tester, hasProject: true);

    await tester.tap(find.text('카카오로 시작하기'));
    await tester.pumpAndSettle();
    await agreeToTerms(tester);

    expect(auth.oauthAttempts, isNotEmpty);
    expect(find.byKey(GuardianStartKeys.emailFallback), findsNothing);
    // The browser is open at this point; nothing on this screen should claim
    // the sign-in finished, because it has not.
    expect(find.byKey(GuardianNavKeys.bar), findsNothing);
  });
}
