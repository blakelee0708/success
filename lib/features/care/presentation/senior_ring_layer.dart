import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../application/senior_ring_controller.dart';

/// What the parent sees while their phone is ringing.
///
/// **Anywhere on the screen stops it.** That is the whole interaction, and it
/// is deliberate: somebody woken by a phone they did not expect to make a
/// noise should not have to find a button. A pocket could end it early — but
/// the guardian can simply send it again, and the cost of a senior unable to
/// silence their own phone is in a different league from the cost of one
/// extra press on the guardian's side.
///
/// It says **who** and **why** before it says anything else. A phone that
/// starts screaming with no explanation is frightening, and an elderly person
/// cannot tell a message from a fault. That line is not a paid extra sold on
/// top of the noise — it is what keeps the noise from being cruel.
class SeniorRingLayer extends ConsumerWidget {
  const SeniorRingLayer({super.key});

  static const layerKey = Key('senior-ring-layer');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = ref.watch(seniorRingControllerProvider);
    if (request == null) return const SizedBox.shrink();

    return Positioned.fill(
      key: SeniorRingLayer.layerKey,
      child: GestureDetector(
        // `opaque` so the whole area answers, including the parts with no
        // child under them. Without it the gaps between the texts do nothing
        // and the senior taps a dead patch of screen while it keeps ringing.
        behavior: HitTestBehavior.opaque,
        onTap: () =>
            ref.read(seniorRingControllerProvider.notifier).dismiss(),
        child: ColoredBox(
          color: AppColors.seniorSurface,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.volume_up_rounded,
                    size: 72,
                    color: AppColors.seniorPrimary,
                  ),
                  const SizedBox(height: 28),
                  Text(
                    '${request.from}님이\n찾고 계세요',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 30,
                      height: 1.35,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.6,
                      color: AppColors.seniorInk,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    request.line,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 23,
                      height: 1.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.seniorInk,
                    ),
                  ),
                  const SizedBox(height: 40),
                  // Said rather than drawn as a button, because the button is
                  // the whole screen. A button here would teach the senior to
                  // aim for it and make every other tap feel like a failure.
                  const Text(
                    '화면을 한 번 누르면\n소리가 꺼집니다',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 21,
                      height: 1.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.seniorInkMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
