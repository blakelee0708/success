import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'home_strip.dart';

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
class HomeBody extends StatelessWidget {
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

  /// The band gives up its height before the tiles do, but never all of it.
  static const minStrip = 110.0;

  @override
  Widget build(BuildContext context) {
    final rows = (tiles.length / 2).ceil();

    return LayoutBuilder(
      builder: (context, constraints) {
        // Square tiles, and the band takes whatever is left over. Stretching
        // the tiles to fill instead gave 169x250 rectangles, which is what the
        // band was invented to fix.
        final tile = (constraints.maxWidth - gutter) / 2;
        final square = rows * tile + (rows - 1) * rowGap;
        final room = constraints.maxHeight - sectionGap - minStrip;
        final grid = math.max(0.0, math.min(square, room));
        final rowHeight = rows > 0 ? (grid - (rows - 1) * rowGap) / rows : 0.0;

        return Column(
          children: [
            const Expanded(child: HomeStrip()),
            const SizedBox(height: sectionGap),
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
