import 'package:flutter/material.dart';

import '../../../../core/widgets/clay_pad.dart';

/// One of the wide buttons that sit under the tiles on either home screen.
///
/// Shared rather than copied because the thing that holds the screen together
/// is that every pressable object is lit from the same direction — and because
/// the two homes now put different buttons here (가족 and 더 보기 on one,
/// 긴급 구조 요청 and 가족 on the other) out of the same parts.
class HomePill extends StatelessWidget {
  const HomePill({
    super.key,
    required this.label,
    required this.icon,
    required this.light,
    required this.face,
    required this.deep,
    required this.wall,
    required this.ink,
    required this.onTap,
    this.height = 80,
    this.iconSize = 29,
    this.fontSize = 23,
  });

  final String label;
  final IconData icon;

  /// The lit crown, the body, the shaded foot, and the side wall.
  final Color light;
  final Color face;
  final Color deep;
  final Color wall;

  /// What the icon and the label are drawn in. Amber takes ink; the darker
  /// faces take white.
  final Color ink;

  final VoidCallback onTap;
  final double height;
  final double iconSize;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: SizedBox(
        height: height,
        child: ClayPad(
          light: light,
          face: face,
          deep: deep,
          wall: wall,
          radius: 26,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            // Scales down rather than overflowing, the same rule the tiles
            // and SOS follow.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: iconSize, color: ink),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w900,
                      color: ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
