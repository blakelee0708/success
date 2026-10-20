import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/senior_profile.dart';
import '../application/senior_link_controller.dart';

/// Whether a guardian is waiting for this senior to agree to a handover.
final pendingPrimaryGuardianProvider = FutureProvider<SeniorProfile?>((
  ref,
) async {
  final link = await ref.watch(seniorLinkControllerProvider.future);
  final profileId = link.seniorProfileId;
  if (profileId == null) return null;
  try {
    final profile = await ref
        .read(seniorLinkRepositoryProvider)
        .fetchProfile(profileId);
    return profile.pendingPrimaryGuardianId == null ? null : profile;
  } on Object {
    // The launcher keeps working with no signal; an unknown answer is simply
    // "nothing to ask about right now".
    return null;
  }
});

/// Asks the senior to agree to a change of primary guardian.
///
/// On the home screen rather than inside 가족 연결, because a senior may never
/// open that screen — and `07_PHASE_PLAN` makes their answer the thing that
/// decides it. Everyone else involved is a guardian, so nothing they agree
/// among themselves establishes who should be answering for this person.
class PrimaryGuardianPrompt extends ConsumerStatefulWidget {
  const PrimaryGuardianPrompt({super.key});

  static const promptKey = Key('primary-guardian-prompt');
  static const approveKey = Key('primary-guardian-approve');
  static const declineKey = Key('primary-guardian-decline');

  @override
  ConsumerState<PrimaryGuardianPrompt> createState() =>
      _PrimaryGuardianPromptState();
}

class _PrimaryGuardianPromptState extends ConsumerState<PrimaryGuardianPrompt> {
  bool _busy = false;

  Future<void> _answer(String profileId, bool approve) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(pairingRepositoryProvider)
          .resolvePrimaryGuardian(profileId, approve);
      ref.invalidate(pendingPrimaryGuardianProvider);
    } on Object {
      // Nothing useful to tell them: the question stays on screen and they can
      // answer again when the phone has signal.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(pendingPrimaryGuardianProvider).value;
    if (profile == null) return const SizedBox.shrink();

    return Padding(
      key: PrimaryGuardianPrompt.promptKey,
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
                '가족 한 분이 대표 보호자를\n맡겠다고 하십니다',
                style: TextStyle(
                  fontSize: 27,
                  height: 1.35,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.6,
                  color: AppColors.seniorInk,
                ),
              ),
              const SizedBox(height: 16),
              // Short enough to be whole lines. Written long and left to
              // wrap, this is where a senior is agreeing to something.
              const Text(
                '허락하시면 그분이\n'
                '이 폰을 대신 정리해 드립니다.',
                style: TextStyle(
                  fontSize: 20,
                  height: 1.55,
                  color: AppColors.seniorInk,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                '잘 모르시겠으면\n자녀분께 먼저 여쭤보세요.',
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
                      key: PrimaryGuardianPrompt.declineKey,
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
                      key: PrimaryGuardianPrompt.approveKey,
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
