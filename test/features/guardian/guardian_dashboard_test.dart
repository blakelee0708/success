import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/guardian/presentation/guardian_dashboard_screen.dart';
import 'package:app/features/guardian/presentation/guardian_family_tab.dart';
import 'package:app/features/guardian/presentation/guardian_launcher_tab.dart';
import 'package:app/features/onboarding/presentation/splash_screen.dart';

import '../../support/pump_app.dart';

/// Reaches the dashboard the way a guardian does on a build with no Supabase
/// project: splash → guardian start → a provider button, which is what keeps
/// Phase 3's "navigable without a backend" true.
///
/// With no project the repositories resolve to their in-memory twins, so no
/// parent is linked — that empty state is what these cases see. The cases that
/// need a linked parent live in guardian_launcher_tab_test.dart.
Future<void> _gotoDashboard(WidgetTester tester) async {
  await pumpApp(tester);
  await tester.tap(find.byKey(SplashScreen.guardianCardKey));
  await tester.pumpAndSettle();
  await tester.tap(find.text('카카오로 시작하기'));
  await tester.pumpAndSettle();
  await agreeToTerms(tester);
}

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('signing in lands on the dashboard, not a placeholder', (
    tester,
  ) async {
    await _gotoDashboard(tester);

    expect(find.byType(GuardianDashboardScreen), findsOneWidget);
  });

  testWidgets('a guardian with no parent yet is told how to get one', (
    tester,
  ) async {
    await _gotoDashboard(tester);

    expect(find.byKey(GuardianHomeKeys.noParent), findsOneWidget);
    expect(find.text('아직 연결된 부모님이 없어요'), findsOneWidget);
  });

  testWidgets('no phone reading is shown that the server does not have', (
    tester,
  ) async {
    await _gotoDashboard(tester);

    // Battery, ringer and network were mocked through Phase 3 and arrive with
    // the Phase 6 background sync. On a dashboard whose whole job is to
    // reassure, a plausible-looking 배터리 72% is worse than saying nothing.
    expect(find.textContaining('배터리 72'), findsNothing);
    expect(find.textContaining('벨소리 · 70'), findsNothing);
    expect(find.text('연결됨'), findsNothing);
  });

  testWidgets('all four tabs are reachable without a backend', (tester) async {
    await _gotoDashboard(tester);

    await _openTab(tester, '홈 화면');
    expect(find.byKey(GuardianLauncherKeys.empty), findsOneWidget);

    await _openTab(tester, '돌봄');
    expect(find.text('안심 케어'), findsWidgets);

    await _openTab(tester, '가족');
    expect(find.text('부모님 연결하기'), findsOneWidget);

    await _openTab(tester, '홈');
    expect(find.byKey(GuardianHomeKeys.noParent), findsOneWidget);
  });

  testWidgets('the care tab drops what the PRD puts outside the MVP', (
    tester,
  ) async {
    await _gotoDashboard(tester);
    await _openTab(tester, '돌봄');

    // 약 알림 / 복약 기록 are listed under Out Of MVP, and call-content
    // analysis is explicitly excluded, so neither may be advertised here.
    expect(find.textContaining('약 알림'), findsNothing);
    expect(find.textContaining('복용'), findsNothing);
    expect(find.textContaining('보이스피싱'), findsNothing);
  });

  testWidgets('the care tab sells no location at all', (tester) async {
    await _gotoDashboard(tester);
    await _openTab(tester, '돌봄');

    // The rule used to be 실시간 추적이라고 표현하지 않는다, and it still
    // holds — but location left the product entirely on 2026-10-26, so the
    // tighter check is that the word appears nowhere. See
    // `01_PRODUCT_PRD`'s `## 위치 기능을 뺀 이유`.
    expect(find.textContaining('실시간'), findsNothing);
    expect(find.textContaining('추적'), findsNothing);
    expect(find.textContaining('위치'), findsNothing);
  });

  testWidgets('both ways of connecting a parent are offered', (tester) async {
    await _gotoDashboard(tester);
    await _openTab(tester, '가족');

    // 07_PHASE_PLAN has two paths, and path A depends on the Play install
    // referrer surviving — so path B is not an advanced option to hide.
    expect(find.text('설치 문자 보내기'), findsOneWidget);
    expect(find.text('번호 입력하기'), findsOneWidget);
  });

  testWidgets('nothing that needs a parent is offered before there is one', (
    tester,
  ) async {
    await _gotoDashboard(tester);
    await _openTab(tester, '가족');

    // Recovery, the family invite and the guardian list all belong to a
    // specific parent. The cases that need one live in
    // guardian_family_tab_test.dart.
    expect(find.byKey(GuardianFamilyKeys.recovery), findsNothing);
    expect(find.byKey(GuardianFamilyKeys.familyInvite), findsNothing);
    expect(find.byKey(GuardianFamilyKeys.guardians), findsNothing);
  });

  testWidgets('the home tab does not offer editing a parent who is not there', (
    tester,
  ) async {
    // Through Phase 3 this tab drew the guardian's own local buttons and
    // claimed they reached the parent's phone. With nobody linked there is
    // nothing to edit, and saying so beats showing someone else's home screen.
    await _gotoDashboard(tester);
    await _openTab(tester, '홈 화면');

    expect(find.byKey(GuardianLauncherKeys.empty), findsOneWidget);
    expect(find.byKey(GuardianLauncherKeys.add), findsNothing);
  });
}
