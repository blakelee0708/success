import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/app_launcher.dart';

/// Offers to make this app the phone's home screen, from 설정.
///
/// `06_PERMISSION_AND_POLICY` allows exactly this one request during
/// onboarding, and that is where it is asked now — right after the senior
/// picks a screen. This is the way back for the ones who said 나중에, and for
/// the phones that refuse the chooser outright.
///
/// It used to sit on the home screen itself, above the tiles and not
/// dismissible. At 제일 크게 it asked for more height than the phone had, and
/// because every tile is a `FittedBox` nothing overflowed: the tiles shrank
/// to 12px instead. Asking twice was not worth a home screen nobody can read.
///
/// Renders nothing when the platform cannot answer, or when this app is
/// already the home app.
class DefaultHomePrompt extends ConsumerStatefulWidget {
  const DefaultHomePrompt({super.key});

  static const promptKey = Key('default-home-prompt');
  static const buttonKey = Key('default-home-prompt-button');

  /// Shown only after the chooser refused to open.
  static const manualKey = Key('default-home-prompt-manual');

  @override
  ConsumerState<DefaultHomePrompt> createState() => _DefaultHomePromptState();
}

class _DefaultHomePromptState extends ConsumerState<DefaultHomePrompt> {
  bool _chooserRefused = false;

  Future<void> _ask() async {
    final opened = await ref.read(appLauncherProvider).openHomeSettings();
    if (!mounted) return;
    setState(() => _chooserRefused = !opened);
    // The chooser is a separate screen and the app cannot see what was picked,
    // so the answer is re-read on return rather than assumed.
    ref.invalidate(isDefaultHomeProvider);
  }

  @override
  Widget build(BuildContext context) {
    final isDefault = ref.watch(isDefaultHomeProvider);
    if (isDefault.value != false) return const SizedBox.shrink();

    return Padding(
      key: DefaultHomePrompt.promptKey,
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '이 화면을 첫 화면으로 만들어 두세요',
            style: TextStyle(
              fontSize: 21,
              height: 1.4,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              color: AppColors.seniorInk,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '한 번만 정해두면, 홈 버튼을 누를 때마다\n이 화면이 나옵니다',
            style: TextStyle(
              fontSize: 17,
              height: 1.5,
              color: AppColors.seniorInkMuted,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 72,
            child: FilledButton(
              key: DefaultHomePrompt.buttonKey,
              onPressed: _ask,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.seniorPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26),
                ),
              ),
              child: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '첫 화면으로 정하기',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
            ),
          ),
          // Some phones refuse the in-app chooser outright, and Samsung keeps
          // its own launcher set as the default so pressing Home never offers
          // a choice either. Then this is the only way, and saying so beats a
          // button that appears to do nothing.
          if (_chooserRefused) ...[
            const SizedBox(height: 10),
            const Text(
              '이 휴대폰에서는 여기서 바로 정할 수 없어요.\n'
              '휴대폰 설정 → 애플리케이션 → 기본 앱 선택 → 홈 화면 앱\n'
              '에서 ‘잘보이네’를 골라 주세요.',
              key: DefaultHomePrompt.manualKey,
              style: TextStyle(
                fontSize: 16,
                height: 1.5,
                color: AppColors.seniorInkMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
