import 'package:flutter/material.dart';

import '../../../../core/widgets/clay_pad.dart';
import '../../../../domain/app_category.dart';
import '../../../../domain/launcher_app.dart';

/// One home-screen tile, drawn as a pressable object by [ClayPad].
///
/// **Every colour comes from the app, not from its category.** They used to
/// be read off `app.category` directly, which meant a colour the senior
/// picked in 앱 설정하기 was written to disk, synced to the server, and drawn
/// by nobody. On a phone that reads as the setting being broken, on the one
/// screen where they cannot work around it.
///
/// The lettering is measured rather than assumed white: a yellow face cannot
/// carry white text and takes ink instead, whether that yellow arrived from
/// the 카카오톡 category or from somebody choosing it.
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
    final ink = app.letteringColor;
    final onDark = ink == Colors.white;
    return Semantics(
      button: true,
      label: app.label,
      child: ClayPad(
        light: app.lightColor,
        face: app.baseColor,
        deep: app.deepColor,
        wall: app.wallColor,
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
                  app.category.icon,
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
