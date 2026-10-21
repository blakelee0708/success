import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/launcher_app.dart';
import '../application/senior_settings_controller.dart';
import '../data/app_launcher.dart';
import 'widgets/app_tile.dart';
import '../../family/application/senior_pairing_controller.dart';
import 'widgets/home_body.dart';
import '../../care/presentation/senior_ring_layer.dart';
import 'widgets/senior_notice_layer.dart';
import 'widgets/home_pill.dart';
import 'widgets/sos_button.dart';

/// 정말 쉬운 화면 — the clock-and-family band, 2x2 tiles, 가족, 더 보기, SOS.
/// No scrolling, depth 1.
///
/// The tiles come from the saved settings rather than the constant defaults,
/// so a rename or a removal made in 설정 actually reaches the home screen.
class EasyHomeScreen extends ConsumerWidget {
  const EasyHomeScreen({super.key});

  /// Four tiles have room to breathe where 자세한 화면's eight do not.
  static const _rowGap = 22.0;

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
    // `04_SCREEN_SPEC` gives this slot as 가족 연결 또는 자녀 이름 버튼. Talking
    // to the family moved up into [HomeStrip], which shows their newest
    // message, so what is left for the button is the connection itself —
    // still named for the job a senior has at the time.
    final connected =
        (ref.watch(seniorGuardiansProvider).value ?? const []).isNotEmpty;

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
              child: Column(
                children: [
                  Expanded(
                    child: HomeBody(
                      rowGap: _rowGap,
                      tiles: [
                        for (final app in apps)
                          AppTile(
                            app: app,
                            onTap: () => _openApp(context, ref, app),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: HomeBody.sectionGap),
                  Row(
                    children: [
                      Expanded(
                        child: HomePill(
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
                      const SizedBox(width: HomeBody.gutter),
                      Expanded(
                        child: HomePill(
                          label: '더 보기',
                          icon: Icons.apps,
                          light: AppColors.seniorMoreLight,
                          face: AppColors.seniorMore,
                          deep: AppColors.seniorMoreDeep,
                          wall: AppColors.seniorMoreWall,
                          ink: Colors.white,
                          // Straight to 설정. The screen that used to sit in
                          // between held one button and a line saying apps
                          // cannot be added yet, which is a screen that exists
                          // to be passed through.
                          onTap: () => context.push(Routes.seniorSettings),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: HomeBody.sectionGap),
                  SosButton(onTap: () => context.go(Routes.sos)),
                ],
              ),
            ),
          ),
          const SeniorNoticeLayer(),
          // Above the consent cards: a ring is urgent and over in a
          // minute, and a senior cannot be asked to answer a question
          // while their phone is screaming at them.
          const SeniorRingLayer(),
        ],
      ),
    );
  }
}
