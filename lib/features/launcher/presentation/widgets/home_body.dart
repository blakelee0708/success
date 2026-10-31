import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../domain/senior_settings.dart';
import '../../application/senior_settings_controller.dart';
import 'home_strip.dart';
import 'home_utility_row.dart';

/// The part both homes share: the clock-and-family band, and the grid of
/// tiles under it.
///
/// One widget because the geometry is the hard part and it is the same
/// geometry twice. The tiles are kept square where there is room for it; where
/// there is not — 자세한 화면 asks for eight of them in the height the easy
/// screen gives four — the rows shrink and the band keeps its own height
/// instead. That order matters: taking the height out of the band would drop
/// the clock from 50px to 35px, and then the two screens no longer read as
/// the same app.
///
/// Place it inside an [Expanded]: it sizes itself from the space it is given.
class HomeBody extends ConsumerWidget {
  const HomeBody({super.key, required this.tiles, required this.rowGap});

  /// The cells of the grid, in order, two to a row.
  final List<Widget> tiles;

  /// Vertical space between rows. 자세한 화면 runs tighter than the easy one
  /// because it has twice as many rows to fit.
  final double rowGap;

  /// The vertical rule between two tiles, and between the two buttons under
  /// them. They were 16 and 14 once, and the buttons visibly failed to line up.
  static const gutter = 16.0;

  /// Between the band, the grid and the buttons.
  static const sectionGap = 24.0;

  /// What the band is actually drawn at — date, clock, rule, family line. It
  /// is wrapped in a `FittedBox`, so giving it less than this does not
  /// overflow or throw: it scales the whole band down, clock and all. At the
  /// 110px floor below, the clock comes out at 29px instead of 50.
  /// Raised from 192 on 2026-10-27, after the band was read on a real phone
  /// and called too small.
  ///
  /// The sizes inside it could not simply go up: the content already stood at
  /// 158px against a 160px budget, and the `FittedBox` answers anything
  /// larger by scaling the whole band back down — so every increase cancelled
  /// itself and the band looked unchanged. That is the same silence this
  /// wrapper has produced twice before. The height had to move with the type.
  ///
  /// 150 since 2026-10-31, when the date went from 20px to 34px: 18px more
  /// line, and the same rule - the height moves with the type or the
  /// `FittedBox` takes it back out of the clock.
  static const preferredStrip = 150.0;

  /// The band yields down to this, but only when the rows could not otherwise
  /// hold an icon and a label.
  static const minStrip = 96.0;

  /// The shortest a row can be and still draw a 44px icon over a label.
  /// The shortest a row can be and still draw a 44px icon over a label.
  static const minRow = 92.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = (tiles.length / 2).ceil();
    // Both of 소리 and 인터넷 can be taken off now, and when they are this
    // row takes no height rather than leaving a 48px band of nothing. The
    // grid gets that height back, which is the same arithmetic the band and
    // the grid already share.
    final utility = HomeUtilityRow.visibleFor(
      ref.watch(seniorSettingsControllerProvider).value ??
          const SeniorSettings(),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Square tiles, and the band takes whatever is left over. Stretching
        // the tiles to fill instead gave 169x250 rectangles, which is what the
        // band was invented to fix.
        final tile = (constraints.maxWidth - gutter) / 2;
        final square = rows * tile + (rows - 1) * rowGap;
        final available =
            constraints.maxHeight -
            14 -
            (utility ? HomeUtilityRow.height + sectionGap : 0);

        // The band is laid out at its drawn height and the grid takes what is
        // left. The other way round — which is what this did at first — let
        // 자세한 화면's eight rows push the band to its 110px floor, and the
        // clock was silently scaled to 29px while the easy screen's stayed 50.
        //
        // Only when the rows could not hold an icon and a label on what that
        // leaves does the band start giving height back.
        final gaps = (rows - 1) * rowGap;
        final cap = available - preferredStrip >= rows * minRow + gaps
            ? available - preferredStrip
            : available - minStrip;
        final grid = math.max(0.0, math.min(square, cap));
        final rowHeight = rows > 0 ? (grid - gaps) / rows : 0.0;

        return Column(
          children: [
            const Expanded(child: HomeStrip()),
            const SizedBox(height: 14),
            // Directly under the clock, above the apps: these change the
            // phone rather than open anything, and the band is the part of
            // the screen that is about the phone itself.
            if (utility) ...[
              const HomeUtilityRow(),
              const SizedBox(height: sectionGap),
            ],
            SizedBox(
              height: grid,
              child: GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: rowGap,
                crossAxisSpacing: gutter,
                childAspectRatio: rowHeight > 0 ? tile / rowHeight : 1,
                physics: const NeverScrollableScrollPhysics(),
                children: tiles,
              ),
            ),
          ],
        );
      },
    );
  }
}
