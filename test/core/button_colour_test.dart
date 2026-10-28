import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/theme/app_colors.dart';
import 'package:app/domain/app_category.dart';
import 'package:app/domain/launcher_app.dart';

/// The colours a senior (or their guardian) can pick by hand.
///
/// They were five, all warm, and — worse — **nothing drew them**: `AppTile`
/// painted `category.baseColor` directly, so a chosen colour was saved to
/// disk, synced to the server and read by nobody. On a real phone that looked
/// like the setting did not work, which is the one thing on that screen a
/// senior cannot work around.
///
/// A picked colour has to carry the whole clay object, not just its face.
/// Three parts make it and dropping any leaves a flat rectangle, so the other
/// three are derived from the one the person chose.
double _luminance(Color c) => c.computeLuminance();

double _contrast(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  final hi = math.max(la, lb), lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('there are at least twelve to choose from', () {
    // Five, all warm, was not a palette — it was the terracotta family with
    // the lights turned up and down.
    expect(ButtonColor.values.length, greaterThanOrEqualTo(12));
  });

  test('the five that already existed are still there, by name', () {
    // `button_color` stores the enum's *name*, on disk and on the server, and
    // an unknown name reads back as null — which silently resets a button a
    // senior had already recoloured. Renaming one is a data migration, not a
    // rename.
    for (final kept in ['vermilion', 'orange', 'yellow', 'rust', 'rose']) {
      expect(
        ButtonColor.values.map((c) => c.name),
        contains(kept),
        reason: '$kept would reset every button already set to it',
      );
    }
  });

  group('every colour makes a whole clay object', () {
    for (final colour in ButtonColor.values) {
      test('${colour.name} — the wall is the darkest of the four', () {
        // The wall is the shadow the tile stands on. Lighter than the face,
        // it stops reading as an object at all.
        final face = _luminance(colour.color);
        expect(_luminance(colour.wallColor), lessThan(face));
        expect(
          _luminance(colour.wallColor),
          lessThan(_luminance(colour.deepColor)),
        );
        expect(_luminance(colour.lightColor), greaterThan(face));
      });

      test('${colour.name} — it carries lettering it can actually hold', () {
        // Same 3:1 floor as the category faces. Yellow cannot hold white and
        // takes ink, exactly as the 카카오톡 tile does.
        final ink = colour.letteringColor;
        expect(
          ink == Colors.white || ink == AppColors.seniorInk,
          isTrue,
          reason: 'lettering is white or the app ink, nothing else',
        );
        expect(_contrast(colour.color, ink), greaterThanOrEqualTo(3.0));
      });

      test('${colour.name} — it picks the better of the two', () {
        // Not a hand-kept list that can drift from the colours beside it.
        final white = _contrast(colour.color, Colors.white);
        final inked = _contrast(colour.color, AppColors.seniorInk);
        expect(
          colour.letteringColor,
          white >= inked ? Colors.white : AppColors.seniorInk,
        );
      });
    }
  });

  group('a button draws the colour it was given', () {
    const plain = LauncherApp(
      id: 'a',
      label: '전화',
      category: AppCategory.phone,
    );

    test('with no choice it is the category, as before', () {
      expect(plain.baseColor, AppCategory.phone.baseColor);
      expect(plain.lightColor, AppCategory.phone.lightColor);
      expect(plain.deepColor, AppCategory.phone.deepColor);
      expect(plain.wallColor, AppCategory.phone.wallColor);
      expect(plain.letteringColor, AppCategory.phone.letteringColor);
    });

    test('a chosen colour replaces all four, not only the face', () {
      // Replacing the face alone leaves the green wall under a blue face.
      final picked = plain.withColor(ButtonColor.indigo);
      expect(picked.baseColor, ButtonColor.indigo.color);
      expect(picked.lightColor, ButtonColor.indigo.lightColor);
      expect(picked.deepColor, ButtonColor.indigo.deepColor);
      expect(picked.wallColor, ButtonColor.indigo.wallColor);
    });

    test('and the lettering with them', () {
      // 전화 is white on green. Painted yellow and left white, its label
      // measures under 2:1 and the tile is unreadable.
      final yellow = plain.withColor(ButtonColor.yellow);
      expect(yellow.letteringColor, AppColors.seniorInk);
      expect(
        _contrast(yellow.baseColor, yellow.letteringColor),
        greaterThanOrEqualTo(3.0),
      );
    });

    test('clearing it goes back to the category', () {
      expect(
        plain.withColor(ButtonColor.indigo).withColor(null).baseColor,
        AppCategory.phone.baseColor,
      );
    });
  });
}
