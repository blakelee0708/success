import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../domain/app_category.dart';
import '../../../../core/widgets/clay_pad.dart';
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
    // An app button nobody has chosen an app for yet. Drawn hollow, like the
    // empty slot on 자세한 화면, because the one thing it must not look like
    // is an app: a senior who reads it as one presses it, nothing opens, and
    // they decide the phone is broken. Hollow says *nothing is standing here
    // yet*, and the label says what to do about it.
    if (app.awaitingChoice) return _Unchosen(label: app.label, onTap: onTap);

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
                // An installed app wears its own icon, because that is the
                // thing the senior recognises — they are looking for the
                // picture they already know, not for our word for it. The
                // generic glyph is the fallback for a button whose icon
                // could not be read, and for the guardian's half, which is
                // never sent one.
                if (app.iconBytes != null)
                  Image.memory(
                    app.iconBytes!,
                    width: 44,
                    height: 44,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (context, _, _) => Icon(
                      app.category.icon,
                      size: 44,
                      color: ink,
                      shadows: onDark ? _lift : null,
                    ),
                  )
                else
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

/// The guardian's seeded button, before the senior has filled it in.
class _Unchosen extends StatelessWidget {
  const _Unchosen({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        // The gaps answer too, so a tile this size has no dead patches.
        behavior: HitTestBehavior.opaque,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.seniorSlotFill,
            borderRadius: BorderRadius.circular(34),
            border: Border.all(
              color: AppColors.seniorSlotBorder,
              width: 2.5,
              strokeAlign: BorderSide.strokeAlignInside,
            ),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.touch_app_outlined,
                      size: 44,
                      color: AppColors.seniorSlotInk,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: AppColors.seniorSlotInk,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
