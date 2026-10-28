import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/pair_link.dart';
import '../../family/application/senior_pairing_controller.dart';
import '../../launcher/data/phone_dialer.dart';
import '../application/senior_ring_controller.dart';

/// What the parent sees while their phone is ringing.
///
/// **A card over the home, not a screen of its own.** It is the same shape as
/// the message popup, and for the same reason: the home still showing around
/// it is how a senior knows their phone has not turned into something else
/// while they were not looking. The two consent cards cover the home outright
/// because they must be answered; this one does not have to be.
///
/// It says **who** and **why** before it says anything else. A phone that
/// starts screaming with no explanation is frightening, and an elderly person
/// cannot tell a message from a fault. That line is not a paid extra sold on
/// top of the noise - it is what keeps the noise from being cruel.
///
/// **Tapping anywhere outside the card still stops it**, which is what the
/// full-screen version did everywhere. A senior startled by a phone they did
/// not expect to make a noise should not have to find a button, and a card
/// with two buttons on it is exactly the screen where somebody presses the
/// background in a hurry. 소리 끄기 is there for whoever does look.
class SeniorRingLayer extends ConsumerWidget {
  const SeniorRingLayer({super.key});

  static const layerKey = Key('senior-ring-layer');
  static const callKey = Key('senior-ring-call');
  static const stopKey = Key('senior-ring-stop');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = ref.watch(seniorRingControllerProvider);
    if (request == null) return const SizedBox.shrink();

    final number = _numberOf(
      request.fromGuardianId,
      ref.watch(seniorGuardiansProvider).value ?? const [],
    );

    void stop() => ref.read(seniorRingControllerProvider.notifier).dismiss();

    return Positioned.fill(
      key: SeniorRingLayer.layerKey,
      child: GestureDetector(
        // `opaque` so the whole area answers, including the parts with no
        // child under them. Without it the gaps do nothing and the senior
        // taps a dead patch of screen while it keeps ringing.
        behavior: HitTestBehavior.opaque,
        onTap: stop,
        child: ColoredBox(
          // The same scrim the message popup uses. Dark enough that the card
          // is plainly in front, light enough that the home is still there.
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
                      // Swallows taps on the card so the buttons are not
                      // racing the scrim behind them.
                      child: GestureDetector(
                        onTap: () {},
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Icon(
                              Icons.volume_up_rounded,
                              size: 56,
                              color: AppColors.seniorPrimary,
                            ),
                            const SizedBox(height: 18),
                            Text(
                              // Whose it is comes first, the same as the
                              // message card. 찾으세요 rather than
                              // 찾고 계세요: the reader is the parent and the
                              // caller is their own child.
                              '${request.from}님이\n찾으세요',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 27,
                                height: 1.35,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.6,
                                color: AppColors.seniorInk,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: AppColors.seniorCard,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                request.line,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 22,
                                  height: 1.55,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.seniorInk,
                                ),
                              ),
                            ),
                            const SizedBox(height: 26),
                            // The resolution of the whole feature, where
                            // there is a number for it. A senior who picks up
                            // a loud phone and can only silence it has been
                            // told something and given nothing to do about
                            // it - and 전화를 안 받아 is why their child
                            // pressed the button.
                            //
                            // Dialling, never calling, exactly as 119 does.
                            if (number != null)
                              SizedBox(
                                height: 72,
                                child: FilledButton(
                                  key: SeniorRingLayer.callKey,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.seniorPrimary,
                                  ),
                                  onPressed: () {
                                    stop();
                                    ref
                                        .read(phoneDialerProvider)
                                        .openDialer(number);
                                  },
                                  child: Text(
                                    '${request.from}에게\n전화하기',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 23,
                                      height: 1.3,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                            if (number != null) const SizedBox(height: 12),
                            SizedBox(
                              height: 72,
                              child: number == null
                                  ? FilledButton(
                                      key: SeniorRingLayer.stopKey,
                                      style: FilledButton.styleFrom(
                                        backgroundColor:
                                            AppColors.seniorPrimary,
                                      ),
                                      onPressed: stop,
                                      child: const Text(
                                        '소리 끄기',
                                        style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    )
                                  // Quieter than 전화하기 when both are
                                  // there, because stopping the noise is not
                                  // what their child wanted.
                                  : TextButton(
                                      key: SeniorRingLayer.stopKey,
                                      onPressed: stop,
                                      child: const Text(
                                        '소리 끄기',
                                        style: TextStyle(
                                          fontSize: 21,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.seniorInkMuted,
                                        ),
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The sender's own number, or null.
  ///
  /// Never falls back to the primary guardian. Two children ring the same
  /// phone, and a call button that reaches the other one is worse than no
  /// button at all - the senior would believe they had answered their child.
  static String? _numberOf(String? guardianId, List<GuardianLink> guardians) {
    if (guardianId == null) return null;
    for (final g in guardians) {
      if (g.guardianAccountId == guardianId && g.isActive) {
        final number = g.phoneNumber?.trim();
        return number == null || number.isEmpty ? null : number;
      }
    }
    return null;
  }
}
