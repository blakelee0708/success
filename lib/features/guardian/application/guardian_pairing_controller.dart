import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../domain/guardian_notice.dart';
import '../../../domain/pair_link.dart';
import 'guardian_home_apps_controller.dart';
import 'guardian_session_controller.dart';

/// The application id the install link points at.
///
/// Settled 2026-10-26. It has to match `android/app/build.gradle.kts`, because
/// this is the id in the Play link a guardian texts their parent and a wrong
/// one sends them to a store page that does not exist. It lives here rather
/// than at each call site for that reason, and it can never be changed once a
/// listing exists.
const applicationId = 'com.jalboine.app';

/// What the app owes this guardian, which today is one line: their parent
/// cut the link.
///
/// It is read on the dashboard rather than pushed, because a removed
/// guardian has nothing else left on that screen - every other provider
/// behind it is refused by RLS from the moment the link goes, so without
/// this the app simply shows them an empty dashboard and says nothing.
final guardianNoticesProvider = FutureProvider<List<GuardianNotice>>((
  ref,
) async {
  final session = ref.watch(guardianSessionProvider);
  if (!session.hasValue || session.value == null) return const [];
  return ref.watch(pairingRepositoryProvider).guardianNotices();
});

/// The invite this phone most recently issued, if any.
///
/// **It is here rather than in the form's `State` because the form does not
/// survive what issuing one does.** Creating the first parent flips 홈 out
/// of its 아직 연결된 부모님이 없어요 branch into the connected layout - a
/// different tree - so the widget holding the code was torn down at the
/// exact moment the code appeared, and the guardian was left looking at an
/// empty form. The number they were about to read out to their parent was
/// gone and nothing said so.
///
/// It also outlives switching tabs and coming back, which is the other time
/// somebody would want to look at it again.
final lastInviteProvider = NotifierProvider<LastInvite, IssuedInvite?>(
  LastInvite.new,
);

class LastInvite extends Notifier<IssuedInvite?> {
  @override
  IssuedInvite? build() => null;

  void set(IssuedInvite? invite) => state = invite;
}

/// An install invite and who its two texts are addressed to.
///
/// The number travels with the link because the texts are sent from a
/// different screen than the one the number was typed on, and asking for
/// it twice is how the second text goes to nobody.
class IssuedInvite {
  const IssuedInvite(this.link, {this.phoneNumber});

  final PairLink link;
  final String? phoneNumber;
}

/// The install invite still waiting to be used, for 홈's 기다리고 있어요 page.
///
/// Read from the server rather than only from [lastInviteProvider], because
/// that one is gone the moment the app is closed - and the day after is when
/// a parent asks 번호가 뭐였지.
///
/// It follows *which* parent is waiting rather than the whole list, so the
/// list being re-read every five seconds does not re-read this twice each
/// time. The waiting card's own poll invalidates it, which is what notices
/// the parent's phone using the number.
final waitingInviteProvider = FutureProvider<PairLink?>((ref) async {
  final profileId = ref.watch(
    pendingSeniorLinksProvider.select(
      (links) => links.value?.firstOrNull?.seniorProfileId,
    ),
  );
  if (profileId == null) return null;
  return ref.watch(pairingRepositoryProvider).openSeniorInvite(profileId);
});

/// Everyone looking after the selected parent.
final guardiansForSelectedProvider = FutureProvider<List<GuardianLink>>((
  ref,
) async {
  final profile = ref.watch(selectedSeniorProfileProvider);
  if (profile == null) return const [];
  return ref.watch(pairingRepositoryProvider).guardiansFor(profile.id);
});

/// The guardian half of Phase 5: issuing codes and typing the one their parent
/// read out.
class GuardianPairingController extends Notifier<void> {
  @override
  void build() {}

  /// 경로 A. Creates the parent and the invite, and shows the number.
  ///
  /// **It no longer opens the messaging app by itself.** It used to, with one
  /// text carrying both the link and the number - and on the live server
  /// issuing the invite moves 홈 onto its waiting page, so the guardian came
  /// back from the messaging app to a screen with no number on it. The number
  /// is shown first now, and each of the two texts is its own button.
  Future<PairLink> inviteSenior({
    required String displayName,
    String? phoneNumber,
  }) async {
    final link = await ref
        .read(pairingRepositoryProvider)
        .createSeniorInvite(displayName: displayName);
    ref
        .read(lastInviteProvider.notifier)
        .set(IssuedInvite(link, phoneNumber: phoneNumber));
    _connected();
    return link;
  }

