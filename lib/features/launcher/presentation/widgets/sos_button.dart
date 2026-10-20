import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/clay_pad.dart';

/// Always-visible red emergency bar, drawn as the deepest object on the
/// screen — it is the one control that must read as pressable from across a
/// room.
class SosButton extends StatelessWidget {
  const SosButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '긴급 구조 요청',
      child: SizedBox(
        height: 96,
        child: ClayPad(
          light: AppColors.seniorSosLight,
          face: AppColors.seniorSos,
          deep: AppColors.seniorSosDeep,
          wall: AppColors.seniorSosWall,
          radius: 28,
          onTap: onTap,
          // Scales down rather than clipping: at 아주 크게 the label and
          // icon no longer fit the pill, and SOS is the one control that
          // must never be half off the screen.
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.notifications_active,
                    color: Colors.white,
                    size: 31,
                    shadows: [
                      Shadow(
                        color: Color(0x4D000000),
                        offset: Offset(0, 3),
                        blurRadius: 3,
                      ),
                    ],
                  ),
                  SizedBox(width: 13),
                  Text(
                    '긴급 구조 요청',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          color: Color(0x52000000),
                          offset: Offset(0, 2),
                          blurRadius: 5,
                        ),
                      ],
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
