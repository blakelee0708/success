import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// What to say before the phone's own home-app chooser opens.
///
/// That chooser is drawn by Android, from `RoleManager`, and **the app cannot
/// touch any of it** — not the wording, not the order, and not which row
/// starts selected. It deliberately starts on whatever is the home app now,
/// because an app that could pre-select itself is how a launcher gets
/// hijacked. So the only thing we control is what the senior knows before it
/// appears, and until now they knew nothing: a system dialog in system
/// language arrived with no warning and the radio already on the other app.
///
/// **It names no button on that screen.** The labels differ by phone and by
/// Android version — Samsung says 기본 앱으로 설정, others say something else
/// — so quoting one would be wrong on the phones that say the other, and
/// being wrong here is worse than being vague. Two things are true
/// everywhere: the app being asked about is named in the list, and the
/// confirm sits at the bottom right.
enum HomeAppDirection {
  /// Making this app the home screen. Pick 잘보이네.
  take,

  /// Giving it back. Pick whatever they used before.
  give,
}

class HomeAppCoach extends StatelessWidget {
  const HomeAppCoach({super.key, required this.direction});

  final HomeAppDirection direction;

  /// Each line is a whole line. At 19px in a card this wide that is about
  /// seventeen Korean glyphs, and these are counted rather than wrapped —
  /// the senior's consent cards document what a wrapped line costs.
  List<String> get _lines => switch (direction) {
    HomeAppDirection.take => const [
      '다음 화면에서',
      '「잘보이네」를 누르고',
      '오른쪽 아래를',
      '한 번 더 눌러 주세요',
    ],
    HomeAppDirection.give => const [
      '다음 화면에서',
      '원래 쓰시던 앱을 누르고',
      '오른쪽 아래를',
      '한 번 더 눌러 주세요',
    ],
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final line in _lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              line,
              style: const TextStyle(
                fontSize: 19,
                height: 1.5,
                fontWeight: FontWeight.w700,
                color: AppColors.seniorInk,
              ),
            ),
          ),
      ],
    );
  }
}
