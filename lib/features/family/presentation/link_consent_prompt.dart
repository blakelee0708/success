import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/pending_guardian_link.dart';
import '../application/senior_link_controller.dart';
import '../application/senior_pairing_controller.dart';

/// Whether somebody is waiting for this senior to agree to being connected.
final pendingGuardianLinkProvider = FutureProvider<PendingGuardianLink?>((
  ref,
) async {
  // Only a phone that is actually a senior's has anything to answer. The
  // guard is first so a guardian's phone does not reach the repository at
  // all - the trap this codebase has walked into twice.
  final link = await ref.watch(seniorLinkControllerProvider.future);
  if (link.seniorProfileId == null) return null;
  return ref.watch(pairingRepositoryProvider).pendingGuardianLink();
});

/// 가족 연결 동의 — answered on the senior's own phone, before anything is
/// shared.
///
/// **A guardian typed a number and was connected.** Nothing ever asked the
/// person whose phone it is. On 경로 B they had at least pressed 번호
/// 보여주기; on the install-SMS path they did nothing at all, and a sibling
/// joining by invitation was never mentioned to their mother.
///
/// Play's rule for an app that looks at another adult's phone is that the
/// adult knows and agrees on their own device. This is that card, and after
/// taking 위치 out it is the most valuable thing in the app for 심사.
///
/// Every line is short enough to be the whole line. Korean glyphs are about
/// as wide as the type size, so at 20px in a 318px card that is sixteen -
/// counted, not wrapped to. On the screen where a wrapped line once left 은
/// alone, and this is the other screen in the app where somebody is being
/// asked to agree to something.
class LinkConsentPrompt extends ConsumerStatefulWidget {
  const LinkConsentPrompt({super.key});

  static const promptKey = Key('link-consent-prompt');
  static const approveKey = Key('link-consent-approve');
  static const declineKey = Key('link-consent-decline');

  /// What the card can do for the senior, in their own words.
  ///
  /// Not 부모님의 홈 화면: the reader is the parent, and their own home screen
  /// described in the third person is somebody else talking about them.
  static const can = ['홈 화면 버튼 정리하기', '메시지 주고받기', '스마트폰 현황 확인하기'];

  @override
  ConsumerState<LinkConsentPrompt> createState() => _LinkConsentPromptState();
}

class _LinkConsentPromptState extends ConsumerState<LinkConsentPrompt> {
  bool _busy = false;

  Future<void> _answer(String linkId, bool approve) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(pairingRepositoryProvider)
          .answerGuardianLink(linkId, approve: approve);
      ref.invalidate(pendingGuardianLinkProvider);
      // 허락합니다 is the moment this phone has a family, so everything that
      // reads the roster has to ask again.
      ref.invalidate(seniorGuardiansProvider);
    } on Object {
      // The question stays on screen; they can answer again with signal.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(pendingGuardianLinkProvider).value;
    if (pending == null) return const SizedBox.shrink();

    // **The name comes first.** 가족 연결 요청이 있어요 tells a senior nothing
    // they can act on, and with two children a card that cannot name one asks
    // somebody to agree to they-do-not-know-who. It is asked of every
    // guardian once, before their dashboard, for this sentence.
    final who = pending.guardianName;
    final headline = who == null || who.isEmpty
        ? '가족이\n연결을 부탁하셨어요'
        : '$who님이\n연결을 부탁하셨어요';

    return Padding(
      key: LinkConsentPrompt.promptKey,
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
              Text(
                headline,
                style: const TextStyle(
                  fontSize: 27,
                  height: 1.35,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.6,
                  color: AppColors.seniorInk,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '허락하시면 자녀분이\n이런 걸 할 수 있어요.',
                style: TextStyle(
                  fontSize: 20,
                  height: 1.55,
                  color: AppColors.seniorInk,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                [
                  for (final line in LinkConsentPrompt.can) '· $line',
                ].join('\n'),
                style: const TextStyle(
                  fontSize: 20,
                  height: 1.75,
                  fontWeight: FontWeight.w700,
                  color: AppColors.seniorInk,
                ),
              ),
              const SizedBox(height: 16),
              // **No list of what is not collected.** A list of things that
              // are not happening plants worries in a reader who did not
              // arrive with them, and this reader is on their own phone
              // rather than reading a policy. `site/privacy.html` is the page
              // that owes the complete answer.
              const Text(
                '싫으시면 아니요를 누르세요.',
                style: TextStyle(
                  fontSize: 18,
                  height: 1.55,
                  color: AppColors.seniorInkMuted,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 72,
                      child: OutlinedButton(
                        key: LinkConsentPrompt.declineKey,
                        onPressed: _busy
                            ? null
                            : () => _answer(pending.linkId, false),
                        child: const Text(
                          '아니요',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 72,
                      child: FilledButton(
                        key: LinkConsentPrompt.approveKey,
                        onPressed: _busy
                            ? null
                            : () => _answer(pending.linkId, true),
                        child: const Text(
                          '허락합니다',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
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
