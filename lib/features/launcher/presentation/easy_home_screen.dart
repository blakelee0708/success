import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/app_category.dart';
import '../../../domain/launcher_app.dart';
import '../../../domain/senior_settings.dart';
import '../application/senior_settings_controller.dart';
import 'open_home_button.dart';
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(seniorSettingsControllerProvider).value ??
        const SeniorSettings();
    final all = settings.apps.isEmpty ? defaultEasyApps : settings.apps;
    final apps = seniorGridApps(all);
    // Null when the family took the button off. Each of the four goes on its
    // own: the row it is in closes up, and if nothing is left in that row the
    // row goes too and the grid takes the height.
    final familyButton = settings.slot(AppCategory.family);
    final sosButton = settings.slot(AppCategory.sos);
    // `04_SCREEN_SPEC` gives this slot as 가족 연결 또는 자녀 이름 버튼. Talking
    // to the family moved up into [HomeStrip], which shows their newest
    // message, so what is left for the button is the connection itself —
    // still named for the job a senior has at the time.
    final connected =
        (ref.watch(seniorGuardiansProvider).value ?? const []).isNotEmpty;

    // A launcher's home screen is the root: pressing Back on it must do
    // nothing at all. Without this the route pops, and on a real phone the
    // whole home slid sideways out of view as the senior watched — which on
    // the screen the phone *sits* on reads as the app falling over, and
    // leaves them somewhere they did not ask to be.
    //
    // `canPop: false` keeps the system gesture from leaving, and the empty
    // callback keeps it from doing anything else either.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {},
      child: Scaffold(
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
                              onTap: () => openHomeButton(context, ref, app),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: HomeBody.sectionGap),
                    Row(
                      children: [
                        if (familyButton case final family?) ...[
                          Expanded(
                            child: HomePill(
                              // The senior's own words and colour, which the
                              // family can change from either phone. Before a
                              // family is attached the button is still an
                              // invitation, so the label they chose waits.
                              label: connected ? family.label : '가족 연결',
                              icon: family.category.icon,
                              light: family.lightColor,
                              face: family.baseColor,
                              deep: family.deepColor,
                              wall: family.wallColor,
                              ink: family.letteringColor,
                              // The band used to carry the newest message and
                              // open the conversation. With the band down to a
                              // clock, this button takes that back - which is
                              // what `04_SCREEN_SPEC` asked of it in the first
                              // place. Without this the conversation has no
                              // route from the senior's home at all: 가족 연결
                              // only ever reaches a 연결되었어요 notice.
                              onTap: () => context.push(
                                connected
                                    ? Routes.familyMessages
                                    : Routes.familyLink,
                              ),
                            ),
                          ),
                          const SizedBox(width: HomeBody.gutter),
                        ],
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
                            // cannot be added yet, which is a screen that
                            // exists to be passed through.
                            onTap: () => context.push(Routes.seniorSettings),
                          ),
                        ),
                      ],
                    ),
                    if (sosButton case final sos?) ...[
                      const SizedBox(height: HomeBody.sectionGap),
                      SosButton(
                        label: sos.label,
                        onTap: () => context.go(Routes.sos),
                      ),
                    ],
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
      ),
    );
  }
}
