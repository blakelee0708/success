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
import 'package:app/features/launcher/presentation/widgets/category_picker.dart';

import '../../support/pump_app.dart';

const _apps = [
  LauncherApp(id: 'phone', label: '전화', category: AppCategory.phone),
  LauncherApp(id: 'message', label: '문자', category: AppCategory.message),
  LauncherApp(id: 'kakao', label: '카카오톡', category: AppCategory.kakao),
];

/// Enough buttons that the tab has something to scroll.
final _manyApps = [
  for (var i = 0; i < 16; i++)
    LauncherApp(id: 'app$i', label: '버튼 $i', category: AppCategory.message),
];

/// A guardian already signed in, with one parent linked and that parent's home
/// screen already on the server.
Future<
  ({
    InMemoryHomeAppsRepository homeApps,
    InMemorySeniorLinkRepository links,
    String profileId,
  })
>
_pumpTab(
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

  return (homeApps: homeApps, links: links, profileId: profile.id);
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

    // The app rows plus the four slot buttons - 가족, 소리, 인터넷,
    // 긴급 구조 요청 - which this tab started carrying on 2026-10-28 so the
    // guardian can take one off when their parent asks.
    expect(
      find.byType(GuardianCard),
      findsNWidgets(_apps.length + fixedSlotApps.length),
    );
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
    await tester.tap(find.byKey(CategoryPickerKeys.option(AppCategory.camera)));
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

  testWidgets('버튼 추가하기 sits under the last row and moves down with it', (
    tester,
  ) async {
    // It was pinned to the bottom of the screen, which left a field of
    // nothing between it and the last row and said nothing about where a new
    // button would land. In the list it is the next thing after the last
    // button, and adding one pushes it further down — which is the answer to
    // "where does it go".
    final h = await _pumpTab(tester);

    double addTop() => tester.getRect(
      find.byKey(GuardianLauncherKeys.add),
    ).top;
    final lastRow = tester.getRect(find.text(_apps.last.label));
    final before = addTop();

    expect(before, greaterThan(lastRow.bottom));

    await tester.tap(find.byKey(GuardianLauncherKeys.add));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(CategoryPickerKeys.option(AppCategory.camera)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '딸');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(h.homeApps.byProfile[h.profileId]!.last.label, '딸');
    expect(
      addTop(),
      greaterThan(before),
      reason: 'the new row did not push 버튼 추가하기 down',
    );
  });

  testWidgets('the heading scrolls with the list rather than sitting above it', (
    tester,
  ) async {
    // One scroll view holds the whole tab, so the heading is part of what
    // moves. Pinned above a separate list, it stays clamped to the very top
    // of the phone however far down the list you are.
    await _pumpTab(tester, apps: _manyApps);

    expect(find.text('어머니 홈 화면'), findsOneWidget);
    await tester.drag(
      find.byKey(GuardianLauncherKeys.list),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();

    // Scrolled off, because it is in the list. A header pinned above one
    // would still be sitting there at the top of the phone.
    expect(find.text('어머니 홈 화면'), findsNothing);
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

  testWidgets('a kind the screen already holds is not offered again', (
    tester,
  ) async {
    // Offering 카카오톡 to a screen that already has 카카오톡 is offering a
    // second button that opens the same app — a duplicate the senior cannot
    // tell from the first, on the one screen they cannot fix themselves.
    await _pumpTab(tester);

    await tester.tap(find.byKey(GuardianLauncherKeys.add));
    await tester.pumpAndSettle();

    for (final taken in [AppCategory.phone, AppCategory.message, AppCategory.kakao]) {
      expect(
        find.byKey(CategoryPickerKeys.option(taken)),
        findsNothing,
        reason: '$taken is already on the parent\'s home screen',
      );
    }
    expect(find.byKey(CategoryPickerKeys.option(AppCategory.camera)), findsOneWidget);
  });

  testWidgets('사람 and 폰에 있는 앱 are always offered', (tester) async {
    // A family has several people in it and a phone has eighty apps. Hiding
    // these after the first use would make the whole feature a one-shot.
    await _pumpTab(tester, apps: [
      ..._apps,
      const LauncherApp(
        id: 'daughter',
        label: '딸',
        category: AppCategory.contact,
        phoneNumber: '01012345678',
      ),
      const LauncherApp(
        id: 'game',
        label: '고스톱',
        category: AppCategory.installed,
        packageName: 'com.game.gostop',
      ),
    ]);

    await tester.tap(find.byKey(GuardianLauncherKeys.add));
    await tester.pumpAndSettle();

    expect(find.byKey(CategoryPickerKeys.option(AppCategory.contact)), findsOneWidget);
    expect(find.byKey(CategoryPickerKeys.option(AppCategory.installed)), findsOneWidget);
  });

  /// Presses 지우기 on one of the four slot rows, through the screen.
  Future<void> removeSlot(WidgetTester tester, AppCategory category) async {
    await tester.scrollUntilVisible(
      find.byKey(GuardianLauncherKeys.slot(category)),
      200,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(GuardianLauncherKeys.slot(category)),
        matching: find.byIcon(Icons.delete_outline),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('지우기'));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
  }

  testWidgets('the guardian can take 긴급 구조 요청 off their parent\'s home', (
    tester,
  ) async {
    // 엄마가 SOS 빼 달라고 했으니 빼 줘야지. Until 2026-10-28 these four were
    // the only buttons on a senior's phone that nobody could remove - not the
    // senior and not their family - on the half of the app whose whole job is
    // that the family can arrange that screen.
    final tab = await _pumpTab(tester);

    await removeSlot(tester, AppCategory.sos);

    // On the profile rather than in `home_apps`: what is recorded is the
    // absence of a button, and that table holds rows.
    expect(
      tab.links.profiles[tab.profileId]!.removedSlots,
      contains(AppCategory.sos),
    );
    expect(find.byKey(GuardianLauncherKeys.slot(AppCategory.sos)), findsNothing);
  });

  testWidgets('and it comes back from 버튼 추가하기', (tester) async {
    // A kind that can be taken off and never offered back is a one-way door.
    final tab = await _pumpTab(tester);
    await removeSlot(tester, AppCategory.sos);

    await tester.scrollUntilVisible(find.byKey(GuardianLauncherKeys.add), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(GuardianLauncherKeys.add));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(CategoryPickerKeys.option(AppCategory.sos)));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    expect(
      tab.links.profiles[tab.profileId]!.removedSlots,
      isNot(contains(AppCategory.sos)),
    );
    expect(
      find.byKey(GuardianLauncherKeys.slot(AppCategory.sos)),
      findsOneWidget,
    );
  });

  testWidgets('a parent\'s screen is never cut below four buttons', (
    tester,
  ) async {
    // The floor is on the controller, because the senior's 앱 설정 and this
    // screen are two ways to the same list. The refusal says the number and
    // offers the way round it rather than reporting a fault.
    final tab = await _pumpTab(
      tester,
      apps: const [
        LauncherApp(id: 'phone', label: '전화', category: AppCategory.phone),
      ],
    );

    // One app and four slot buttons is five. One may go; the next may not.
    await removeSlot(tester, AppCategory.sound);
    expect(
      tab.links.profiles[tab.profileId]!.removedSlots,
      contains(AppCategory.sound),
    );

    await removeSlot(tester, AppCategory.internet);

    expect(find.byKey(GuardianLauncherKeys.floorNotice), findsOneWidget);
    expect(
      tab.links.profiles[tab.profileId]!.removedSlots,
      isNot(contains(AppCategory.internet)),
    );
  });
}
