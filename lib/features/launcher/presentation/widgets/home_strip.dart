import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/clock.dart';
import '../../../../core/format/korean_clock.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/clay_pad.dart';

/// The band across the top of 정말 쉬운 화면: the time, and the family.
///
/// It exists because the home screen had 211px of nothing at the bottom and
/// square tiles could not fill it. Rather than stretch the tiles into tall
/// rectangles, the slack became one wide thing worth looking at.
///
/// Two jobs, in the order a senior needs them. The clock answers the question
/// they picked the phone up to ask. Underneath it is whoever is looking after
/// them: their child's newest message when there is one, and the way to
/// connect a family when there is not — the same slot `04_SCREEN_SPEC` gives
/// to 가족 연결 또는 자녀 이름.
class HomeStrip extends ConsumerWidget {
  const HomeStrip({super.key});

  static const stripKey = Key('home-strip');


  /// Shown once somebody is.


  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(nowProvider)();

    return ClayPad(
      light: AppColors.seniorCardLight,
      face: AppColors.seniorCard,
      deep: AppColors.seniorCardDeep,
      wall: AppColors.seniorCardWall,
      radius: 30,
      sheen: 0.3,
      child: Padding(
        key: stripKey,
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 16),
        // Scales down rather than overflowing, the same rule the tiles and
        // SOS follow. The band is the part that gives up height when the
        // 첫 화면 card appears or the text size goes to 아주 크게, so it is
        // the part that has to survive being squeezed.
        child: LayoutBuilder(
          builder: (context, box) => FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: box.maxWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The date sits above the clock rather than beside it: side by
                  // side, the two ran to 328px inside a 310px card and the date
                  // was pushed out of its own box.
                  Text(
                    koreanDate(now),
                    style: const TextStyle(
                      fontSize: 20,
                      height: 1.3,
                      fontWeight: FontWeight.w500,
                      color: AppColors.seniorInkMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    koreanTime(now),
                    // One line, always. `오후 7:14` broke after 오후 and came
                    // out two lines tall, and because the band is wrapped in
                    // a `FittedBox` the whole thing was then scaled to 0.79
                    // to fit — so the clock rendered at 43px while the code
                    // said 54 and nothing overflowed to say so. Raising the
                    // sizes could not help: every increase was absorbed by
                    // the same scaling. The third time this wrapper has
                    // hidden a fault in this file.
                    maxLines: 1,
                    softWrap: false,
                    style: const TextStyle(
                      fontSize: 60,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.5,
                      color: AppColors.seniorInk,
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
