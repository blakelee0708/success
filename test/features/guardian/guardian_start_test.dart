import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:app/core/router/routes.dart';

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
  group('the three pages before sign-in', () {
    testWidgets('it opens on the first page, about the parent', (tester) async {
      await _gotoGuardianStart(tester);

      expect(find.text('스마트폰이 어려운 부모님,\n이제 걱정하지 마세요'), findsOneWidget);
      expect(find.text('큰 아이콘'), findsOneWidget);
      expect(find.text('눈이 어두운 부모님도 쉽게 확인할 수 있어요'), findsOneWidget);
      expect(find.text('글씨 크기 4단계'), findsOneWidget);
      expect(find.text('메시지 읽어 드리기'), findsOneWidget);
      // The buttons are on the last page, after the reasons to press them.
      expect(find.byKey(GuardianStartKeys.email), findsNothing);
    });

    testWidgets('다음 walks the pages in order', (tester) async {
      await _gotoGuardianStart(tester);

      await tester.tap(find.byKey(GuardianStartKeys.next));
      await tester.pumpAndSettle();
      expect(
        find.text('부모님의 런처 앱 화면을\n자녀(보호자)가 직접\n바꿔드릴 수 있어요'),
        findsOneWidget,
      );
      expect(find.text('앱 추가'), findsOneWidget);
      expect(find.text('앱 버튼 색과 이름'), findsOneWidget);

      await tester.tap(find.byKey(GuardianStartKeys.next));
      await tester.pumpAndSettle();
      expect(find.text('부모님의 안부가\n걱정되시나요?'), findsOneWidget);
      expect(find.text('마지막 폰 사용 시간'), findsOneWidget);
      expect(find.byKey(GuardianStartKeys.email), findsOneWidget);
      // Nothing to skip to from the page the buttons are on.
      expect(find.byKey(GuardianStartKeys.skip), findsNothing);
    });

    testWidgets('the pages can be swiped as well', (tester) async {
      await _gotoGuardianStart(tester);

      await tester.fling(
        find.byKey(GuardianStartKeys.pages),
        const Offset(-300, 0),
        1000,
      );
      await tester.pumpAndSettle();

      expect(find.text('앱 추가'), findsOneWidget);
    });

    testWidgets('건너뛰기 goes straight to the buttons', (tester) async {
      await _gotoGuardianStart(tester);

      await skipGuardianIntro(tester);

      expect(find.byKey(GuardianStartKeys.kakao), findsOneWidget);
      expect(find.byKey(GuardianStartKeys.email), findsOneWidget);
    });

    testWidgets('each page carries a picture of the app', (tester) async {
      await _gotoGuardianStart(tester);
      expect(find.byKey(GuardianStartKeys.picture), findsOneWidget);
    });

    testWidgets('it is shown every time, not only the first', (tester) async {
      // The owner's call: a returning guardian sees the three pages again
      // and can skip them, rather than the app remembering they were seen.
      await _gotoGuardianStart(tester);
      await skipGuardianIntro(tester);

      // Back walks the pages, and on the first one leaves.
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byKey(GuardianStartKeys.back));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(GuardianStartKeys.back));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('눌러보세요'), findsOneWidget);

      // Arriving again: nothing remembered that the pages were read.
      GoRouter.of(
        tester.element(find.byType(SplashScreen)),
      ).go(Routes.guardianStart);
      await tester.pumpAndSettle();

      expect(find.text('큰 아이콘'), findsOneWidget);
    });

    testWidgets('back from the email form lands on the buttons again', (
      tester,
    ) async {
      await _gotoGuardianStart(tester);
      await skipGuardianIntro(tester);
      await tester.tap(find.byKey(GuardianStartKeys.email));
      await tester.pumpAndSettle();
      await agreeToTerms(tester);

      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();

      expect(find.byKey(GuardianStartKeys.email), findsOneWidget);
    });
  });

  testWidgets('guardian start offers Kakao, then Google, then email', (
    tester,
  ) async {
    await _gotoGuardianStart(tester);
    await skipGuardianIntro(tester);

    final kakao = find.text('카카오로 시작하기');
    final google = find.text('구글로 시작하기');
    final email = find.text('이메일로 시작하기');
    expect(kakao, findsOneWidget);
    expect(google, findsOneWidget);
    expect(email, findsOneWidget);

    // Kakao sits above Google: nearly every guardian in this age range has one.
    expect(tester.getTopLeft(kakao).dy, lessThan(tester.getTopLeft(google).dy));
    // Email is last because it is the most work — a password to invent and
    // remember — not because it matters least.
    expect(tester.getTopLeft(google).dy, lessThan(tester.getTopLeft(email).dy));
  });

  testWidgets('email needs no 준비 중 sheet, only the terms one', (tester) async {
    // 약관 동의 is in front of all three because an account must not exist
    // before it is answered, and it is gone for good once answered.
    await _gotoGuardianStart(tester);
    await skipGuardianIntro(tester);

    await tester.tap(find.text('이메일로 시작하기'));
    await tester.pumpAndSettle();
    await agreeToTerms(tester);

    expect(find.byKey(GuardianLoginKeys.email), findsOneWidget);
    expect(find.byKey(GuardianLoginKeys.submit), findsOneWidget);
  });

  testWidgets('guardian start does not split sign-up from sign-in', (
    tester,
  ) async {
    await _gotoGuardianStart(tester);
    await skipGuardianIntro(tester);

    // `~로 시작하기` covers both on this page. The email form has its own
    // 로그인 / 새로 가입하기 tabs, because a password is the one thing a
    // person does have to know whether they already made.
    expect(find.text('회원가입'), findsNothing);
    expect(find.text('계정이 없으신가요?'), findsNothing);
    expect(find.text('이메일로 로그인'), findsNothing);
    expect(find.text('이메일로 가입하기'), findsNothing);
  });

  testWidgets('guardian start no longer claims consent already happened', (
    tester,
  ) async {
    await _gotoGuardianStart(tester);
    await skipGuardianIntro(tester);

    expect(find.textContaining('동의하게 됩니다'), findsNothing);
    expect(find.textContaining('동의하는 화면이 나옵니다'), findsOneWidget);
  });

  testWidgets('both providers open the dashboard on a build with no project', (
    tester,
  ) async {
    await _gotoGuardianStart(tester);
    await skipGuardianIntro(tester);

    await tester.tap(find.text('카카오로 시작하기'));
    await tester.pumpAndSettle();
    await agreeToTerms(tester);

    expect(find.byKey(GuardianNavKeys.bar), findsOneWidget);
  });

  testWidgets('back on the first page returns to the splash', (tester) async {
    await _gotoGuardianStart(tester);

    await tester.tap(find.byKey(GuardianStartKeys.back));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('눌러보세요'), findsOneWidget);
  });

  testWidgets('the pages promise nothing the app cannot do', (tester) async {
    // This is the first thing a guardian reads and the only place that makes
    // promises. The parent's internet state is not something the guardian's
    // phone can read, so it may not be offered here.
    await _gotoGuardianStart(tester);

    for (var page = 0; page < 3; page++) {
      expect(
        find.textContaining('인터넷'),
        findsNothing,
        reason: 'page ${page + 1}',
      );
      if (page < 2) {
        await tester.tap(find.byKey(GuardianStartKeys.next));
        await tester.pumpAndSettle();
      }
    }
  });
}
