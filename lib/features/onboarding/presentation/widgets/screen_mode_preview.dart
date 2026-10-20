import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../domain/app_category.dart';

/// A thumbnail of a home screen, drawn from the colours the real one uses, so
/// the choice can be made by looking instead of by reading.
///
/// Deliberately not a screenshot: it has to stay right when the tiles are
/// renamed or recoloured, and at this size the only thing that carries is the
/// shape — how many blocks, how big, and what sits under them.
class ScreenModePreview extends StatelessWidget {
  const ScreenModePreview({
    super.key,
    required this.tiles,
    required this.categories,
    required this.hasTabBar,
  });

  /// How many app blocks the screen it stands for shows. Four against six is
  /// the whole difference between the two modes.
  final int tiles;

  final List<AppCategory> categories;

  /// 자세한 화면 has a bottom bar; 정말 쉬운 화면 has two pills and SOS.
  final bool hasTabBar;

  @override
  Widget build(BuildContext context) {
    final big = tiles <= 4;
    return AspectRatio(
      aspectRatio: 0.62,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.seniorBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.seniorHairline, width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Column(
            children: [
              // Rows rather than a GridView: a grid gives its children a
              // fixed aspect and leaves whatever is over as dead space, which
              // put a hole under the four-tile preview.
              Expanded(
                child: Column(
                  children: [
                    for (var row = 0; row < (tiles / 2).ceil(); row++) ...[
                      if (row > 0) SizedBox(height: big ? 6 : 4),
                      Expanded(
                        child: Row(
                          // Without this the row centres its children, and a
                          // DecoratedBox with no child has no height of its
                          // own — every tile came out as a hairline.
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var col = 0; col < 2; col++) ...[
                              if (col > 0) SizedBox(width: big ? 6 : 4),
                              Expanded(
                                child: _Block(
                                  category: categories[row * 2 + col],
                                  radius: big ? 9 : 7,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 6),
              if (hasTabBar)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (var i = 0; i < 3; i++)
                      Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          color: AppColors.seniorInkMuted,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                  ],
                )
              else ...[
                Row(
                  children: [
                    Expanded(child: _Bar()),
                    const SizedBox(width: 6),
                    Expanded(child: _Bar()),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  height: 13,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [AppColors.seniorSosLight, AppColors.seniorSos],
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 11,
      decoration: BoxDecoration(
        color: AppColors.seniorCardDeep,
        borderRadius: BorderRadius.circular(5),
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.category, required this.radius});

  final AppCategory category;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [category.lightColor, category.baseColor],
        ),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: category.wallColor,
            offset: const Offset(0, 2),
            spreadRadius: -1,
          ),
        ],
      ),
    );
  }
}
