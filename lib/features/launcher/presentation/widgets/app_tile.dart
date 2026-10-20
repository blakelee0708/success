import 'package:flutter/material.dart';

import '../../../../core/widgets/clay_pad.dart';
import '../../../../domain/app_category.dart';
import '../../../../domain/launcher_app.dart';

/// One home-screen tile, drawn as a pressable object by [ClayPad].
///
/// The lettering colour comes from the category rather than being white
/// outright: the yellow face cannot carry white text and takes ink instead.
class AppTile extends StatelessWidget {
  const AppTile({super.key, required this.app, required this.onTap});

  final LauncherApp app;
  final VoidCallback onTap;

  /// Lifts white lettering off the face it sits on. Omitted where the
  /// lettering is ink, which a dark shadow would only smudge.
  static const _lift = [
    Shadow(color: Color(0x4D000000), offset: Offset(0, 2), blurRadius: 4),
  ];

  @override
  Widget build(BuildContext context) {
    final cat = app.category;
    final ink = cat.letteringColor;
    final onDark = ink == Colors.white;
    return Semantics(
      button: true,
      label: app.label,
      child: ClayPad(
        light: cat.lightColor,
        face: cat.baseColor,
        deep: cat.deepColor,
        wall: cat.wallColor,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          // The whole tile scales down to fit rather than overflowing.
          // Raising the text size is the point of this app, so a tile that
          // breaks at 아주 크게 breaks the feature it exists to serve.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  cat.icon,
                  size: 44,
                  color: ink,
                  shadows: onDark ? _lift : null,
                ),
                const SizedBox(height: 10),
                Text(
                  app.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: ink,
                    shadows: onDark ? _lift : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
