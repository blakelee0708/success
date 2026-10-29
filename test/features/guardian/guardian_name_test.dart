import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/guardian_auth_repository.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/domain/guardian_account.dart';
import 'package:app/features/guardian/presentation/guardian_name_screen.dart';
import 'package:app/features/guardian/presentation/widgets/guardian_nav_bar.dart';

import '../../support/pump_app.dart';

/// 부모님이 뭐라고 부르세요 — asked once, before the dashboard.
///
/// Nothing ever wrote `guardian_accounts.display_name`: every caller of
/// `ensureGuardianAccount` passed no name, so it was null for every guardian
/// in the system and four screens fell back to the literal word 보호자 - the
/// family list, the parent's 긴급 연락 tile, the ring card, and the name over
/// a bubble when a parent has two children.
Future<InMemorySeniorLinkRepository> _pump(
  WidgetTester tester, {
  String? savedName,
  String? providerName,
}) async {
  final auth = InMemoryGuardianAuthRepository()
    ..seedSignedIn(GuardianSession(userId: 'u1', providerName: providerName));
  addTearDown(auth.dispose);
  final links = InMemorySeniorLinkRepository();
  if (savedName != null) {
    await links.ensureGuardianAccount(displayName: savedName);
  }
  await pumpApp(
    tester,
    overrides: [
      guardianAuthRepositoryProvider.overrideWithValue(auth),
      seniorLinkRepositoryProvider.overrideWithValue(links),
    ],
  );
  await tester.pumpAndSettle();
  return links;
}

void main() {
  testWidgets('a guardian with no name is asked before anything else', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.byKey(GuardianNameScreen.field), findsOneWidget);
    expect(find.byKey(GuardianNavKeys.bar), findsNothing);
  });

  testWidgets('and cannot get past it', (tester) async {
    // **Required, with no skip.** What this feeds is the sentence a senior
    // answers on their own phone - 영희님이 연결을 부탁하셨어요 - and with two
    // children a card that cannot name one asks somebody to agree to
    // they-do-not-know-who.
    await _pump(tester);

    await tester.tap(find.byKey(GuardianNameScreen.save));
    await tester.pumpAndSettle();

    expect(find.byKey(GuardianNameScreen.error), findsOneWidget);
    expect(find.byKey(GuardianNavKeys.bar), findsNothing);
  });

  testWidgets('answering it opens the dashboard and saves the name', (
    tester,
  ) async {
    final links = await _pump(tester);

    await tester.enterText(find.byKey(GuardianNameScreen.field), '영희');
    await tester.tap(find.byKey(GuardianNameScreen.save));
    await tester.pumpAndSettle();

    expect(find.byKey(GuardianNavKeys.bar), findsOneWidget);
    expect((await links.ensureGuardianAccount()).displayName, '영희');
  });

  testWidgets('a provider nickname is offered, not imposed', (tester) async {
    // Kakao and Google hand over a nickname and email sign-up hands over
    // nothing. It is a suggestion either way: what goes on the parent's
    // screen is what the parent calls them, and a Kakao nickname is as likely
    // to be 호야 as 영희.
    await _pump(tester, providerName: '호야');

    expect(find.text('호야'), findsOneWidget);
  });

  testWidgets('a guardian who has answered is never asked again', (
    tester,
  ) async {
    await _pump(tester, savedName: '영희');

    expect(find.byKey(GuardianNameScreen.field), findsNothing);
    expect(find.byKey(GuardianNavKeys.bar), findsOneWidget);
  });
}
