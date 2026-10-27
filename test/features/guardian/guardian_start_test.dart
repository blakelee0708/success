import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/guardian/presentation/widgets/guardian_nav_bar.dart';
import 'package:app/features/guardian/presentation/guardian_login_screen.dart';
import 'package:app/features/guardian/presentation/guardian_start_screen.dart';
import 'package:app/features/onboarding/presentation/splash_screen.dart';

import '../../support/pump_app.dart';

Future<void> _gotoGuardianStart(WidgetTester tester) async {
  await pumpApp(tester);
  await tester.tap(find.byKey(SplashScreen.guardianCardKey));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('guardian start leads with what the guardian gets', (
    tester,
  ) async {
    await _gotoGuardianStart(tester);

    expect(find.text('보호자 시작하기'), findsOneWidget);
    expect(find.text('부모님께 이런 걸\n해드릴 수 있어요'), findsOneWidget);
    expect(find.text('연결은 몇 분이면 끝납니다.'), findsOneWidget);
  });

  testWidgets('guardian start lists the three benefits', (tester) async {
    await _gotoGuardianStart(tester);

    expect(find.text('부모님을 대신해 필요한 앱을 관리해 드릴 수 있어요'), findsOneWidget);
    expect(find.text('홈 화면 버튼의 이름과 색을 멀리서 정리합니다'), findsOneWidget);
    expect(find.text('부모님과 큰 글씨로 메시지와 사진을 주고받을 수 있어요'), findsOneWidget);
    expect(find.text('보내면 부모님 첫 화면에 바로 뜹니다'), findsOneWidget);
    expect(find.text('부모님 폰을 언제 쓰셨는지 알 수 있어요'), findsOneWidget);
    expect(find.text('마지막으로 쓰신 시각이 보입니다'), findsOneWidget);
  });

  testWidgets('guardian start offers Kakao, then Google, then email', (
    tester,
  ) async {
    await _gotoGuardianStart(tester);

    final kakao = find.text('카카오로 시작하기');
    final google = find.text('구글로 시작하기');
    final email = find.text('이메일로 시작하기');
    expect(kakao, findsOneWidget);
    expect(google, findsOneWidget);
    expect(email, findsOneWidget);

    // Kakao sits above Google: nearly every guardian in this age range has one.
    expect(tester.getTopLeft(kakao).dy, lessThan(tester.getTopLeft(google).dy));
    // Email is last because it is the most work — a password to invent and
    // remember — not because it matters least. Today it is the only one of
    // the three that can actually finish.
    expect(tester.getTopLeft(google).dy, lessThan(tester.getTopLeft(email).dy));
  });

  testWidgets('email goes straight to the form, with no sheet in between', (
    tester,
  ) async {
    // Kakao and Google have to explain themselves first because neither has
    // an OAuth client configured. Email has nothing to explain and nothing to
    // wait for, so a sheet saying so would be a screen that exists to be
    // passed through — the same fault 더 보기 and 첫 화면으로 정하기 were
    // both rewritten to remove.
    await _gotoGuardianStart(tester);

    await tester.tap(find.text('이메일로 시작하기'));
    await tester.pumpAndSettle();

    expect(find.byKey(GuardianLoginKeys.email), findsOneWidget);
    expect(find.byKey(GuardianLoginKeys.submit), findsOneWidget);
  });

  testWidgets('guardian start does not split sign-up from sign-in', (
    tester,
  ) async {
    await _gotoGuardianStart(tester);

    // `~로 시작하기` covers both, so a separate 회원가입 control would ask a
    // question the user cannot answer correctly: somebody who cannot recall
    // whether they signed up before has to guess, and guessing wrong is an
    // error message rather than a sign-in.
    //
    // **This is about 가입 vs 로그인, not about which provider.** `이메일로
    // 시작하기` is a third provider wearing the same verb as the other two,
    // so it does not split anything; it used to be asserted absent here, and
    // that read the rule as being about email.
    expect(find.text('회원가입'), findsNothing);
    expect(find.text('계정이 없으신가요?'), findsNothing);
    expect(find.text('이메일로 로그인'), findsNothing);
    expect(find.text('이메일로 가입하기'), findsNothing);
  });

  testWidgets('guardian start states the terms consent', (tester) async {
    await _gotoGuardianStart(tester);

    expect(find.text('시작하면 서비스 이용약관과\n개인정보 처리방침에 동의하게 됩니다'), findsOneWidget);
  });

  testWidgets('both providers open the dashboard on a build with no project', (
    tester,
  ) async {
    await _gotoGuardianStart(tester);

    await tester.tap(find.text('카카오로 시작하기'));
    await tester.pumpAndSettle();

    // With a Supabase project attached these buttons explain that the provider
    // is being prepared and offer the email route. With none attached the old
    // Phase 3 behaviour stands, which is what keeps the dashboard reachable
    // without a backend.
    expect(find.byKey(GuardianNavKeys.bar), findsOneWidget);
  });

  testWidgets('back returns to the splash', (tester) async {
    await _gotoGuardianStart(tester);

    await tester.tap(find.byKey(GuardianStartKeys.back));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('눌러보세요'), findsOneWidget);
  });

  testWidgets('the sign-in screen promises nothing the app cannot do yet', (
    tester,
  ) async {
    // This is the first screen a guardian reads and the only one that makes
    // promises. It was offering 배터리 · 소리 · 인터넷 "한눈에" while the
    // dashboard says 준비 중 for all three — they arrive with the Phase 6
    // background sync, which is an interface with no implementation — and
    // 사진 was on that list too and has come off it, because the app changed
    // rather than the copy: the private bucket exists with its policies
    // checked against the live project, and both ends can send one. The
    // three below are still true - the readings arrive with a background
    // sync that remains an interface with no implementation.
    //
    // Same rule that took the mocked 배터리 72% off the dashboard, applied one
    // screen earlier. A promise made before sign-up is worse than a hopeful
    // number after it.
    await _gotoGuardianStart(tester);

    for (final claim in ['배터리', '인터넷']) {
      expect(
        find.textContaining(claim),
        findsNothing,
        reason: '$claim is not something this app does yet',
      );
    }

    // And the one that came back is actually offered.
    expect(find.textContaining('사진'), findsOneWidget);
  });
}
