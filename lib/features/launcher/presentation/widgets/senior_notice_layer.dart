import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../care/presentation/care_consent_prompt.dart';
import '../../../family/presentation/primary_guardian_prompt.dart';
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
class SeniorNoticeLayer extends ConsumerWidget {
  const SeniorNoticeLayer({super.key});

  static const layerKey = Key('senior-notice-layer');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final careWaiting = ref.watch(careConsentPendingProvider).value != null;
    final handoverWaiting =
        ref.watch(pendingPrimaryGuardianProvider).value != null;
    final unread = ref.watch(unreadFromFamilyProvider);
    if (!careWaiting && !handoverWaiting && unread == null) {
      return const SizedBox.shrink();
    }

    // One at a time. Two consent screens stacked is not a question, it is an
    // interrogation; the care one goes first because money is already held
    // against it.
    return Positioned.fill(
      key: SeniorNoticeLayer.layerKey,
      child: ColoredBox(
        color: AppColors.seniorBackground,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
            child: Center(
              child: SingleChildScrollView(
                child: careWaiting
                    ? const CareConsentPrompt()
                    : handoverWaiting
                    ? const PrimaryGuardianPrompt()
                    : FamilyMessagePrompt(message: unread!),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
