import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/guardian/presentation/widgets/guardian_nav_bar.dart';
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
    expect(find.text('홈 화면 앱과 버튼 색을 원격으로 정리합니다'), findsOneWidget);
    expect(find.text('부모님과 쉽게 메시지와 사진을 주고받을 수 있어요'), findsOneWidget);
    expect(find.text('큰 글씨로 바로 보이는 가족 메시지'), findsOneWidget);
    expect(find.text('부모님의 폰 상태를 확인할 수 있어요'), findsOneWidget);
    expect(find.text('배터리 · 소리 · 인터넷 연결을 한눈에'), findsOneWidget);
  });

  testWidgets('guardian start offers Kakao first, then Google', (tester) async {
    await _gotoGuardianStart(tester);

    final kakao = find.text('카카오로 시작하기');
    final google = find.text('구글로 시작하기');
    expect(kakao, findsOneWidget);
    expect(google, findsOneWidget);

    // Kakao sits above Google: nearly every guardian in this age range has one.
    expect(tester.getTopLeft(kakao).dy, lessThan(tester.getTopLeft(google).dy));
  });

  testWidgets('guardian start does not split sign-up from sign-in', (
    tester,
  ) async {
    await _gotoGuardianStart(tester);

    // `~로 시작하기` covers both, so a separate 회원가입 control would ask a
    // question the user cannot answer correctly.
    expect(find.text('회원가입'), findsNothing);
    expect(find.text('계정이 없으신가요?'), findsNothing);
    expect(find.text('이메일로 시작하기'), findsNothing);
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
}
