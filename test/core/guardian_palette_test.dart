import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/theme/app_colors.dart';

/// The guardian palette settled on 2026-10-20: a blue gradient ground, cards
/// that are gradients rather than bordered boxes, and one deep blue hero.
///
/// `04_SCREEN_SPEC` gives this persona 파란 포인트, which is why none of the
/// senior rules apply here — no clay, no 26px lettering, and blue is the
/// point rather than the thing to avoid.
void main() {
  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    return la > lb ? (la + 0.05) / (lb + 0.05) : (lb + 0.05) / (la + 0.05);
  }

  group('the hero gradient carries white lettering end to end', () {
    // A gradient is not one colour, and checking only the dark end is how a
    // pastel card ships with a 1.6:1 label on it. The reference image this
    // was drawn from fails exactly there: #B5CBF6 under white measures 1.64.
    //
    // 4.5 rather than 3.0 because the hero carries 13px lines as well as the
    // big ones. Dropping below it means taking the small text off the card.
    for (final (name, stop) in [
      ('start', AppColors.guardianHeroStart),
      ('mid', AppColors.guardianHeroMid),
      ('end', AppColors.guardianHeroEnd),
    ]) {
      test('$name clears 4.5:1', () {
        expect(contrast(Colors.white, stop), greaterThanOrEqualTo(4.5));
      });
    }

    test('it actually runs light-to-dark, so the shading reads', () {
      expect(
        AppColors.guardianHeroStart.computeLuminance(),
        lessThan(AppColors.guardianHeroMid.computeLuminance()),
      );
      expect(
        AppColors.guardianHeroMid.computeLuminance(),
        lessThan(AppColors.guardianHeroEnd.computeLuminance()),
      );
    });
  });

  group('text on a card holds at the card\'s darker end', () {
    // The cards are gradients too, so the floor is the bottom of the card and
    // not the white at its crown.
    final card = AppColors.guardianCardEnd;

    test('the ink is far clear of it', () {
      expect(contrast(AppColors.guardianInk, card), greaterThanOrEqualTo(7.0));
    });

    test('the low-battery amber is lettering, not decoration', () {
      // It carries the value itself — 12% — at 15px, so it has to clear the
      // small-text floor against the bottom of the card and not merely look
      // like a warning colour.
      expect(
        contrast(AppColors.guardianTintAmberInk, card),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('the caption clears 4.5:1, being 12.5px', () {
      // #8B95A1 is the colour this family usually puts here and it measures
      // 3.04 against white — under the bar before the gradient is even
      // considered. This palette uses a darker step for that reason.
      expect(
        contrast(AppColors.guardianInkFaint, card),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  group('every tinted blob can carry its own icon', () {
    for (final (name, tint, ink) in [
      ('blue', AppColors.guardianTintBlue, AppColors.guardianTintBlueInk),
      ('violet', AppColors.guardianTintViolet, AppColors.guardianTintVioletInk),
      ('green', AppColors.guardianTintGreen, AppColors.guardianTintGreenInk),
      ('amber', AppColors.guardianTintAmber, AppColors.guardianTintAmberInk),
    ]) {
      test('$name clears 3:1', () {
        expect(contrast(tint, ink), greaterThanOrEqualTo(3.0));
      });
    }
  });

  test('the ground is a gradient that ends in white', () {
    // Top tinted, bottom plain, so the cards nearest the bottom still have an
    // edge to sit against.
    expect(AppColors.guardianGroundEnd, const Color(0xFFFFFFFF));
    expect(
      AppColors.guardianGroundTop.computeLuminance(),
      lessThan(AppColors.guardianGroundEnd.computeLuminance()),
    );
  });
}
