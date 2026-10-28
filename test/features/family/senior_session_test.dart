import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/core/supabase/senior_auth.dart';
import 'package:app/core/supabase/supabase_providers.dart';
import 'package:app/data/remote/home_apps_repository.dart';
import 'package:app/data/remote/pairing_repository.dart';
import 'package:app/data/remote/senior_link_repository.dart';
import 'package:app/data/senior_link_store.dart';
import 'package:app/domain/pair_link.dart';
import 'package:app/domain/senior_profile.dart';
import 'package:app/features/family/application/senior_pairing_controller.dart';
import 'package:app/features/launcher/application/senior_presence_reporter.dart';

/// The parent's phone has no account and signs in anonymously, and until
/// 2026-10-28 **nothing in the app ever did it**.
///
/// Every senior-side database function opens with `if auth.uid() is null then
/// raise exception 'not authenticated'`, so on a real phone 번호 보여주기 came
/// back as `번호를 받지 못했어요. 인터넷 연결을 확인해 주세요.` — a sentence
/// about the network for a failure that had nothing to do with it.
///
/// Nothing could have caught it from the outside. `flutter test` runs on the
/// in-memory twins, which need no session, and every `tool/verify_*` script
/// signs *itself* in before it starts because it is standing in for the phone.
/// The one caller nobody exercised was the app. So these tests watch for the
/// sign-in itself rather than for a working call.
class _CountingAuth implements SeniorAuth {
  int calls = 0;

  /// False stands in for a phone with no signal, or a project with anonymous
  /// sign-ins turned off.
  bool succeeds = true;

  @override
  Future<bool> ensure() async {
    calls++;
    return succeeds;
  }
}

/// Records how many sign-ins had happened by the time the server was asked.
class _OrderedPairing extends InMemoryPairingRepository {
  _OrderedPairing(super.store, this._auth);

  final _CountingAuth _auth;

  int signInsBeforeShowCode = -1;
  int signInsBeforeEnterCode = -1;

  @override
  Future<PairLink> startSeniorPairing({
    required String installId,
    String? deviceLabel,
    String? platform,
    String? osVersion,
  }) {
    signInsBeforeShowCode = _auth.calls;
    return super.startSeniorPairing(
      installId: installId,
      deviceLabel: deviceLabel,
      platform: platform,
      osVersion: osVersion,
    );
  }

  @override
  Future<SeniorProfile> redeemRecoveryCode({
    required String code,
    required String installId,
    String? deviceLabel,
    String? platform,
    String? osVersion,
  }) {
    if (signInsBeforeEnterCode < 0) signInsBeforeEnterCode = _auth.calls;
    return super.redeemRecoveryCode(
      code: code,
      installId: installId,
      deviceLabel: deviceLabel,
      platform: platform,
      osVersion: osVersion,
    );
  }
}

({ProviderContainer container, _CountingAuth auth, _OrderedPairing pairing})
_seniorPhone({String? profileId}) {
  final links = InMemorySeniorLinkRepository();
  final auth = _CountingAuth();
  final pairing = _OrderedPairing(links, auth);

  final container = ProviderContainer(
    // ignore: invalid_use_of_internal_member
    overrides: <Object>[
      seniorAuthProvider.overrideWithValue(auth),
      seniorLinkRepositoryProvider.overrideWithValue(links),
      pairingRepositoryProvider.overrideWithValue(pairing),
      homeAppsRepositoryProvider.overrideWithValue(InMemoryHomeAppsRepository()),
      seniorLinkStoreProvider.overrideWithValue(
        InMemorySeniorLinkStore(
          SeniorLink(installId: 'senior-phone', seniorProfileId: profileId),
        ),
      ),
    ].cast(),
  );
  addTearDown(container.dispose);
  return (container: container, auth: auth, pairing: pairing);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // The settings controller the pairing controller touches afterwards reads
    // shared_preferences, whose channel does not exist under `flutter test`.
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({});
  });

  test('번호 보여주기 signs the phone in before it asks the server', () async {
    final phone = _seniorPhone();

    await phone.container
        .read(seniorPairingControllerProvider.notifier)
        .showCode();

    expect(phone.auth.calls, greaterThan(0));
    expect(
      phone.pairing.signInsBeforeShowCode,
      greaterThan(0),
      reason: 'start_senior_pairing raises on a null auth.uid()',
    );
    expect(phone.container.read(seniorPairingControllerProvider).hasError, isFalse);
  });

  test('entering a number signs in first too', () async {
    // The other half of the same screen, and the same exception underneath
    // it: redeem_recovery_code and redeem_senior_invite both refuse a caller
    // with no session.
    final phone = _seniorPhone();
    final controller = phone.container.read(
      seniorPairingControllerProvider.notifier,
    );
    await controller.showCode();
    final issued = phone.pairing.issued.single;
    // Forget the sign-in 번호 보여주기 just did, or this test passes on the
    // strength of the other half of the screen.
    phone.auth.calls = 0;

    await expectLater(controller.enterCode(issued.code), throwsA(anything));

    expect(phone.pairing.signInsBeforeEnterCode, greaterThan(0));
  });

  test('the check-in signs in before it touches the device row', () async {
    // `touch_senior_device` is scoped to `auth_user_id = auth.uid()`, so with
    // no session it updates nothing and says so to nobody — the quietest of
    // the failures this missing sign-in caused.
    final phone = _seniorPhone(profileId: 'profile-1');

    final reported = await phone.container
        .read(seniorPresenceReporterProvider)
        .report();

    expect(reported, isTrue);
    expect(phone.auth.calls, 1);
  });

  test('a guardian\'s phone is never signed in anonymously', () async {
    // `HomeKeyListener` wraps the whole router, so the check-in runs on the
    // guardian's phone as well. An anonymous session there is one that looks
    // like a session to anything asking whether somebody is signed in, on the
    // half of the app where being signed in is the whole question.
    final phone = _seniorPhone();

    expect(
      await phone.container.read(seniorPresenceReporterProvider).report(),
      isFalse,
    );
    expect(phone.auth.calls, 0);
  });

  test('no session reports nothing rather than touching a row it cannot own',
      () async {
    final phone = _seniorPhone(profileId: 'profile-1');
    phone.auth.succeeds = false;

    expect(
      await phone.container.read(seniorPresenceReporterProvider).report(),
      isFalse,
    );
  });
}
