import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/onboarding/presentation/screen_mode_choice_screen.dart';
import 'package:app/features/onboarding/presentation/widgets/screen_mode_preview.dart';

import '../../support/pump_app.dart';

/// 화면을 골라주세요 asks a senior to choose between two home screens.
///
/// It used to describe them in words — "큰 버튼 4개" — inside two tall white
/// boxes that were seven tenths empty, on a white ground that gave them no
/// edge. Reading is the hard part for the person being asked, so each card
/// now carries a small picture of the screen it chooses.
void main() {
  testWidgets('each choice shows the layout it picks', (tester) async {
    await enterSeniorFlow(tester);

    expect(find.byKey(ScreenModeChoiceKeys.easyPreview), findsOneWidget);
    expect(find.byKey(ScreenModeChoiceKeys.detailedPreview), findsOneWidget);
  });

  testWidgets('the preview shows as many tiles as the screen it stands for', (
    tester,
  ) async {
    // Four against six is the whole difference between the two modes, so a
    // preview that does not carry it is decoration.
    await enterSeniorFlow(tester);

    expect(
      tester
          .widget<ScreenModePreview>(
            find.byKey(ScreenModeChoiceKeys.easyPreview),
          )
          .tiles,
      4,
    );
    expect(
      tester
          .widget<ScreenModePreview>(
            find.byKey(ScreenModeChoiceKeys.detailedPreview),
          )
          .tiles,
      6,
    );
  });

  testWidgets('nothing overflows making room for them', (tester) async {
    await enterSeniorFlow(tester);

    expect(find.text('정말 쉬운 화면'), findsOneWidget);
    expect(find.text('자세한 화면'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