  /// Text one: the store link.
  ///
  /// Returns as soon as the messaging app is asked to open. It deliberately
  /// does not report whether anything was sent, because the app cannot know,
  /// and the same rule as SOS applies: never claim an action the user still
  /// has to take themselves.
  Future<void> sendInstallLink(PairLink link, {String? phoneNumber}) =>
      _openMessagingApp(
        phoneNumber: phoneNumber,
        body: link.installLinkMessage(applicationId),
      );

  /// Text two: where to type the number, and the number.
  Future<void> sendInviteCode(PairLink link, {String? phoneNumber}) =>
      _openMessagingApp(phoneNumber: phoneNumber, body: link.codeMessage());

  /// 경로 B. The number the parent read out, plus the two things it could not
  /// carry.
  Future<void> claimCode({
    required String code,
    required String displayName,
    String? phoneNumber,
  }) async {
    // A number typed in is not a number to show, so anything left on screen
    // from an earlier 설치 문자 goes.
    ref.read(lastInviteProvider.notifier).set(null);
    await ref
        .read(pairingRepositoryProvider)
        .claimSeniorPairingCode(
          code: code,
          displayName: displayName,
          phoneNumber: phoneNumber,
        );
    _connected();
  }

  Future<PairLink> createRecoveryCode(String seniorProfileId) =>
      ref.read(pairingRepositoryProvider).createRecoveryCode(seniorProfileId);

  Future<PairLink> createFamilyInvite(String seniorProfileId) =>
      ref.read(pairingRepositoryProvider).createFamilyInvite(seniorProfileId);

  Future<void> redeemFamilyInvite(String code) async {
    await ref.read(pairingRepositoryProvider).redeemFamilyInvite(code);
    _connected();
  }

  /// Both halves of 연결됨, because a new link is 'pending' now.
  ///
  /// `linkedSeniorProfilesProvider` is active-only, so on its own it comes
  /// back empty and the dashboard goes on saying 아직 연결된 부모님이 없어요
  /// to a guardian who has just connected one. The first thing they would do
  /// is do it again - and the second attempt meets the family-plan gate,
  /// which counts pending links, so they are told 가족 플랜이 필요해요 about
  /// their first parent.
  void _connected() {
    ref.invalidate(linkedSeniorProfilesProvider);
    ref.invalidate(pendingSeniorLinksProvider);
  }

  /// 부모님 연결 끊기, from 연결 관리.
  ///
  /// Their own link and nobody else's. The parent is not told: nothing
  /// changes on their phone beyond the 가족 button going back to saying
  /// 가족 연결, and a notice would be the app explaining somebody's child to
  /// them.
  ///
  /// The remaining month is refunded, which is what separates this from
  /// 해지하기 - that one keeps the days already paid for.
  Future<void> leaveSenior(String seniorProfileId) async {
    await ref.read(pairingRepositoryProvider).leaveSenior(seniorProfileId);
    ref.invalidate(guardiansForSelectedProvider);
    _connected();
  }

  /// 어머니 폰을 바꿨어요, answered here because the child is who knows.
  ///
  /// The parent pressed 번호 보여주기 on the new handset as always, which
  /// made a second, empty profile. This takes the four digits that profile is
  /// holding and moves the phone onto the original, so the conversation, the
  /// buttons and the text size are all where they were.
  Future<void> movePhone({
    required String code,
    required String seniorProfileId,
  }) async {
    await ref
        .read(pairingRepositoryProvider)
        .moveSeniorToNewPhone(code: code, seniorProfileId: seniorProfileId);
    ref.invalidate(selectedSeniorDeviceProvider);
    _connected();
  }

  Future<void> requestPrimary(String seniorProfileId) async {
    await ref
        .read(pairingRepositoryProvider)
        .requestPrimaryGuardian(seniorProfileId);
    ref.invalidate(guardiansForSelectedProvider);
  }

  /// Opens the messaging app with the body filled in. A missing number is
  /// fine — the guardian picks the recipient there.
  Future<void> _openMessagingApp({
    String? phoneNumber,
    required String body,
  }) async {
    final uri = Uri(
      scheme: 'sms',
      path: phoneNumber?.replaceAll(RegExp(r'[^0-9+]'), '') ?? '',
      queryParameters: {'body': body},
    );
    try {
      await launchUrl(uri);
    } on Object {
      // The invite still exists and the code still works; the guardian can
      // read it out instead. Failing the whole flow over the messaging app
      // would throw away a perfectly good invite.
    }
  }
}

final guardianPairingControllerProvider =
    NotifierProvider<GuardianPairingController, void>(
      GuardianPairingController.new,
    );
