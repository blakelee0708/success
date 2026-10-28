import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/clay_pad.dart';
import '../../launcher/data/phone_dialer.dart';
import '../application/support_code_controller.dart';

/// The 고객센터 number. **Blank, and only the owner can fill it.**
///
/// It sits here as one named constant for the same reason `site/privacy.html`
/// leaves its six 사업자 fields as `「 」`: a number cannot be invented, and a
/// wrong one on this card sends a confused eighty-year-old to a stranger.
/// While it is blank the card shows the 문의 번호 and no 전화하기 button,
/// because a call button that dials nothing is the one thing worse than no
/// call button - the senior presses it, nothing happens, and they conclude
/// the phone is broken. The same rule 긴급 연락's 보호자 tile follows.
///
/// Filling it makes the button appear. Nothing else changes.
///
/// Filled 2026-10-28 with the owner's own number, which is what 고객센터 is
/// until there is a desk. It dials rather than calls - `tel:` resolves to
/// ACTION_DIAL - exactly as 119 and 보호자 do, because
/// `06_PERMISSION_AND_POLICY` requires the person press call themselves.
const supportPhoneNumber = '010-7522-3157';

class SupportCardKeys {
  const SupportCardKeys._();

  static const card = Key('support-card');
  static const code = Key('support-card-code');
  static const call = Key('support-card-call');
  static const close = Key('support-card-close');
}

/// Opens 문의하기.
///
/// A card rather than a screen, like the ring and the family message: the home
/// still showing around it is how a senior knows their phone has not turned
/// into something else while they were not looking.
Future<void> openSupportCard(BuildContext context, WidgetRef ref) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _SupportCard(),
  );
}

class _SupportCard extends ConsumerWidget {
  const _SupportCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = ref.watch(supportCodeProvider);

    return AlertDialog(
      key: SupportCardKeys.card,
      backgroundColor: AppColors.seniorSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(24, 26, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
      // Every line is a whole line, counted rather than wrapped: at 21px in
      // this card that is about fourteen glyphs, and the consent cards
      // document what a wrapped one costs - `지금 쓰시는 기능은` broke after
      // 기능 and left 은 alone.
      title: const Text(
        '고객센터에\n이 번호를 불러주세요',
        style: TextStyle(
          fontSize: 24,
          height: 1.4,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.5,
          color: AppColors.seniorInk,
        ),
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Code(code),
          const SizedBox(height: 18),
          if (supportPhoneNumber.isNotEmpty) ...[
            SizedBox(
              height: 78,
              child: ClayPad(
                key: SupportCardKeys.call,
                light: AppColors.seniorButtonGreenLight,
                face: AppColors.seniorButtonGreen,
                deep: AppColors.seniorButtonGreenDeep,
                wall: AppColors.seniorButtonGreenWall,
                radius: 22,
                onTap: () => ref
                    .read(phoneDialerProvider)
                    .openDialer(supportPhoneNumber),
                child: const Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.call_rounded, size: 30, color: Colors.white),
                        SizedBox(width: 12),
                        Text(
                          '전화하기',
                          style: TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
      actions: [
        TextButton(
          key: SupportCardKeys.close,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            '닫기',
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              color: AppColors.seniorInkMuted,
            ),
          ),
        ),
      ],
    );
  }
}

/// The number itself, in three digits and three.
///
/// Six digits in one run is read as one long thing and lost halfway; two
/// groups of three is how a person says a number out loud, which is the one
/// thing this number is for.
class _Code extends StatelessWidget {
  const _Code(this.code);

  final AsyncValue<String?> code;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.seniorUtilityLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.seniorUtilityDeep, width: 2),
      ),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: switch (code) {
          AsyncData(value: final String number) => Text(
            key: SupportCardKeys.code,
            _spaced(number),
            style: const TextStyle(
              fontSize: 44,
              height: 1.1,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              color: AppColors.seniorInk,
            ),
          ),
          // A failure says to try again rather than naming a cause. The last
          // time this app guessed at a cause it blamed the senior's internet
          // for a missing sign-in, which sent them to check a router.
          AsyncError() || AsyncData() => const Text(
            '번호를 받지 못했어요.\n잠시 뒤에 다시 눌러 주세요.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              height: 1.5,
              fontWeight: FontWeight.w700,
              color: AppColors.seniorInk,
            ),
          ),
          _ => const Text(
            '번호를 가져오고 있어요',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.seniorInkMuted,
            ),
          ),
        },
      ),
    );
  }

  static String _spaced(String number) => number.length == 6
      ? '${number.substring(0, 3)} ${number.substring(3)}'
      : number;
}
