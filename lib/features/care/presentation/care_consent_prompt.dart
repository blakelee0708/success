import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/senior_profile.dart';
import '../../family/application/senior_link_controller.dart';
import '../data/care_capabilities.dart';

/// Whether the senior has been asked to agree to 안심 케어.
final careConsentPendingProvider = FutureProvider<SeniorProfile?>((ref) async {
  final link = await ref.watch(seniorLinkControllerProvider.future);
  final profileId = link.seniorProfileId;
  if (profileId == null) return null;
  try {
    final profile = await ref
        .read(seniorLinkRepositoryProvider)
        .fetchProfile(profileId);
    return profile.paidConsentStatus == PaidConsentStatus.pending
        ? profile
        : null;
  } on Object {
    // The launcher keeps working with no signal; unknown means nothing to ask.
    return null;
  }
});

/// Step 2 of the paid flow, on the senior's own phone.
///
/// `06_PERMISSION_AND_POLICY` orders it: 보호자 결제 → 피보호자 폰에 동의 화면 →
/// 피보호자가 허락 → 시스템 권한 요청 → 기능 활성화. This is the second step, and
/// nothing downstream of it runs until it is answered.
///
/// The wording matters as much as the mechanism, and so does the *list*. Every
/// line comes from `careCapabilities`, filtered to what is actually built and
/// paid, because what is described here is what the senior is agreeing to:
///
///  * Nothing unbuilt. A consent collected today for a feature that switches
///    on in six months is a consent nobody gave — 권한은 필요한 순간에
///    요청한다. 위치 is the one that matters, and it is absent.
///  * Nothing free. The battery and ringer reading rides on the check-in and
///    happens whether or not anyone subscribes; listing it would tell the
///    senior that 아니요 stops something it does not stop.
///
/// Which leaves the two alerts, described as *when the guardian is told*
/// rather than as *what is collected* — because the collection is the free
/// check-in either way.
///
/// And refusing is offered as plainly as agreeing — a consent screen with a
/// hard-to-find 아니요 is not asking.
class CareConsentPrompt extends ConsumerStatefulWidget {
  const CareConsentPrompt({super.key});

  static const promptKey = Key('care-consent-prompt');
  static const approveKey = Key('care-consent-approve');
  static const declineKey = Key('care-consent-decline');

  @override
  ConsumerState<CareConsentPrompt> createState() => _CareConsentPromptState();
}

class _CareConsentPromptState extends ConsumerState<CareConsentPrompt> {
  bool _busy = false;

  Future<void> _answer(String profileId, bool approve) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(subscriptionRepositoryProvider)
          .resolveCareConsent(profileId, approve);
      ref.invalidate(careConsentPendingProvider);
    } on Object {
      // The question stays on screen; they can answer again with signal.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(careConsentPendingProvider).value;
    if (profile == null) return const SizedBox.shrink();

    return Padding(
      key: CareConsentPrompt.promptKey,
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: AppColors.seniorSurface,
        borderRadius: BorderRadius.circular(20),
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '자녀분이 안심 케어를\n신청하셨어요',
                style: TextStyle(
                  fontSize: 27,
                  height: 1.35,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.6,
                  color: AppColors.seniorInk,
                ),
              ),
              const SizedBox(height: 16),
              // Read from `careCapabilities`, never typed here. This card and
              // the guardian's 돌봄 tab are two descriptions of one product
              // and they had already come apart: this one asked the senior to
              // agree to `5분마다 어디 계신지`, which is not built and will not
              // be until the 위치기반서비스사업 신고 is through, and to
              // `배터리와 소리, 인터넷 상태` — of which 인터넷 is never read and
              // the rest is free and sent regardless, so 아니요 would not have
              // stopped it.
              //
              // Every line is short enough to be the whole line; there is a
              // test counting glyphs. Written long and left to wrap, 지금
              // 쓰시는 기능은 broke after 기능 and left 은 alone on a line of
              // its own — on the one screen in the app where a senior is
              // being asked to agree to something.
              const Text(
                '허락하시면 이런 때에\n'
                '자녀분이 알림을 받아요.',
                style: TextStyle(
                  fontSize: 20,
                  height: 1.55,
                  color: AppColors.seniorInk,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                [for (final c in consentedCareCapabilities) '· ${c.seniorLine}']
                    .join('\n'),
                style: const TextStyle(
                  fontSize: 20,
                  height: 1.7,
                  fontWeight: FontWeight.w700,
                  color: AppColors.seniorInk,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                '싫으시면 아니요를 누르세요.\n'
                '지금 쓰시는 기능은 그대로 쓰시고,\n'
                '자녀분 결제는 취소됩니다.',
                style: TextStyle(
                  fontSize: 19,
                  height: 1.6,
                  color: AppColors.seniorInkMuted,
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: CareConsentPrompt.declineKey,
                      onPressed: _busy
                          ? null
                          : () => _answer(profile.id, false),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(72),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(26),
                        ),
                      ),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '아니요',
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      key: CareConsentPrompt.approveKey,
                      onPressed: _busy ? null : () => _answer(profile.id, true),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(72),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(26),
                        ),
                      ),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '허락합니다',
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
