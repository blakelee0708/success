import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/features/guardian/presentation/widgets/guardian_nav_bar.dart';
import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/guardian_auth_repository.dart';
import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/guardian_account.dart';
import 'package:app/features/launcher/presentation/easy_home_screen.dart';
import 'package:app/features/onboarding/presentation/splash_screen.dart';

import '../support/pump_app.dart';

/// An auth repository that starts out holding a session, the way Supabase does
/// after restoring one from disk.
InMemoryGuardianAuthRepository _signedIn() => InMemoryGuardianAuthRepository()
  ..seedSignedIn(
    const GuardianSession(userId: 'user-1', email: 'guardian@example.com'),
  );

/// A saved launcher, as a senior's phone would have.
Map<String, Object> _savedEasyMode() => {
  SharedPreferencesSeniorSettingsRepository.storageKey:
      '{"screenMode":"easy","fontSize":"normal","apps":['
      '{"id":"phone","label":"전화","category":"phone","color":null}]}',
};

void main() {
  testWidgets('a device with nothing saved still opens on the splash', (
    tester,
  ) async {
    final auth = InMemoryGuardianAuthRepository();
    addTearDown(auth.dispose);
    await pumpApp(
      tester,
      overrides: [guardianAuthRepositoryProvider.overrideWithValue(auth)],
    );

    expect(find.byType(SplashScreen), findsOneWidget);
  });

  testWidgets('a guardian whose session was restored skips the splash', (
    tester,
  ) async {
    final auth = _signedIn();
    addTearDown(auth.dispose);
    // Named, because a guardian with no name is asked for one before their
    // dashboard - which is a different screen from the splash and is the
    // subject of `guardian_name_test`, not this one.
    final links = InMemorySeniorLinkRepository();
    await links.ensureGuardianAccount(displayName: '영희');
    await pumpApp(
      tester,
      overrides: [
        guardianAuthRepositoryProvider.overrideWithValue(auth),
        seniorLinkRepositoryProvider.overrideWithValue(links),
      ],
    );
    await tester.pump(const Duration(milliseconds: 300));

    // Signing in last week should not put them back at the front door.
    expect(find.byKey(GuardianNavKeys.bar), findsOneWidget);
    expect(find.byType(SplashScreen), findsNothing);
  });

  testWidgets('a saved senior mode still wins on a shared device', (
    tester,
  ) async {
    // The senior's phone is the one that must never show a splash, and this
    // app becomes its launcher — pressing Home has to land on their buttons
    // even if a guardian once signed in here.
    final auth = _signedIn();
    addTearDown(auth.dispose);
    await pumpApp(
      tester,
      overrides: [guardianAuthRepositoryProvider.overrideWithValue(auth)],
      prefs: _savedEasyMode(),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(EasyHomeScreen), findsOneWidget);
  });
}
