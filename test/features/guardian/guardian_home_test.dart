import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/clock.dart';
import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/guardian_auth_repository.dart';
import 'package:app/data/remote/home_apps_repository.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/domain/app_category.dart';
import 'package:app/domain/guardian_account.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/domain/senior_device.dart';
import 'package:app/features/guardian/presentation/guardian_dashboard_screen.dart';
import 'package:app/features/guardian/presentation/widgets/guardian_nav_bar.dart';
import 'package:app/features/guardian/presentation/widgets/guardian_surfaces.dart';

import '../../support/pump_app.dart';

const _apps = [
  LauncherApp(id: 'phone', label: '전화', category: AppCategory.phone),
  LauncherApp(id: 'message', label: '문자', category: AppCategory.message),
  LauncherApp(id: 'kakao', label: '카카오톡', category: AppCategory.kakao),
];

final _now = DateTime(2026, 10, 20, 15, 10);

/// A signed-in guardian with one parent linked, and that parent's phone
/// either having checked in or not.
Future<void> _pumpHome(
  WidgetTester tester, {
  DateTime? lastSeenAt,
}) async {
  final auth = InMemoryGuardianAuthRepository()
    ..seedSignedIn(const GuardianSession(userId: 'u1', email: 'g@example.com'));
  addTearDown(auth.dispose);

  final links = InMemorySeniorLinkRepository();
  await links.ensureGuardianAccount(displayName: '영희');
  final profile = await links.createSeniorProfile(displayName: '어머니');
  if (lastSeenAt != null) {
    links.activeDeviceByProfile[profile.id] = SeniorDevice(
      id: 'device-1',
      installId: 'install-1',
      isActive: true,
      deviceLabel: '갤럭시 A54',
      lastSeenAt: lastSeenAt,
    );
  }

  final homeApps = InMemoryHomeAppsRepository();
  await homeApps.replace(profile.id, _apps);

  await pumpApp(
    tester,
    overrides: [
      nowProvider.overrideWithValue(() => _now),
      guardianAuthRepositoryProvider.overrideWithValue(auth),
      seniorLinkRepositoryProvider.overrideWithValue(links),
      homeAppsRepositoryProvider.overrideWithValue(homeApps),
    ],
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the hero says when the phone was last used', (tester) async {
    await _pumpHome(tester, lastSeenAt: DateTime(2026, 10, 20, 14, 30));

    expect(find.byKey(GuardianHomeKeys.hero), findsOneWidget);
    expect(find.text('오후 2:30'), findsOneWidget);
    expect(find.textContaining('쓰고 계셨어요'), findsOneWidget);
    expect(find.textContaining('갤럭시 A54'), findsOneWidget);
  });

  testWidgets('with no check-in it claims no time at all', (tester) async {
    // The hero is the most reassuring thing on the screen, which is exactly
    // why it must not reassure on no evidence. The server knows the phone
    // connected; it does not know the parent is well, and when it does not
    // even know that, the card has to say so.
    await _pumpHome(tester);

    expect(find.byKey(GuardianHomeKeys.hero), findsOneWidget);
    expect(find.textContaining('쓰고 계셨어요'), findsNothing);
    expect(find.textContaining('아직'), findsWidgets);
  });

  testWidgets('the hero counts the messages the family has left', (
    tester,
  ) async {
    // Nothing sent yet, so the whole free monthly allowance is there.
    await _pumpHome(tester, lastSeenAt: DateTime(2026, 10, 20, 14, 30));

    expect(find.text('50번'), findsOneWidget);
    expect(find.textContaining('메시지'), findsWidgets);
  });

  testWidgets('four things to do, each with what it is about', (tester) async {
    await _pumpHome(tester, lastSeenAt: DateTime(2026, 10, 20, 14, 30));

    expect(find.byType(GuardianActionCard), findsNWidgets(4));
    expect(find.textContaining('홈 버튼'), findsOneWidget);
    expect(find.textContaining('메시지'), findsWidgets);
    expect(find.textContaining('안심 케어'), findsOneWidget);
    expect(find.textContaining('초대하기'), findsOneWidget);
    // Read off the parent's real home screen, not a guess.
    expect(find.text('버튼 3개'), findsOneWidget);
  });

  testWidgets('the Material tab bar and the bordered cards are gone', (
    tester,
  ) async {
    await _pumpHome(tester, lastSeenAt: DateTime(2026, 10, 20, 14, 30));

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byKey(GuardianNavKeys.bar), findsOneWidget);
    // Still five destinations, still reachable.
    for (final label in ['홈', '홈 화면', '메시지', '돌봄', '가족']) {
      expect(find.text(label), findsWidgets, reason: '$label is missing');
    }
  });

  testWidgets('every tab starts its headline at the same height', (
    tester,
  ) async {
    // 홈 draws its heading through _TabScaffold and 홈 화면 passes the same one
    // as its list's header, so the crown lives in two places and has drifted
    // once already — 20 on one tab, 26 on the other, and both too close to
    // the top of the phone to look deliberate.
    await _pumpHome(tester, lastSeenAt: DateTime(2026, 10, 20, 14, 30));
    final home = tester.getRect(find.text('어머니')).top;
    expect(home, greaterThanOrEqualTo(GuardianHeading.crown));

    await tester.tap(find.byKey(GuardianNavKeys.destination('홈 화면')));
    await tester.pumpAndSettle();
    final launcher = tester.getRect(find.text('어머니 홈 화면')).top;

    expect((launcher - home).abs(), lessThan(1));
  });

  testWidgets('the tabs still open from the new bar', (tester) async {
    await _pumpHome(tester, lastSeenAt: DateTime(2026, 10, 20, 14, 30));

    await tester.tap(find.byKey(GuardianNavKeys.destination('홈 화면')));
    await tester.pumpAndSettle();
    expect(find.text('어머니 홈 화면'), findsOneWidget);

    await tester.tap(find.byKey(GuardianNavKeys.destination('가족')));
    await tester.pumpAndSettle();
    expect(find.byKey(GuardianHomeKeys.hero), findsNothing);
  });
}
