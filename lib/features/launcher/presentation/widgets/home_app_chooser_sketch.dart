import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// A drawing of the phone's own home-app chooser, with the two presses
/// numbered on the spots they happen.
///
/// Words alone were what this card had, and a senior reading
/// `목록에서 「잘보이네」를 누르고` has to hold a description in their head
/// and then match it against a dark system dialog in a typeface they have
/// not seen before. A picture of the thing removes the matching step: they
/// look for the shape, not for a sentence.
///
/// **It is a depiction, not a screenshot**, and deliberately so. A screenshot
/// would be of one handset on one Android version and would be wrong on the
/// next, while reading as a promise of exactly what will appear. This is
/// plainly a diagram - flat, no app icons, numbers that no system dialog has
/// - so it says *this shape, these two presses* rather than *this image*.
///
/// **One dialog, not two.** The card said two steps for weeks, describing a
/// Samsung flow where choosing a row raised a second dialog with 현재 버전
/// 유지 / 변경. On a Galaxy running One UI today it is a single dialog: both
/// rows and 취소 / 기본 앱으로 설정 together. That was found by looking at a
/// real phone, which is the only way this kind of claim is ever checked.
class HomeAppChooserSketch extends StatelessWidget {
  const HomeAppChooserSketch({super.key, required this.pickThisApp});

  /// Which row the first press lands on. True for 잘보이네 when taking the
  /// home screen, false for the phone's own launcher when giving it back.
  final bool pickThisApp;

  static const chooserKey = Key('home-app-chooser-sketch');

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: chooserKey,
      decoration: BoxDecoration(
        // The system dialog is dark on every phone that draws this, and the
        // card it sits on is near-white. Matching that is most of what makes
        // the drawing recognisable at a glance.
        color: const Color(0xFF2E2E33),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '기본 홈 앱으로\n설정하시겠습니까?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 9),
            _Row(
              label: '잘보이네',
              selected: pickThisApp,
              step: pickThisApp ? 1 : null,
            ),
            const SizedBox(height: 5),
            _Row(
              label: 'One UI 홈',
              selected: !pickThisApp,
              step: pickThisApp ? null : 1,
            ),
            const SizedBox(height: 8),
            const Divider(height: 1, thickness: 1, color: Color(0xFF45454B)),
            const SizedBox(height: 7),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '취소',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF9A9AA2),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      _StepBadge(2),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '기본 앱으로 설정',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.selected, this.step});

  final String label;
  final bool selected;
  final int? step;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        // The row the senior is being sent to is lifted out of the dialog's
        // flat dark, because the number alone is a small thing to find on a
        // screen somebody is seeing for the first time.
        color: step == null ? Colors.transparent : const Color(0xFF3C3C44),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          if (step case final n?) ...[
            _StepBadge(n),
            const SizedBox(width: 8),
          ] else
            const SizedBox(width: 26),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: step == null ? const Color(0xFFB9B9C2) : Colors.white,
              ),
            ),
          ),
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected
                    ? const Color(0xFF4C8DFF)
                    : const Color(0xFF6E6E78),
                width: 2,
              ),
              color: selected ? const Color(0xFF4C8DFF) : Colors.transparent,
            ),
          ),
        ],
      ),
    );
  }
}

/// The numbers the dialog does not have.
///
/// In the app's own terracotta rather than in anything Android uses, so it
/// reads as something this app added to the picture and not as a control the
/// senior should look for on the real screen.
class _StepBadge extends StatelessWidget {
  const _StepBadge(this.step);

  final int step;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.seniorPrimary,
        shape: BoxShape.circle,
      ),
      child: Text(
        '$step',
        style: const TextStyle(
          fontSize: 11,
          height: 1,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
      ),
    );
  }
}
