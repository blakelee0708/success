import 'package:flutter/material.dart';

import 'coach_lines.dart';

/// Said before the phone's own internet sheet slides up.
///
/// The sheet is not ours - not its wording, not its order, and not the text
/// size the senior chose, which is the whole promise of this app. Nothing can
/// be done about any of that: `setWifiEnabled` has been a no-op for ordinary
/// apps since Android 10 and mobile data needs carrier privileges, so the
/// panel is the only way an app can put Wi-Fi in reach at all.
///
/// So the only thing left is what the senior knows before it appears. That is
/// the same conclusion the home-app chooser reached, and this card is the same
/// shape for the same reason.
///
/// Two things it is careful about:
///
///  * **It does not promise the internet will work.** Pressing Wi-Fi switches
///    the radio on; whether there is a network in range is not ours to say.
///    The card describes the button, not the outcome.
///  * **It says how to get back.** The panel is a system sheet with no 돌아
///    가기 of ours on it, and a senior who cannot find the way out of a screen
///    they did not ask for concludes the phone is broken.
class InternetCoach extends StatelessWidget {
  const InternetCoach({super.key});

  @override
  Widget build(BuildContext context) {
    return const CoachLines(
      lines: [
        '이제 폰 화면이 하나 나와요.',
        '',
        '「Wi-Fi」를 누르면',
        '인터넷이 켜지고 꺼져요.',
        '',
        '다 하시면 뒤로 가기를',
        '눌러 주세요.',
      ],
      footnote: '화면 모양은 폰마다 조금 달라요.',
    );
  }
}
