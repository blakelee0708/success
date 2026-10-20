import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/clay_pad.dart';
import '../data/app_launcher.dart';

/// 설정 — everything a senior can change about their own phone.
///
/// Reached from the 설정 tile on 자세한 화면 and from 더 보기 on the easy one.
/// It was a list of six identical Material cards in the warm brown ink that
/// came out of the palette in the 2026-10-20 review, which left it looking
/// like a different app from the home screen it opens off.
///
/// The six are not six of a kind, so they are not drawn as six of a kind:
/// two are about this phone's screen, two are about the family, and two are
/// not built. The last pair say so by being unpressable rather than by
/// opening a screen that apologises.
class SeniorSettingsScreen extends ConsumerWidget {
  const SeniorSettingsScreen({super.key});

  static const homeAppRow = Key('senior-settings-home-app');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Shown only where the phone says this app is not its home app, which is
    // the case onboarding's question leaves behind when a senior says 나중에.
    final offerHomeApp =
        ref.watch(isDefaultHomeProvider).value == false;

    return Scaffold(
      backgroundColor: AppColors.seniorBackground,
      appBar: AppBar(
        backgroundColor: AppColors.seniorBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          '설정',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.6,
            color: AppColors.seniorInk,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            const _GroupTitle('이 화면'),
            _Row(
              label: '앱 설정하기',
              detail: '버튼의 이름과 색, 순서를 바꿉니다',
              icon: Icons.grid_view_rounded,
              face: AppColors.seniorButtonPurple,
              light: AppColors.seniorButtonPurpleLight,
              deep: AppColors.seniorButtonPurpleDeep,
              wall: AppColors.seniorButtonPurpleWall,
              onTap: () => context.push(Routes.appSettings),
            ),
            _Row(
              label: '글씨 크기 조절하기',
              detail: '보통부터 제일 크게까지',
              icon: Icons.format_size_rounded,
              face: AppColors.seniorButtonGreen,
              light: AppColors.seniorButtonGreenLight,
              deep: AppColors.seniorButtonGreenDeep,
              wall: AppColors.seniorButtonGreenWall,
              onTap: () => context.push(Routes.fontSize),
            ),
            if (offerHomeApp)
              _Row(
                key: SeniorSettingsScreen.homeAppRow,
                label: '첫 화면으로 정하기',
                detail: '홈 버튼을 누르면 이 화면이 나옵니다',
                icon: Icons.home_rounded,
                face: AppColors.seniorSos,
                light: AppColors.seniorSosLight,
                deep: AppColors.seniorSosDeep,
                wall: AppColors.seniorSosWall,
                onTap: () => context.push(Routes.homeApp),
              ),
            const SizedBox(height: 26),
            const _GroupTitle('가족'),
            _Row(
              label: '가족 메시지',
              detail: '자녀분과 주고받은 이야기',
              icon: Icons.chat_bubble_rounded,
              face: AppColors.seniorFamily,
              light: AppColors.seniorFamilyLight,
              deep: AppColors.seniorFamilyDeep,
              wall: AppColors.seniorFamilyWall,
              ink: AppColors.seniorInk,
              onTap: () => context.push(Routes.familyMessages),
            ),
            _Row(
              label: '가족 연결 설정',
              detail: '누가 이 폰을 돌봐 드리는지',
              icon: Icons.family_restroom,
              face: AppColors.seniorButtonPink,
              light: AppColors.seniorButtonPinkLight,
              deep: AppColors.seniorButtonPinkDeep,
              wall: AppColors.seniorButtonPinkWall,
              onTap: () => context.push(Routes.familyLink),
            ),
            const SizedBox(height: 26),
            const _GroupTitle('아직 준비 중'),
            const _Row(
              label: '진동/벨소리 전환',
              detail: '곧 쓰실 수 있어요',
              icon: Icons.volume_up_rounded,
              face: AppColors.seniorMore,
              light: AppColors.seniorMoreLight,
              deep: AppColors.seniorMoreDeep,
              wall: AppColors.seniorMoreWall,
            ),
            const _Row(
              label: '잘보이네 사용하지 않기',
              detail: '곧 쓰실 수 있어요',
              icon: Icons.logout_rounded,
              face: AppColors.seniorMore,
              light: AppColors.seniorMoreLight,
              deep: AppColors.seniorMoreDeep,
              wall: AppColors.seniorMoreWall,
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 0, 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.3,
          color: AppColors.seniorInkMuted,
        ),
      ),
    );
  }
}

/// One setting, drawn as the same object the home screen is made of.
class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.label,
    required this.detail,
    required this.icon,
    required this.face,
    required this.light,
    required this.deep,
    required this.wall,
    this.ink = Colors.white,
    this.onTap,
  });

  final String label;
  final String detail;
  final IconData icon;
  final Color face;
  final Color light;
  final Color deep;
  final Color wall;

  /// White on every face but the amber one, which is too light to carry it.
  final Color ink;

  /// Null leaves the row unpressable, which is how the two unbuilt settings
  /// say so — rather than by opening a screen that apologises.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        // 0.6 rather than 0.5: Opacity fades the lettering with the face, and
        // the line saying why a row cannot be used is the only thing on it
        // worth reading.
        child: Opacity(
          opacity: enabled ? 1 : 0.6,
          child: SizedBox(
            height: 92,
            child: ClayPad(
              light: light,
              face: face,
              deep: deep,
              wall: wall,
              radius: 26,
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  children: [
                    Icon(icon, size: 34, color: ink),
                    const SizedBox(width: 16),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              label,
                              style: TextStyle(
                                fontSize: 23,
                                height: 1.2,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                                color: ink,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              detail,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (enabled) ...[
                      const SizedBox(width: 10),
                      Icon(Icons.chevron_right, size: 28, color: ink),
                    ],
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
