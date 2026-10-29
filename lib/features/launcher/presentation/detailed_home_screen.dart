import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/clay_pad.dart';
import '../../../domain/app_category.dart';
import '../../../domain/launcher_app.dart';
import '../../../domain/senior_settings.dart';
import '../application/senior_settings_controller.dart';
import 'add_home_button.dart';
import 'open_home_button.dart';
import 'widgets/app_tile.dart';
import '../../family/application/senior_pairing_controller.dart';
import 'widgets/home_body.dart';
import 'widgets/senior_notice_layer.dart';
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Saved buttons rather than the constant defaults, so an edit made in
    // 설정 reaches the home screen.
    final settings =
        ref.watch(seniorSettingsControllerProvider).value ??
        const SeniorSettings();
    final all = settings.apps.isEmpty ? defaultDetailedApps : settings.apps;
    final apps = seniorGridApps(all);
    // Null when the family took it off. With both gone the row goes too and
    // the grid takes its height; with one gone the other has the width.
    final familyButton = settings.slot(AppCategory.family);
    final sosButton = settings.slot(AppCategory.sos);
    final connected =
        (ref.watch(seniorGuardiansProvider).value ?? const []).isNotEmpty;

    // One empty slot after 설정, or two where that would leave a half-finished
    // row. Padding the grid out to eight whatever the senior kept would fill
    // most of their home with 추가하기, which is a reproach rather than an
    // invitation.
    final slots = (apps.length + 1).isEven ? 2 : 1;

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
                          _SettingsTile(
                            onTap: () => context.push(Routes.seniorSettings),
                          ),
                          for (var i = 0; i < slots; i++)
                            _AddSlot(
                              // Straight to the question, not to the settings
                              // list. It used to land on 앱 설정 — a list of
                              // the buttons they already have, with 버튼
                              // 추가하기 at the bottom — so adding one from the
                              // home screen took four screens. Two of them
                              // were there to be passed through, and the step
                              // a senior gives up at is never the choosing, it
                              // is getting to the place where they can choose.
                              onTap: () => addHomeButton(context, ref),
                            ),
                        ],
                      ),
                    ),
                    if (familyButton != null || sosButton != null) ...[
                      const SizedBox(height: HomeBody.sectionGap),
                      Row(
                        children: [
                          if (sosButton case final sos?) ...[
                            Expanded(
                              flex: _sosFlex,
                              child: HomePill(
                                label: sos.label,
                                icon: sos.category.icon,
                                light: sos.lightColor,
                                face: sos.baseColor,
                                deep: sos.deepColor,
                                wall: sos.wallColor,
                                ink: sos.letteringColor,
                                onTap: () => context.go(Routes.sos),
                              ),
                            ),
                            if (familyButton != null)
                              const SizedBox(width: HomeBody.gutter),
                          ],
                          if (familyButton case final family?)
                            Expanded(
                              flex: _familyFlex,
                              child: HomePill(
                                // The senior's own words and colour, which
                                // the family can change from either phone.
                                // Before a family is attached the button is
                                // still an invitation, so the label they
                                // chose waits.
                                label: connected ? family.label : '가족 연결',
                                icon: family.category.icon,
                                light: family.lightColor,
                                face: family.baseColor,
                                deep: family.deepColor,
                                wall: family.wallColor,
                                // Amber is too light to carry white lettering.
                                ink: family.letteringColor,
                                // The band used to carry the newest message
                                // and open the conversation. With the band
                                // down to a clock, this button takes that
                                // back - which is what `04_SCREEN_SPEC` asked
                                // of it in the first place. Without it the
                                // conversation has no route from the senior's
                                // home at all: 가족 연결 only ever reaches a
                                // 연결되었어요 notice.
                                onTap: () => context.push(
                                  connected
                                      ? Routes.familyMessages
                                      : Routes.familyLink,
                                ),
                              ),
                            ),
                        ],
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
          ],
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
      // **설정 is a word this reader may not have.** It is borrowed from
      // English by way of office software, and the senior who needs this
      // screen most is the one least likely to have met it. 바꾸기 says what
      // pressing it does, in a word anybody has.
      label: '바꾸기',
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
                  '바꾸기',
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
                    Icon(Icons.add, size: 44, color: AppColors.seniorSlotInk),
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
