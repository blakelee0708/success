import '../../../notices/application/notice_providers.dart';
import '../../../notices/presentation/senior_service_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../care/presentation/care_consent_prompt.dart';
import '../../../family/presentation/link_consent_prompt.dart';
import '../../../messages/application/unread_notice.dart';
import '../../../messages/presentation/family_message_prompt.dart';

/// The two things only the senior can answer, drawn over their whole home
/// screen rather than squeezed above the tiles.
///
/// 안심 케어 동의 and the primary-guardian handover are both answered on the
/// parent's own phone — that is the point of them, and neither can move to
/// another screen. As cards above the grid they did what the 첫 화면 card
/// did: at 제일 크게 they asked for more height than the phone had, and
/// because every tile is a `FittedBox` nothing overflowed. The tiles came out
/// 24px tall, wide bars with no icon and no label.
///
/// Covering the home instead costs a senior the tiles until they answer, and
/// both cards are answered by pressing one of two buttons. A grid they cannot
/// read costs them the tiles anyway.
///
/// A third thing is drawn here now, and it is not a question: an unread
/// message from the family. It covers the home for a different reason -
/// a senior does not go looking, and a quiet mark beside a button is read
/// only by somebody who already knows to look for it. It is **last**, because
/// the two above it can only be answered by this person and money is held
/// against one of them, and because unlike them it can be put off.
///
/// **It is on 가족 연결 as well as the home**, and that was found on a phone.
/// 경로 B leaves the senior standing on the 가족 연결 screen looking at the
/// number they just read out, which is exactly where they are when their
/// child finishes typing it - and the layer was only ever in the home
/// screens' `Stack`. The card could not be drawn where the person was
/// standing. They pressed Back, arrived at the home, and only then were
/// asked. A consent screen nobody can reach is not a consent screen.
class SeniorNoticeLayer extends ConsumerWidget {
  const SeniorNoticeLayer({super.key, this.messages = true});

  /// Whether an unread message may use this layer.
  ///
  /// False on 가족 연결: that screen is one task long and the senior is in
  /// the middle of it. The questions still show, because they are the reason
  /// the layer is there at all and the senior is the only one who can answer
  /// them.
  final bool messages;

  static const layerKey = Key('senior-notice-layer');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // **First of the two questions.** Nothing a guardian asks for means
    // anything until this one is answered - 안심 케어 is bought by somebody
    // who is not connected yet.
    final linkWaiting = ref.watch(pendingGuardianLinkProvider).value != null;
    final careWaiting = ref.watch(careConsentPendingProvider).value != null;
    final unread = messages ? ref.watch(unreadFromFamilyProvider) : null;
    // **Last of everything.** A 공지 is the company talking, and the family
    // and the two questions come first: it waits behind an unread message
    // rather than covering it. Off on 가족 연결 for the same reason the
    // message is.
    final notice = messages && unread == null
        ? ref.watch(seniorNoticeProvider)
        : null;
    if (!linkWaiting && !careWaiting && unread == null && notice == null) {
      return const SizedBox.shrink();
    }

    // One at a time. Two consent screens stacked is not a question, it is an
    // interrogation; the care one goes first because money is already held
    // against it.
    //
    // The two consents cover the home outright. A message does not: it is a
    // card over the launcher with the home still showing around it, because
    // unlike them it is not a question and the senior may simply have reached
    // for their phone to make a call. Covering the whole screen for that
    // would take the phone away from them to tell them something.
    if (linkWaiting || careWaiting) {
      return Positioned.fill(
        key: SeniorNoticeLayer.layerKey,
        child: ColoredBox(
          color: AppColors.seniorBackground,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
              // **Shrunk to fit rather than scrolled.** At 제일 크게 both
              // cards ran past a 844px phone - the link card by 300px - and
              // the scroll view they sat in put 허락합니다 below the fold, on
              // the one screen where a senior is asked to agree to
              // something. Scrolling is what this app's readers fail at
              // most; a card drawn a little smaller is still read.
              child: LayoutBuilder(
                builder: (context, constraints) => Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: constraints.maxWidth,
                      child: linkWaiting
                          ? const LinkConsentPrompt()
                          : const CareConsentPrompt(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Positioned.fill(
      key: SeniorNoticeLayer.layerKey,
      child: ColoredBox(
        // Dark enough that the card is plainly in front, light enough that
        // the home is still recognisably there behind it. A senior who can
        // see their own tiles knows the phone has not changed into something
        // else while they were not looking.
        color: const Color(0x8C000000),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: SingleChildScrollView(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.seniorBackground,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                    child: unread != null
                        ? FamilyMessagePrompt(message: unread)
                        : SeniorServiceNotice(notice: notice!),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
