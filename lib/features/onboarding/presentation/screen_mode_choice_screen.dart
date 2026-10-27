import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/clay_pad.dart';
import '../../../domain/app_category.dart';
import '../../launcher/presentation/widgets/category_picker.dart';
import '../../../domain/senior_settings.dart';
import '../../launcher/application/senior_settings_controller.dart';
import '../../launcher/presentation/widgets/home_app_coach.dart';
import '../../launcher/data/app_launcher.dart';
import 'widgets/screen_mode_preview.dart';

/// Widget keys the tests drive.
class ScreenModeChoiceKeys {
  /// The home-app question, asked once at the end of onboarding.
  static const homeAppAsk = Key('screen-mode-home-app-ask');

  ScreenModeChoiceKeys._();

  static const easyPreview = Key('mode-preview-easy');
  static const detailedPreview = Key('mode-preview-detailed');
}

/// Onboarding step: pick the launcher style. The ONLY onboarding question.
///
/// Each card carries a picture of the screen it chooses. It used to describe
/// them — "큰 버튼 4개" — in two tall boxes that were mostly empty, which asked
/// the person who finds reading hardest to read their way to the answer.
class ScreenModeChoiceScreen extends ConsumerWidget {
  const ScreenModeChoiceScreen({super.key});

  Future<void> _choose(
    BuildContext context,
    WidgetRef ref,
    ScreenMode mode,
  ) async {
    await ref
        .read(seniorSettingsControllerProvider.notifier)
        .chooseScreenMode(mode);
    if (!context.mounted) return;

    // The one request `06_PERMISSION_AND_POLICY` allows during onboarding, so
    // onboarding is where it belongs. It used to wait on the home screen as a
    // card over the tiles — which at 제일 크게 left the tiles 45px tall.
    //
    // Only where the phone says it is not already the home app. A null means
    // the platform cannot answer at all (a desktop build, `flutter test`),
    // and a dialog about it there is noise.
    //
    // Read, never awaited. The screen asks the platform the moment it opens
    // (see `build`), so by the time anyone has read two options and tapped
    // one the answer is in. Awaiting it here instead strands the senior on
    // the screen they just answered whenever the channel does not reply —
    // `flutter test` is one such platform, and a phone whose launcher service
    // is wedged is another. Still loading means "cannot say", same as null.
    final isHome = ref.read(isDefaultHomeProvider).value;
    final launcher = ref.read(appLauncherProvider);
    if (isHome == false && context.mounted) {
      final yes = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          key: ScreenModeChoiceKeys.homeAppAsk,
          backgroundColor: AppColors.seniorSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text(
            '이 앱을 첫 화면으로 쓸까요?',
            style: TextStyle(
              fontSize: 24,
              height: 1.4,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              color: AppColors.seniorInk,
            ),
          ),
          content: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '한 번만 정해두면, 홈 버튼을 누를 때마다\n이 화면이 나옵니다.',
                style: TextStyle(
                  fontSize: 18,
                  height: 1.55,
                  color: AppColors.seniorInkMuted,
                ),
              ),
              SizedBox(height: 18),
              Divider(height: 1, color: AppColors.seniorHairline),
              SizedBox(height: 14),
              // Pressing 첫 화면으로 정하기 opens Android's own chooser, and
              // none of it can be changed — including that it starts with
              // the other app selected. This is the first time most seniors
              // meet it, so it is the most important of the three places to
              // say what is coming.
              HomeAppCoach(direction: HomeAppDirection.take),
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text(
                '나중에',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: AppColors.seniorInkMuted,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text(
                '첫 화면으로 정하기',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: AppColors.seniorPrimary,
                ),
              ),
            ),
          ],
        ),
      );
      if (yes == true) {
        await launcher.openHomeSettings();
        ref.invalidate(isDefaultHomeProvider);
      }
    }
    if (!context.mounted) return;
    context.go(mode == ScreenMode.easy ? Routes.easyHome : Routes.detailedHome);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Asked here so the answer is ready when a choice is made. _choose reads
    // it rather than waiting for it.
    ref.watch(isDefaultHomeProvider);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 28, 18, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '화면을 골라주세요',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 30,
                  height: 1.25,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.6,
                  color: AppColors.seniorInk,
                ),
              ),
              const SizedBox(height: 7),
              const Text(
                '나중에 언제든 바꿀 수 있어요',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.seniorInkMuted,
                ),
              ),
              const SizedBox(height: 22),
              Expanded(
                child: _ModeCard(
                  title: '정말 쉬운 화면',
                  subtitle: '큰 버튼 4개만.\n가장 간단해요',
                  preview: const ScreenModePreview(
                    key: ScreenModeChoiceKeys.easyPreview,
                    tiles: 4,
                    categories: [
                      AppCategory.phone,
                      AppCategory.message,
                      AppCategory.gallery,
                      AppCategory.youtube,
                    ],
                    hasTabBar: false,
                  ),
                  onTap: () => _choose(context, ref, ScreenMode.easy),
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: _ModeCard(
                  title: '자세한 화면',
                  subtitle: '앱 6개에 설정까지.\n조금 더 쓸 수 있어요',
                  preview: ScreenModePreview(
                    key: ScreenModeChoiceKeys.detailedPreview,
                    tiles: 6,
                    // The preview shows app tiles, so it shows the kinds that
                    // can be one. 가족, 소리 and 인터넷 have places of their
                    // own and are not in the grid at all.
                    categories: addableCategories,
                    hasTabBar: true,
                  ),
                  onTap: () => _choose(context, ref, ScreenMode.detailed),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.title,
    required this.subtitle,
    required this.preview,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final Widget preview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: title,
      child: ClayPad(
        light: AppColors.seniorCardLight,
        face: AppColors.seniorCard,
        deep: AppColors.seniorCardDeep,
        wall: AppColors.seniorCardWall,
        radius: 30,
        wallHeight: 7,
        sheen: 0.3,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              // Fixed, so the words get the rest. Left to its own devices the
              // thumbnail took most of the card and the subtitle broke in the
              // middle of a word.
              SizedBox(width: 104, child: preview),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4,
                          color: AppColors.seniorInk,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF6E6A64),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
