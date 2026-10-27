import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'widgets/go_home_bar.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/clay_pad.dart';
import '../../../domain/pair_link.dart';
import '../../family/application/senior_pairing_controller.dart';
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
    final guardian = _Guardian.from(
      ref.watch(seniorGuardiansProvider).value ?? const [],
    );

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
      bottomNavigationBar: const SafeArea(child: GoHomeBar()),
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
                  key: SosKeys.guardian,
                  label: '보호자',
                  // Who, when there is a who. 119 and 112 carry their own
                  // meaning; this one does not, and a senior reaching for it
                  // should see the name of the person who will answer.
                  caption: guardian.caption,
                  // Yellow cannot carry white lettering — 2.38:1 — so this one
                  // is written in ink, exactly as the 카카오톡 tile is.
                  light: AppColors.seniorButtonYellowLight,
                  face: AppColors.seniorButtonYellow,
                  deep: AppColors.seniorButtonYellowDeep,
                  wall: AppColors.seniorButtonYellowWall,
                  ink: AppColors.seniorInk,
                  // Null until there is a number. A tile that looks pressable
                  // and dials nothing is worse on this screen than one that
                  // plainly cannot be pressed.
                  onTap: guardian.number == null
                      ? null
                      : () => _dial(ref, guardian.number!),
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
    super.key,
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


/// Widget keys the tests drive.
class SosKeys {
  SosKeys._();

  static const guardian = Key('sos-guardian');
}

/// Who the 보호자 button calls, and what it says when it cannot call anyone.
///
/// Three states, and they are three different sentences on purpose. 가족을
/// 연결하면 사용할 수 있어요 was shown for all of them, which made it a lie in
/// the one case it was most load-bearing: a family *was* connected, the button
/// still did nothing, and the caption told the senior to do the thing they had
/// already done.
class _Guardian {
  const _Guardian({required this.caption, this.number});

  factory _Guardian.from(List<GuardianLink> guardians) {
    final active = guardians.where((g) => g.isActive).toList(growable: false);
    if (active.isEmpty) {
      return const _Guardian(caption: '가족을 연결하면 사용할 수 있어요');
    }
    // 대표 보호자 answers for the parent, so they are who this calls. The
    // server returns them first; this does not depend on that.
    final primary = active.firstWhere(
      (g) => g.isPrimary && g.phoneNumber != null,
      orElse: () => active.firstWhere(
        (g) => g.phoneNumber != null,
        orElse: () => active.first,
      ),
    );
    final number = primary.phoneNumber;
    if (number == null) {
      return const _Guardian(caption: '자녀분 전화번호가 아직 없어요');
    }
    return _Guardian(caption: primary.displayName ?? '가족', number: number);
  }

  final String caption;

  /// Null means the tile cannot be pressed.
  final String? number;
}
