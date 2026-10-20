import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/clay_pad.dart';
import '../../../domain/launcher_app.dart';
import '../application/senior_settings_controller.dart';
import '../data/app_launcher.dart';
import 'widgets/app_tile.dart';
import '../../care/presentation/care_consent_prompt.dart';
import '../../family/application/senior_pairing_controller.dart';
import '../../family/presentation/primary_guardian_prompt.dart';
import 'widgets/default_home_prompt.dart';
import 'widgets/home_strip.dart';
import 'widgets/sos_button.dart';

/// 정말 쉬운 화면 — the clock-and-family band, 2x2 tiles, 가족, 더 보기, SOS.
/// No scrolling, depth 1.
///
/// The tiles come from the saved settings rather than the constant defaults,
/// so a rename or a removal made in 설정 actually reaches the home screen.
class EasyHomeScreen extends ConsumerWidget {
  const EasyHomeScreen({super.key});

  /// One spacing system, so the seams line up. The vertical rule between the
  /// tiles and the one between 가족 and 더 보기 are both [_gutter]: they were
  /// 16 and 14 once, and the buttons visibly failed to line up.
  static const _gutter = 16.0;
  static const _rowGap = 22.0;
  static const _sectionGap = 24.0;
  static const _pillHeight = 80.0;

  /// The band gives up its height before the tiles do, but never all of it.
  static const _minStrip = 110.0;

  /// Says so when nothing opened, rather than leaving the senior tapping a
  /// tile that does nothing. Almost always the app is simply not installed.
  Future<void> _openApp(
    BuildContext context,
    WidgetRef ref,
    LauncherApp app,
  ) async {
    final opened = await ref
        .read(appLauncherProvider)
        .open(launchRequestFor(app.category));
    if (opened || !context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('${app.label}을(를) 열 수 없어요. 자녀분께 말씀해 주세요.')),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(seniorSettingsControllerProvider).value?.apps;
    final apps = (saved == null || saved.isEmpty) ? defaultEasyApps : saved;
    final rows = (apps.length / 2).ceil();
    // `04_SCREEN_SPEC` gives this slot as 가족 연결 또는 자녀 이름 버튼. Talking
    // to the family moved up into [HomeStrip], which shows their newest
    // message, so what is left for the button is the connection itself —
    // still named for the job a senior has at the time.
    final connected =
        (ref.watch(seniorGuardiansProvider).value ?? const []).isNotEmpty;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
          child: Column(
            children: [
              const CareConsentPrompt(),
              const PrimaryGuardianPrompt(),
              const DefaultHomePrompt(),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Square tiles, and the band takes whatever is left over.
                    // Stretching the tiles to fill instead gave 169x250
                    // rectangles, which is what the band was invented to fix.
                    final tile = (constraints.maxWidth - _gutter) / 2;
                    final square = rows * tile + (rows - 1) * _rowGap;
                    final room =
                        constraints.maxHeight - _sectionGap - _minStrip;
                    final grid = math.max(0.0, math.min(square, room));

                    return Column(
                      children: [
                        const Expanded(child: HomeStrip()),
                        const SizedBox(height: _sectionGap),
                        SizedBox(
                          height: grid,
                          child: GridView.count(
                            crossAxisCount: 2,
                            mainAxisSpacing: _rowGap,
                            crossAxisSpacing: _gutter,
                            childAspectRatio: grid > 0
                                ? tile / ((grid - (rows - 1) * _rowGap) / rows)
                                : 1,
                            physics: const NeverScrollableScrollPhysics(),
                            children: [
                              for (final app in apps)
                                AppTile(
                                  app: app,
                                  onTap: () => _openApp(context, ref, app),
                                ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: _sectionGap),
              Row(
                children: [
                  Expanded(
                    child: _Pill(
                      label: connected ? '가족' : '가족 연결',
                      icon: Icons.family_restroom,
                      light: AppColors.seniorFamilyLight,
                      face: AppColors.seniorFamily,
                      deep: AppColors.seniorFamilyDeep,
                      wall: AppColors.seniorFamilyWall,
                      // Amber is too light to carry white lettering, so this
                      // one is written in ink. Blue and teal are gone from
                      // the senior's screens entirely: short-wavelength
                      // colours are the first an ageing eye loses.
                      ink: AppColors.seniorInk,
                      onTap: () => context.push(Routes.familyLink),
                    ),
                  ),
                  const SizedBox(width: _gutter),
                  Expanded(
                    child: _Pill(
                      label: '더 보기',
                      icon: Icons.apps,
                      light: AppColors.seniorMoreLight,
                      face: AppColors.seniorMore,
                      deep: AppColors.seniorMoreDeep,
                      wall: AppColors.seniorMoreWall,
                      ink: Colors.white,
                      onTap: () => context.go(Routes.moreApps),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: _sectionGap),
              SosButton(onTap: () => context.go(Routes.sos)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.icon,
    required this.light,
    required this.face,
    required this.deep,
    required this.wall,
    required this.ink,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color light;
  final Color face;
  final Color deep;
  final Color wall;
  final Color ink;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: SizedBox(
        height: EasyHomeScreen._pillHeight,
        child: ClayPad(
          light: light,
          face: face,
          deep: deep,
          wall: wall,
          radius: 26,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 29, color: ink),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 23,
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
