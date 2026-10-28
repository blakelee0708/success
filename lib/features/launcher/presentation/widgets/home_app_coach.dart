import 'package:flutter/material.dart';

import 'coach_lines.dart';
import 'home_app_chooser_sketch.dart';

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
/// **The result comes after the condition, and `그러면` is what joins them.**
/// It used to lead with `홈 버튼을 누르면 그 화면이 나옵니다` on the card
/// before this one — stated as done, when pressing 네 changes nothing at all.
/// Android's screen is next and a person has to finish it. A senior who read
/// that as already-done closed the system screen and then found the phone
/// unchanged, which reads as the app being broken. Same fault as a button
/// claiming to save what was already saved, pointing the other way.
///
/// **It names Samsung's buttons.** The earlier version named none, on the
/// grounds that other phones word them differently — true, but it left
/// `오른쪽 아래를 눌러 주세요` for the overwhelming majority who are holding a
/// Galaxy, where `변경` is simply what it says. Vague everywhere is worse
/// than exact for almost everyone, when the reader is the one this app is
/// built for. The fallback line below covers the rest, and it is phrased
/// as *a button saying something like that will do* rather than as a
/// second instruction — it is an exception most readers never meet.
///
/// **It was two steps and it is one, and the copy was wrong for weeks.**
/// This card described a Samsung flow where choosing a row raises a second
/// dialog with `현재 버전 유지 / 변경`, and named `변경` as the button to
/// press. On a Galaxy running One UI today it is a **single dialog**: both
/// rows and `취소 / 기본 앱으로 설정` together, and there is no 변경 on it at
/// all. A senior following the old card would have looked for a button that
/// was not there.
///
/// That was found by **looking at a real phone**, which is the only way a
/// claim about somebody else's dialog ever gets checked. Nothing in this
/// repository could have caught it: the chooser is `RoleManager`'s, the
/// Kotlin that opens it has never run here, and a test can only confirm the
/// card says what it was written to say.
///
/// **The card draws the dialog now rather than describing it.**
/// `HomeAppChooserSketch` is a depiction with the two presses numbered where
/// they happen, so the senior looks for a shape instead of matching a
/// sentence against a dark screen in a typeface they have not seen. The
/// lines below are what the numbers mean, not a second set of
/// instructions.
enum HomeAppDirection {
  /// Making this app the home screen. Pick 잘보이네.
  take,

  /// Giving it back. Pick whatever they used before.
  give,
}

class HomeAppCoach extends StatelessWidget {
  const HomeAppCoach({super.key, required this.direction});

  final HomeAppDirection direction;

  /// Each line is a whole line, and `home_app_coach_test` is what says so.
  ///
  /// Counting glyphs is not enough here, and the first version proved it:
  /// `목록에서 「One UI 홈」을 누르고` is seventeen characters, the length
  /// the consent cards settled on, and it still ran 14px past its box —
  /// 「」 are full width and the latin letters are not, so the count and the
  /// width answer different questions. The test measures the laid-out
  /// paragraph against the real card, with the app's own faces loaded.
  ///
  /// What a wrapped line costs is documented on the consent cards: `지금
  /// 쓰시는 기능은` broke after 기능 and left 은 alone. This card shipped
  /// with three of them — `누르고` wrapping to `고`, and the fallback to
  /// `다.`
  List<String> get _lines => switch (direction) {
    HomeAppDirection.take => const [
      '이제 이런 창이 나와요.',
      '① 「잘보이네」를 누르시고',
      '② 「기본 앱으로 설정」을',
      '누르세요.',
      '',
      '그러면 홈 버튼을 누를 때',
      '이 화면이 나옵니다.',
    ],
    HomeAppDirection.give => const [
      '이제 이런 창이 나와요.',
      '① 「One UI 홈」을 누르시고',
      '② 「기본 앱으로 설정」을',
      '누르세요.',
      '',
      '그러면 홈 버튼을 누를 때',
      '전에 쓰시던 화면이 나옵니다.',
    ],
  };

  @override
  Widget build(BuildContext context) {
    // The body is shared with [InternetCoach]: both are said before a system
    // screen we do not own appears, and two copies of that layout would drift.
    return CoachLines(
      lines: _lines,
      // Between 이제 이런 창이 나와요 and the numbered pair, which is where
      // 이런 points. Above the numbers rather than below them, because the
      // picture is what the numbers are about.
      figure: HomeAppChooserSketch(
        pickThisApp: direction == HomeAppDirection.take,
      ),
      figureAfterLine: 0,
      // For the phones that word it differently. One line, and quiet, because
      // it is wrong-footing to lead with an exception that most readers will
      // never meet.
      // The dialog differs between phones, and the drawing is of a Galaxy
      // because that is what almost every reader is holding. One line, and
      // quiet, because leading with an exception most readers never meet is
      // wrong-footing.
      footnote: '폰에 따라 조금 다를 수 있어요.',
    );
  }
}
