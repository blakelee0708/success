import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/guardian_auth_repository.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/domain/guardian_account.dart';
import 'package:app/features/guardian/presentation/guardian_family_tab.dart';
import 'package:app/features/guardian/presentation/widgets/guardian_nav_bar.dart';

import '../../support/pump_app.dart';

/// 로그아웃. `04_SCREEN_SPEC` lists it under the guardian's 설정 탭; this app
/// folded that tab into 가족, and the row went missing in the fold —
/// `signOut()` has existed on the controller since Phase 4 with nothing on
/// any screen calling it.
Future<InMemoryGuardianAuthRepository> _openFamilyTab(
  WidgetTester tester,
) async {
  final auth = InMemoryGuardianAuthRepository()
    ..seedSignedIn(const GuardianSession(userId: 'u1', email: 'g@example.com'));
  addTearDown(auth.dispose);

  final links = InMemorySeniorLinkRepository();
  await links.ensureGuardianAccount(displayName: '영희');

  await pumpApp(
    tester,
    overrides: [
      guardianAuthRepositoryProvider.overrideWithValue(auth),
      seniorLinkRepositoryProvider.overrideWithValue(links),
    ],
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(GuardianNavKeys.destination('가족')));
  await tester.pumpAndSettle();
  return auth;
}

void main() {
  testWidgets('the guardian can find the way out', (tester) async {
    await _openFamilyTab(tester);

    await tester.ensureVisible(find.byKey(GuardianFamilyKeys.signOut));
    await tester.pumpAndSettle();
    expect(find.byKey(GuardianFamilyKeys.signOut), findsOneWidget);
  });

  testWidgets('it asks first', (tester) async {
    final auth = await _openFamilyTab(tester);

    await tester.ensureVisible(find.byKey(GuardianFamilyKeys.signOut));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(GuardianFamilyKeys.signOut));
    await tester.pumpAndSettle();

    expect(find.byKey(GuardianFamilyKeys.signOutConfirm), findsOneWidget);
    expect(auth.currentSession, isNotNull);
  });

  testWidgets('backing out keeps the session', (tester) async {
    final auth = await _openFamilyTab(tester);

    await tester.ensureVisible(find.byKey(GuardianFamilyKeys.signOut));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(GuardianFamilyKeys.signOut));
    await tester.pumpAndSettle();
    await tester.tap(find.text('그만두기'));
    await tester.pumpAndSettle();

    expect(auth.currentSession, isNotNull);
    expect(find.byKey(GuardianNavKeys.bar), findsOneWidget);
  });

  testWidgets('signing out ends the session and leaves the dashboard', (
    tester,
  ) async {
    final auth = await _openFamilyTab(tester);

    await tester.ensureVisible(find.byKey(GuardianFamilyKeys.signOut));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(GuardianFamilyKeys.signOut));
    await tester.pumpAndSettle();
    // Scoped to the dialog: the row behind it carries the same word, which
    // is the right word for both.
    await tester.tap(
      find.descendant(
        of: find.byKey(GuardianFamilyKeys.signOutConfirm),
        matching: find.text('로그아웃'),
      ),
    );
    // Pumped rather than settled: signing out lands on the launch gate, which
    // resolves to the splash, and the splash loops its tap prompt forever.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(auth.currentSession, isNull);
    // Staying on a dashboard built from a session that no longer exists is
    // how a signed-out guardian sees the last parent's name until they
    // restart the app.
    expect(find.byKey(GuardianNavKeys.bar), findsNothing);
  });

  testWidgets('it says what signing out does not do', (tester) async {
    // Nothing about the parent's phone changes. A guardian who reads 로그아웃
    // as 연결 끊기 will not press it, and the one who presses it expecting
    // that is worse off still.
    await _openFamilyTab(tester);

    await tester.ensureVisible(find.byKey(GuardianFamilyKeys.signOut));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(GuardianFamilyKeys.signOut));
    await tester.pumpAndSettle();

    expect(find.textContaining('부모님'), findsWidgets);
    expect(find.textContaining('그대로'), findsWidgets);
  });
}
