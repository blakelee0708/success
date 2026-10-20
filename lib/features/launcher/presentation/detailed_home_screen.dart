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
import 'widgets/home_body.dart';
import 'widgets/home_pill.dart';

/// 자세한 화면 — the same band and the same clay as 정말 쉬운 화면, with eight
/// cells instead of four and 긴급 구조 요청 beside 가족 underneath.
///
/// It was a scrolling grid under a Material [NavigationBar] until the
/// 2026-10-20 review. Two things were wrong with that, and neither was colour:
/// the tab bar was the one part of the screen the text size never reached, and
/// having one home scroll while the other did not made them read as two
/// different apps.
///
/// 설정 is a tile here rather than a tab. It cannot simply be dropped — this
/// list is the only way into 글씨 크기 조절하기 in the whole app, which is the
/// setting the app is sold on.
class DetailedHomeScreen extends ConsumerWidget {
  const DetailedHomeScreen({super.key});

  /// Eight cells fit in 480px, so the rows run 108px and the gaps are tighter
  /// than the easy screen's 22. The band keeps its full height either way.
  static const _rowGap = 16.0;

  /// 긴급 구조 요청 gets the wider share. Split evenly, its label scales down
  /// to 17px — smaller than the tile labels above it, which would make SOS the
  /// smallest lettering on a screen where it has to carry furthest.
  static const _sosFlex = 203;
  static const _familyFlex = 135;

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
    // Saved buttons rather than the constant defaults, so an edit made in
    // 설정 reaches the home screen.
    final saved = ref.watch(seniorSettingsControllerProvider).value?.apps;
    final apps = (saved == null || saved.isEmpty) ? defaultDetailedApps : saved;
    final connected =
        (ref.watch(seniorGuardiansProvider).value ?? const []).isNotEmpty;

    // One empty slot after 설정, or two where that would leave a half-finished
    // row. Padding the grid out to eight whatever the senior kept would fill
    // most of their home with 추가하기, which is a reproach rather than an
    // invitation.
    final slots = (apps.length + 1).isEven ? 2 : 1;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
          child: Column(
            children: [
              const CareConsentPrompt(),
              const PrimaryGuardianPrompt(),
              Expanded(
                child: HomeBody(
                  rowGap: _rowGap,
                  tiles: [
                    for (final app in apps)
                      AppTile(
                        app: app,
                        onTap: () => _openApp(context, ref, app),
                      ),
                    _SettingsTile(
                      onTap: () => context.push(Routes.seniorSettings),
                    ),
                    for (var i = 0; i < slots; i++)
                      _AddSlot(
                        onTap: () => context.push(Routes.appSettings),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: HomeBody.sectionGap),
              Row(
                children: [
                  Expanded(
                    flex: _sosFlex,
                    child: HomePill(
                      label: '긴급 구조 요청',
                      icon: Icons.notifications_active,
                      light: AppColors.seniorSosLight,
                      face: AppColors.seniorSos,
                      deep: AppColors.seniorSosDeep,
                      wall: AppColors.seniorSosWall,
                      ink: Colors.white,
                      onTap: () => context.go(Routes.sos),
                    ),
                  ),
                  const SizedBox(width: HomeBody.gutter),
                  Expanded(
                    flex: _familyFlex,
                    child: HomePill(
                      label: connected ? '가족' : '가족 연결',
                      icon: Icons.family_restroom,
                      light: AppColors.seniorFamilyLight,
                      face: AppColors.seniorFamily,
                      deep: AppColors.seniorFamilyDeep,
                      wall: AppColors.seniorFamilyWall,
                      // Amber is too light to carry white lettering.
                      ink: AppColors.seniorInk,
                      onTap: () => context.push(Routes.familyLink),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 설정, drawn as a tile but deliberately not as an app.
///
/// Brown rather than one of the category colours: it stands next to 전화 and
/// 문자 and must not be mistaken for one of them. It is also the one tile on
/// the screen a senior is not expected to use — it is there for the son or
/// daughter sitting beside them.
class _SettingsTile extends StatelessWidget {
  const _SettingsTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '설정',
      child: ClayPad(
        light: AppColors.seniorMoreLight,
        face: AppColors.seniorMore,
        deep: AppColors.seniorMoreDeep,
        wall: AppColors.seniorMoreWall,
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(10),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.settings, size: 44, color: Colors.white),
                SizedBox(height: 10),
                Text(
                  '설정',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
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

/// An empty cell. Hollow on purpose: the whole point of the shape is that
/// there is nothing standing there yet, so it is the one thing on the screen
/// that is not an object.
class _AddSlot extends StatelessWidget {
  const _AddSlot({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '추가하기',
      child: GestureDetector(
        onTap: onTap,
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
          child: const Center(
            child: Padding(
              padding: EdgeInsets.all(10),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add,
                      size: 44,
                      color: AppColors.seniorSlotInk,
                    ),
                    SizedBox(height: 10),
                    Text(
                      '추가하기',
                      style: TextStyle(
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
