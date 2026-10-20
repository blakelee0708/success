import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/clay_pad.dart';
import '../data/phone_dialer.dart';

/// SOS — choose 119 / 112 / 보호자. Selecting a number OPENS the dialer with
/// the number pre-filled; it never calls. The user must press call in the OS
/// dialer (04_SCREEN_SPEC / 06_PERMISSION_AND_POLICY).
///
/// The three were the same red until the 2026-10-20 review, which left the
/// numbers as the only thing telling them apart — on the screen where getting
/// it right matters most and the reader is most rattled. They are now three
/// colours, and the colour carries as far across a room as the digits do.
class SosScreen extends ConsumerWidget {
  const SosScreen({super.key});

  Future<void> _dial(WidgetRef ref, String number) async {
    await ref.read(phoneDialerProvider).openDialer(number);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.seniorBackground,
      appBar: AppBar(
        backgroundColor: AppColors.seniorBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          '긴급 연락',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.6,
            color: AppColors.seniorInk,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            children: [
              Expanded(
                child: _SosTile(
                  label: '119',
                  caption: '불 · 구급',
                  light: AppColors.seniorSosLight,
                  face: AppColors.seniorSos,
                  deep: AppColors.seniorSosDeep,
                  wall: AppColors.seniorSosWall,
                  ink: Colors.white,
                  onTap: () => _dial(ref, '119'),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _SosTile(
                  label: '112',
                  caption: '경찰',
                  light: AppColors.seniorButtonPurpleLight,
                  face: AppColors.seniorButtonPurple,
                  deep: AppColors.seniorButtonPurpleDeep,
                  wall: AppColors.seniorButtonPurpleWall,
                  ink: Colors.white,
                  onTap: () => _dial(ref, '112'),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _SosTile(
                  label: '보호자',
                  caption: '가족을 연결하면 사용할 수 있어요',
                  // Yellow cannot carry white lettering — 2.38:1 — so this one
                  // is written in ink, exactly as the 카카오톡 tile is.
                  light: AppColors.seniorButtonYellowLight,
                  face: AppColors.seniorButtonYellow,
                  deep: AppColors.seniorButtonYellowDeep,
                  wall: AppColors.seniorButtonYellowWall,
                  ink: AppColors.seniorInk,
                  onTap: null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SosTile extends StatelessWidget {
  const _SosTile({
    required this.label,
    required this.caption,
    required this.light,
    required this.face,
    required this.deep,
    required this.wall,
    required this.ink,
    this.onTap,
  });

  final String label;
  final String caption;
  final Color light;
  final Color face;
  final Color deep;
  final Color wall;
  final Color ink;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    /// Lifts white lettering off the face it sits on, the same way the home
    /// tiles do. Omitted where the lettering is ink.
    const lift = [
      Shadow(color: Color(0x4D000000), offset: Offset(0, 2), blurRadius: 4),
    ];
    final onDark = ink == Colors.white;

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      // 0.75, not the 0.5 this started at. Fading the whole subtree fades the
      // lettering with the face: at 0.5 the line explaining *why* the tile is
      // unavailable measured 2.99:1 against it, and that line is the only
      // thing on the tile worth reading.
      child: Opacity(
        opacity: enabled ? 1 : 0.75,
        child: ClayPad(
          light: light,
          face: face,
          deep: deep,
          wall: wall,
          radius: 30,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            // Scales down rather than clipping. This screen is reached from
            // the biggest button on the home screen, and 제일 크게 is a size a
            // senior can be on when they reach it.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      // As big as the tile will hold. These are the two
                      // numbers on the screen and the reader is rattled.
                      fontSize: 72,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                      color: ink,
                      shadows: onDark ? lift : null,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    caption,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: ink,
                      shadows: onDark ? lift : null,
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
