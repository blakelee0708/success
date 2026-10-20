import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/clay_pad.dart';
import '../../../domain/app_category.dart';
import '../../../domain/senior_settings.dart';
import '../../launcher/application/senior_settings_controller.dart';
import 'widgets/screen_mode_preview.dart';

/// Widget keys the tests drive.
class ScreenModeChoiceKeys {
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
    context.go(mode == ScreenMode.easy ? Routes.easyHome : Routes.detailedHome);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                  preview: const ScreenModePreview(
                    key: ScreenModeChoiceKeys.detailedPreview,
                    tiles: 6,
                    categories: AppCategory.values,
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
