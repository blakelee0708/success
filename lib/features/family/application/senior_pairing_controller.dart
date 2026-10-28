import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../data/remote/senior_link_repository.dart';
import '../../../data/senior_link_store.dart';
import '../../../domain/pair_link.dart';
import '../../../domain/senior_profile.dart';
import '../../../domain/senior_settings.dart';
import '../../launcher/application/senior_settings_controller.dart';
import '../../launcher/application/senior_settings_sync.dart';
import 'senior_link_controller.dart';

/// The parent's phone half of 가족 연결.
///
/// Two things can happen on this screen, and which one applies is not the
/// senior's decision to make:
///
/// * 경로 B — nobody has connected them yet, so the phone shows a 4-digit code
///   for their child to type. The phone creates its own profile to do it.
/// * 복구 / 경로 A fallback — their child has a number for them to enter,
///   because this phone is replacing one that was already set up, or the
///   install link did not survive.
///
/// Both are offered at once. A senior holding a number should not have to
/// recognise that theirs is "the recovery case" to find the field.
class SeniorPairingController extends AsyncNotifier<PairLink?> {
  @override
  Future<PairLink?> build() async => null;

  /// Shows a code for the guardian to type. Safe to call again — the same
  /// phone gets the same profile, only a fresh code.
  Future<void> showCode() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _signIn();
      final link = await ref.read(seniorLinkStoreProvider).load();
      final pair = await ref
          .read(pairingRepositoryProvider)
          .startSeniorPairing(
            installId: link.installId,
            platform: defaultTargetPlatform.name,
          );
      // The phone belongs to a profile from this moment, before any guardian
      // has claimed the code — that is what makes the code claimable at all.
      await _remember(pair.seniorProfileId);
      return pair;
    });
  }

  /// Enters a number the guardian read out. Tries recovery first and then the
  /// invite: the senior was told "type this number", not which kind it is, and
  /// making them choose would be asking them to explain their own situation.
  Future<SeniorProfile> enterCode(String code) async {
    await _signIn();
    final link = await ref.read(seniorLinkStoreProvider).load();
    final pairing = ref.read(pairingRepositoryProvider);
    final platform = defaultTargetPlatform.name;

    SeniorProfile profile;
    try {
      profile = await pairing.redeemRecoveryCode(
        code: code,
        installId: link.installId,
        platform: platform,
      );
    } on SeniorLinkException {
      profile = await pairing.redeemSeniorInvite(
        installId: link.installId,
        code: code,
        platform: platform,
      );
    }

    await _remember(profile.id);
    return profile;
  }

  /// The parent's phone has no account, so it signs in anonymously — and
  /// nothing did that until now, which is why both paths on this screen
  /// failed on a real phone with `번호를 받지 못했어요`. Every function they
  /// call raises `not authenticated` on a null `auth.uid()`.
  ///
  /// A failure is not reported from here. The call that follows is the one
  /// that knows what the senior is trying to do, so it is the one whose error
  /// the screen should show; a second message about signing in would name a
  /// thing this app never asked them to do.
  Future<void> _signIn() => ref.read(seniorAuthProvider).ensure();

  /// Records the profile locally and adopts whatever is already waiting for
  /// this parent on the server — a guardian may have arranged their home
  /// screen before the phone ever connected.
  Future<void> _remember(String? profileId) async {
    if (profileId == null) return;
    final store = ref.read(seniorLinkStoreProvider);
    await store.save((await store.load()).copyWith(seniorProfileId: profileId));
    ref.invalidate(seniorLinkControllerProvider);

    final settings = ref.read(seniorSettingsControllerProvider.notifier);
    if (!await settings.pullFromServer()) {
      await ref
          .read(seniorSettingsSyncProvider)
          .push(ref.read(seniorSettingsControllerProvider).value ?? const SeniorSettings());
    }
  }
}

/// Whether anyone is actually looking after this phone.
///
/// Not the same question as "does this phone have a profile": showing a code
/// creates the profile, and a phone whose code nobody has typed yet is not
/// connected to anybody. Saying otherwise would tell a senior their family had
/// arrived when it had not.
final seniorGuardiansProvider = FutureProvider<List<GuardianLink>>((ref) async {
  final link = await ref.watch(seniorLinkControllerProvider.future);
  final profileId = link.seniorProfileId;
  if (profileId == null) return const [];
  try {
    return await ref.watch(pairingRepositoryProvider).guardiansFor(profileId);
  } on Object {
    // The launcher has to keep working with no signal. An unknown answer is
    // shown as "not yet", which is the state the screen can act on.
    return const [];
  }
});

final seniorPairingControllerProvider =
    AsyncNotifierProvider<SeniorPairingController, PairLink?>(
      SeniorPairingController.new,
    );
