import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/theme/app_colors.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/domain/app_category.dart';

/// The palette the 2026-10-20 design review settled on: white ground, and
/// every pressable thing drawn as a solid object with a lit top, a shaded
/// bottom and a visible side wall.
void main() {
  test('the senior ground is white', () {
    // The cream gradient is gone. It was the one thing every reviewer named.
    expect(AppColors.seniorBackground, const Color(0xFFFFFFFF));
  });

  group('every tile colour can be extruded', () {
    for (final category in AppCategory.values) {
      test('${category.name} runs light → base → deep → wall', () {
        // The side wall is what makes the tile look like an object rather
        // than a rectangle, and it only reads if it is darker than the face
        // above it. A wall lighter than its own tile is not a wall.
        final steps = [
          category.lightColor,
          category.baseColor,
          category.deepColor,
          category.wallColor,
        ].map((c) => c.computeLuminance()).toList();

        for (var i = 1; i < steps.length; i++) {
          expect(
            steps[i],
            lessThan(steps[i - 1]),
            reason: '${category.name}: step $i is not darker than step ${i - 1}',
          );
        }
      });

      test('${category.name} letters itself legibly', () {
        // 04_SCREEN_SPEC's whole premise. The label has to clear 3:1 against
        // its own face, which is the floor for text this large. White does
        // not manage it on yellow — that face takes ink instead, and this is
        // the check that found it rather than a phone did.
        final face = category.baseColor.computeLuminance();
        final ink = category.letteringColor.computeLuminance();
        final contrast = face > ink
            ? (face + 0.05) / (ink + 0.05)
            : (ink + 0.05) / (face + 0.05);

        expect(
          contrast,
          greaterThanOrEqualTo(3.0),
          reason: '${category.name} cannot carry its own lettering',
        );
      });
    }
  });

  test('filled buttons use the terracotta the design names', () {
    // ColorScheme.fromSeed does not keep its seed — it generates a tonal
    // palette from it, and the terracotta came out of that as the muddy
    // brown that every filled button in the app was wearing.
    expect(AppTheme.senior.colorScheme.primary, AppColors.seniorPrimary);
    expect(AppTheme.senior.colorScheme.onPrimary, Colors.white);
    expect(AppTheme.guardian.colorScheme.primary, AppColors.guardianPrimary);
    expect(AppTheme.guardian.colorScheme.onPrimary, Colors.white);
  });

  group('the 가족 및 보호자 card is readable', () {
    // Its lettering was terracotta once and the small line measured 2.4:1
    // against white — well under what 12.5px needs. An accent belongs on a
    // mark, not on a sentence, and this is the check that says so.
    //
    // Measured against the card's *deep* step and not against white. The pad
    // is a gradient, so the face under a line of text is never the lightest
    // colour in it; checking the lightest one is how a grey that misses by a
    // tenth comes out looking like it passed.
    double onCard(Color ink) {
      final face = AppColors.splashCardDeep.computeLuminance();
      return (face + 0.05) / (ink.computeLuminance() + 0.05);
    }

    test('the title clears 4.5:1', () {
      expect(onCard(AppColors.splashCardTitle), greaterThanOrEqualTo(4.5));
    });

    test('the small line clears 4.5:1 too, being small', () {
      expect(onCard(AppColors.splashCardLabel), greaterThanOrEqualTo(4.5));
    });
  });

  test('an empty slot is still readable, and carries no beige', () {
    // The slot was drawn in the muted clay #C9A98C until the beige came out
    // of the senior palette. Its lettering is large, so 3:1 is the floor —
    // but a slot nobody can read is not an invitation to fill it.
    final fill = AppColors.seniorSlotFill.computeLuminance();
    final ink = AppColors.seniorSlotInk.computeLuminance();
    expect((fill + 0.05) / (ink + 0.05), greaterThanOrEqualTo(3.0));

    // Neutral: no channel may lead the others, which is what made the old
    // one read as beige.
    for (final c in [AppColors.seniorSlotFill, AppColors.seniorSlotBorder,
        AppColors.seniorSlotInk]) {
      final channels = [c.r, c.g, c.b];
      expect(
        channels.reduce(math.max) - channels.reduce(math.min),
        lessThan(0.05),
        reason: '$c is tinted, not neutral',
      );
    }
  });

  test('the ink is warm, and a step back from black', () {
    // Pure-ish black on a white ground measured 17.4:1 and the strokes of
    // large glyphs read as though they were bleeding — the bright ground
    // spreading into them. This is one step back from that, warmed to the
    // same side as the terracotta and the amber.
    //
    // The floor matters as much as the ceiling: past about 12:1 the ink stops
    // looking solid and starts looking faded, which is the opposite failure.
    final onWhite = 1.05 / (AppColors.seniorInk.computeLuminance() + 0.05);
    expect(onWhite, lessThan(15.0), reason: 'dark enough to bleed');
    expect(onWhite, greaterThan(12.0), reason: 'so pale it reads as faded');

    // Warm: red leads, blue trails. A neutral grey here would sit apart from
    // every other colour on the senior's screens.
    final ink = AppColors.seniorInk;
    expect(ink.r, greaterThan(ink.g));
    expect(ink.g, greaterThan(ink.b));
  });

  test('가족 is lettered in ink, because its face is a light amber', () {
    // Short-wavelength colours go first as eyes age, so the two home buttons
    // are amber and brown rather than the blue and teal they were. Amber is
    // too light for white lettering, so it takes dark ink instead.
    final face = AppColors.seniorFamily.computeLuminance();
    final contrast = (face + 0.05) / (AppColors.seniorInk.computeLuminance() + 0.05);

    expect(contrast, greaterThanOrEqualTo(4.5));
  });
}
