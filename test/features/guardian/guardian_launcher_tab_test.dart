import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/guardian_auth_repository.dart';
import 'package:app/data/remote/home_apps_repository.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/domain/app_category.dart';
import 'package:app/domain/guardian_account.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/features/guardian/presentation/guardian_launcher_tab.dart';
import 'package:app/features/guardian/presentation/widgets/guardian_surfaces.dart';

import '../../support/pump_app.dart';

const _apps = [
  LauncherApp(id: 'phone', label: '전화', category: AppCategory.phone),
  LauncherApp(id: 'message', label: '문자', category: AppCategory.message),
  LauncherApp(id: 'kakao', label: '카카오톡', category: AppCategory.kakao),
];

/// A guardian already signed in, with one parent linked and that parent's home
/// screen already on the server.
Future<({InMemoryHomeAppsRepository homeApps, String profileId})> _pumpTab(
  WidgetTester tester, {
  List<LauncherApp> apps = _apps,
}) async {
  final auth = InMemoryGuardianAuthRepository()
    ..seedSignedIn(const GuardianSession(userId: 'u1', email: 'g@example.com'));
  addTearDown(auth.dispose);

  final links = InMemorySeniorLinkRepository();
  await links.ensureGuardianAccount(displayName: '김보호');
  final profile = await links.createSeniorProfile(displayName: '어머니');

  final homeApps = InMemoryHomeAppsRepository();
  if (apps.isNotEmpty) await homeApps.replace(profile.id, apps);

  await pumpApp(
    tester,
    overrides: [
      guardianAuthRepositoryProvider.overrideWithValue(auth),
      seniorLinkRepositoryProvider.overrideWithValue(links),
      homeAppsRepositoryProvider.overrideWithValue(homeApps),
    ],
  );
  // A restored guardian session lands straight on the dashboard.
  await tester.pumpAndSettle();
  await tester.tap(find.text('홈 화면'));
  await tester.pumpAndSettle();

  return (homeApps: homeApps, profileId: profile.id);
}

void main() {
  testWidgets('the rows are the shared card, not bordered boxes of its own', (
    tester,
  ) async {
    // This tab is where the rebuilt home leads, so it has to be made of the
    // same parts. Its rows were flat #F7F7F8 boxes with a 1px border and a
    // tan drag handle — the handle in particular was #9C8770, the muted clay
    // that came out of the senior palette and had no business here either.
    await _pumpTab(tester);

    expect(find.byType(GuardianCard), findsNWidgets(_apps.length));
  });

  testWidgets('the tab shows the parent\'s buttons, not the guardian\'s', (
    tester,
  ) async {
    // Through Phase 3 this drew the guardian's own local settings, which made
    // the card's promise that a change reaches the parent's phone untrue.
    await _pumpTab(tester);

    expect(find.text('어머니 홈 화면'), findsOneWidget);
    expect(find.text('전화'), findsOneWidget);
    expect(find.text('카카오톡'), findsOneWidget);
  });

  testWidgets('renaming a button writes it to the parent\'s profile', (
    tester,
  ) async {
    final h = await _pumpTab(tester);

    await tester.tap(find.byKey(GuardianLauncherKeys.rename('phone')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '아들');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(
      h.homeApps.byProfile[h.profileId]!.firstWhere((a) => a.id == 'phone').label,
      '아들',
    );
    expect(find.text('아들'), findsOneWidget);
  });

  testWidgets('recolouring a button writes it too', (tester) async {
    final h = await _pumpTab(tester);

    await tester.tap(find.byKey(GuardianLauncherKeys.colour('message')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('원래 색으로'));
    await tester.pumpAndSettle();

    // Clearing is a real edit, so it has to reach the server like any other.
    expect(h.homeApps.replaceCount, greaterThan(1));
  });

  testWidgets('deleting asks first, then removes the button', (tester) async {
    final h = await _pumpTab(tester);

    await tester.tap(find.byKey(GuardianLauncherKeys.delete('kakao')));
    await tester.pumpAndSettle();
    expect(find.text('카카오톡 버튼을 지울까요?'), findsOneWidget);
    await tester.tap(find.text('지우기'));
    await tester.pumpAndSettle();

    expect(
      h.homeApps.byProfile[h.profileId]!.map((a) => a.id),
      ['phone', 'message'],
    );
  });

  testWidgets('backing out of the delete dialog changes nothing', (
    tester,
  ) async {
    final h = await _pumpTab(tester);
    final before = h.homeApps.replaceCount;

    await tester.tap(find.byKey(GuardianLauncherKeys.delete('kakao')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('그만두기'));
    await tester.pumpAndSettle();

    expect(h.homeApps.replaceCount, before);
    expect(find.text('카카오톡'), findsOneWidget);
  });

  testWidgets('adding a button reaches the parent\'s home screen', (
    tester,
  ) async {
    final h = await _pumpTab(tester);

    await tester.tap(find.byKey(GuardianLauncherKeys.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '딸');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(h.homeApps.byProfile[h.profileId]!.last.label, '딸');
  });

  testWidgets('a failed write rolls the screen back', (tester) async {
    // The dashboard tells the guardian the change reaches their parent's
    // phone. A rename still on screen after a failed write would be a lie
    // about someone else's phone.
    final h = await _pumpTab(tester);
    h.homeApps.offline = true;

    await tester.tap(find.byKey(GuardianLauncherKeys.rename('phone')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '아들');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(find.text('아들'), findsNothing);
    expect(find.text('전화'), findsOneWidget);
    expect(
      find.text('바꾸지 못했어요. 인터넷 연결을 확인하고 다시 시도해 주세요.'),
      findsOneWidget,
    );
  });

  testWidgets('a parent with no buttons yet is offered a first one', (
    tester,
  ) async {
    await _pumpTab(tester, apps: const []);

    expect(find.text('아직 버튼이 없어요'), findsOneWidget);
    expect(find.byKey(GuardianLauncherKeys.add), findsOneWidget);
  });

  testWidgets('the parent does not have to be connected to be tidied', (
    tester,
  ) async {
    // The guardian creates the profile before the parent's phone connects, and
    // `pull` on connect applies whatever is waiting. Making them wait would be
    // the wrong way round.
    await _pumpTab(tester, apps: const []);

    await tester.tap(find.byKey(GuardianLauncherKeys.add));
    await tester.pumpAndSettle();

    expect(find.text('버튼 추가하기'), findsWidgets);
  });
}
