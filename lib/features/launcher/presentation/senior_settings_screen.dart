import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'widgets/go_home_bar.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/clay_pad.dart';
import '../../support/presentation/support_card.dart';
import '../data/app_launcher.dart';
import 'widgets/home_app_coach.dart';

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
  static const stopUsingRow = Key('senior-settings-stop-using');
  static const stopUsingConfirm = Key('senior-settings-stop-using-confirm');
  static const stopUsingCoach = Key('senior-settings-stop-using-coach');
  static const stopUsingManual = Key('senior-settings-stop-using-manual');

  /// Shown only when the phone refuses to open its own chooser.
  static const manualKey = Key('senior-settings-home-app-manual');

  /// Shown before the phone's own chooser, which cannot be changed.
  static const homeAppCoach = Key('senior-settings-home-app-coach');
  static const supportRow = Key('senior-settings-support');
  static const manualRow = Key('senior-settings-manual');

  /// Opens the phone's home-app chooser, and says what to do by hand when the
  /// phone will not open it.
  ///
  /// Straight from the row, with no screen in between. There was one, and it
  /// said 첫 화면으로 정하기 three times — as its title, as its heading and on
  /// its only button — before doing what this does.
  static Future<void> _setHomeApp(BuildContext context, WidgetRef ref) async {
    // Said first, because the next thing on screen is Android's own chooser
    // and nothing about it can be changed — least of all that it opens with
    // the *other* app selected. Until this existed, a system dialog in
    // system language arrived with no warning and the senior was expected to
    // work out which of two rows was theirs.
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: SeniorSettingsScreen.homeAppCoach,
        backgroundColor: AppColors.seniorSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: const HomeAppCoach(direction: HomeAppDirection.take),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(
              '그만두기',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.seniorInkMuted,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              '알겠어요',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppColors.seniorPrimary,
              ),
            ),
          ),
        ],
      ),
    );
    if (go != true || !context.mounted) return;

    final opened = await ref.read(appLauncherProvider).openHomeSettings();
    // The chooser is a separate screen and the app cannot see what was
    // picked, so the answer is re-read on return rather than assumed.
    ref.invalidate(isDefaultHomeProvider);
    if (opened || !context.mounted) return;

    // Some phones refuse the in-app chooser outright, and Samsung keeps its
    // own launcher set as the default so pressing Home never offers a choice
    // either. Then this is the only way, and saying so beats a button that
    // appears to do nothing.
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: SeniorSettingsScreen.manualKey,
        backgroundColor: AppColors.seniorSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: const Text(
          '이 휴대폰에서는 여기서 바로 정할 수 없어요.\n'
          '휴대폰 설정 → 애플리케이션 → 기본 앱 선택 → 홈 화면 앱\n'
          '에서 ‘잘보이네’를 골라 주세요.',
          style: TextStyle(
            fontSize: 19,
            height: 1.6,
            color: AppColors.seniorInk,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(
              '알겠어요',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppColors.seniorPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Gives the phone back: the senior picks their old home screen again.
  ///
  /// Android gives an app **no way to stop being the home app** — there is no
  /// "clear default" an app may call on itself. The phone's own chooser is
  /// the only route, and it happens to be the same screen
  /// 첫 화면으로 정하기 opens, approached from the other side. That works
  /// without a line of new Kotlin because `openHomeSettings` only asks for
  /// the HOME *role* when this app does not hold it; holding it, the call
  /// falls through to `ACTION_HOME_SETTINGS`, which is the picker.
  ///
  /// It asks first. This changes what pressing Home does on someone's phone,
  /// and the senior is the one who has to live with the answer.
  static Future<void> _stopUsing(BuildContext context, WidgetRef ref) async {
    // **The question alone.** It carried the reassurance and the step-by-step
    // as well, which made it a wall of text at the moment a senior is only
    // deciding *whether*. What they need to answer is one sentence long, and
    // everything else belongs after they have said yes.
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: SeniorSettingsScreen.stopUsingConfirm,
        backgroundColor: AppColors.seniorSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        // **전에 쓰시던 화면**, not 원래 화면. The app already calls its own
        // home 첫 화면 (`첫 화면에서 사라집니다`), so a second word for a
        // screen is a second thing to work out — and 원래 does not say which
        // of the two it means.
        title: const Text(
          '전에 쓰시던 화면으로\n바꿀까요?',
          style: TextStyle(
            fontSize: 26,
            height: 1.35,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
            color: AppColors.seniorInk,
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
        // **Neither of these is the app's press-me colour, and `네` is the
        // quieter of the two.** Everywhere else `seniorPrimary` means *this
        // is the thing to do*; here the thing being offered is giving up the
        // home screen, and a terracotta `네` beside a grey refusal is the app
        // leaning on somebody to do it. The one that keeps things as they
        // are reads first and reads clearly; `네` is legible and no louder
        // than it has to be.
        //
        // The pair used to be `그만두기` / `돌아가기` and **both read as the
        // other one**: 그만두기 is the word in the row that opens this —
        // 잘보이네 사용하지 않기 — so it looked like the confirm, and
        // 돌아가기 in a dialog reads as *go back*, which is the cancel.
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(
              '아니요, 그대로 쓸게요',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.seniorInk,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              '네',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.seniorInkMuted,
              ),
            ),
          ),
        ],
      ),
    );
    if (go != true || !context.mounted) return;
    // **Then, and only then, what the phone is about to show.** It used to
    // be one card carrying the question and the walkthrough together, which
    // is a wall of text at the moment a senior is still deciding *whether*.
    //
    // Its cancel is `아니요` rather than the `그만두기` the other direction
    // uses: 그만두기 is the row's own word — 잘보이네 사용하지 않기 — so on
    // this card it reads as the confirm, which is the fault the question
    // card was just rewritten to remove.
    final ready = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: SeniorSettingsScreen.stopUsingCoach,
        backgroundColor: AppColors.seniorSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: const HomeAppCoach(direction: HomeAppDirection.give),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(
              '아니요',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.seniorInkMuted,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              '알겠어요',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppColors.seniorPrimary,
              ),
            ),
          ),
        ],
      ),
    );
    if (ready != true || !context.mounted) return;

    final opened = await ref.read(appLauncherProvider).openHomeSettings();
    ref.invalidate(isDefaultHomeProvider);
    if (opened || !context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: SeniorSettingsScreen.stopUsingManual,
        backgroundColor: AppColors.seniorSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: const Text(
          '이 휴대폰에서는 여기서 바로 바꿀 수 없어요.\n'
          '휴대폰 설정 → 애플리케이션 → 기본 앱 선택 → 홈 화면 앱\n'
          '에서 원래 쓰시던 앱을 골라 주세요.',
          style: TextStyle(
            fontSize: 19,
            height: 1.6,
            color: AppColors.seniorInk,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(
              '알겠어요',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppColors.seniorPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Shown only where the phone says this app is not its home app, which is
    // the case onboarding's question leaves behind when a senior says 나중에.
    final isHome = ref.watch(isDefaultHomeProvider).value;
    final offerHomeApp = isHome == false;

    return Scaffold(
      backgroundColor: AppColors.seniorBackground,
      appBar: AppBar(
        backgroundColor: AppColors.seniorBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        // The tile that opens this says 바꾸기, and a screen that then calls
        // itself 설정 is the same word landing on the same person one press
        // later.
        title: const Text(
          '바꾸기',
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
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          children: [
            // First, and above 앱 설정하기 on purpose. Somebody opens 설정
            // either to change something or because they are stuck, and the
            // second one has had nowhere to go until now.
            _Row(
              key: SeniorSettingsScreen.manualRow,
              label: '사용법',
              detail: '막히실 때 누르세요',
              icon: Icons.menu_book_rounded,
              face: AppColors.seniorButtonYellow,
              light: AppColors.seniorButtonYellowLight,
              deep: AppColors.seniorButtonYellowDeep,
              wall: AppColors.seniorButtonYellowWall,
              // The yellow cannot hold white, same rule as the 카카오톡 tile.
              ink: AppColors.seniorInk,
              onTap: () => context.push(Routes.manual),
            ),
            _Row(
              label: '앱 설정하기',
              detail: '버튼을 바꾸려면 누르세요',
              icon: Icons.grid_view_rounded,
              face: AppColors.seniorButtonPurple,
              light: AppColors.seniorButtonPurpleLight,
              deep: AppColors.seniorButtonPurpleDeep,
              wall: AppColors.seniorButtonPurpleWall,
              onTap: () => context.push(Routes.appSettings),
            ),
            _Row(
              label: '글씨 크기 조절하기',
              detail: '글씨를 키우려면 누르세요',
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
                detail: '첫 화면으로 하려면 누르세요',
                icon: Icons.home_rounded,
                face: AppColors.seniorSos,
                light: AppColors.seniorSosLight,
                deep: AppColors.seniorSosDeep,
                wall: AppColors.seniorSosWall,
                onTap: () => _setHomeApp(context, ref),
              ),
            // The other half of the row above, and it belongs beside it
            // rather than at the bottom of the list: 첫 화면으로 정하기 and
            // this are one setting seen from two sides, and exactly one of
            // them applies at a time.
            if (isHome == true)
              _Row(
                key: SeniorSettingsScreen.stopUsingRow,
                label: '잘보이네 사용하지 않기',
                // **The reassurance lives here, not in the dialog.** Its job
                // is to stop someone refusing out of fear, so it has to be
                // read *before* they decide — a card that only appears after
                // 네 cannot do that job. It also keeps the dialog to the one
                // sentence a senior is actually answering.
                detail: '버튼과 글씨 크기는 그대로 있어요',
                icon: Icons.logout_rounded,
                face: AppColors.seniorMore,
                light: AppColors.seniorMoreLight,
                deep: AppColors.seniorMoreDeep,
                wall: AppColors.seniorMoreWall,
                onTap: () => _stopUsing(context, ref),
              ),
            _Row(
              label: '가족 메시지',
              detail: '자녀분과 이야기하려면 누르세요',
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
              detail: '가족을 보시려면 누르세요',
              icon: Icons.family_restroom,
              face: AppColors.seniorButtonPink,
              light: AppColors.seniorButtonPinkLight,
              deep: AppColors.seniorButtonPinkDeep,
              wall: AppColors.seniorButtonPinkWall,
              onTap: () => context.push(Routes.familyLink),
            ),
            _Row(
              key: SeniorSettingsScreen.supportRow,
              label: '문의하기',
              detail: '번호를 받으시려면 누르세요',
              icon: Icons.support_agent_rounded,
              face: AppColors.seniorButtonGreen,
              light: AppColors.seniorButtonGreenLight,
              deep: AppColors.seniorButtonGreenDeep,
              wall: AppColors.seniorButtonGreenWall,
              onTap: () => openSupportCard(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}

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
      padding: const EdgeInsets.only(bottom: 10),
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
            height: 84,
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
