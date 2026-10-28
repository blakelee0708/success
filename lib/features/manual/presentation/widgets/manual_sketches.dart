import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// The drawings on 사용법's cards.
///
/// **They are of this app's own screens, not generic diagrams.** A senior
/// reading `설정에서 앱 설정하기를 누르세요` has to hold a sentence in their
/// head and then match it against a screen they have not looked at yet. A
/// picture of the real thing removes the matching step: they look for the
/// shape and the colour they are about to see.
///
/// Same parts the real screens are made of - the terracotta, the amber, the
/// sand, the rounded clay - at a smaller size. They are **depictions**: flat,
/// no shadows, no live state, and carrying ① ② badges no screen in the app
/// has, so it reads as *this shape, this press* rather than as a screenshot
/// that has to stay true forever.
class ManualPill extends StatelessWidget {
  const ManualPill({
    super.key,
    required this.label,
    required this.face,
    this.ink = Colors.white,
    this.icon,
    this.height = 44,
    this.step,
    this.hollow = false,
  });

  final String label;
  final Color face;
  final Color ink;
  final IconData? icon;
  final double height;

  /// The number the sentence beside the drawing refers to.
  final int? step;

  /// For 버튼 추가하기 and the empty slot, which are outlines on the real
  /// screens too.
  final bool hollow;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Row(
        children: [
          if (step case final n?) ...[ManualBadge(n), const SizedBox(width: 6)],
          Expanded(
            child: Container(
              height: height,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: hollow ? Colors.transparent : face,
                borderRadius: BorderRadius.circular(12),
                border: hollow
                    ? Border.all(color: AppColors.seniorHairline, width: 2)
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 17, color: hollow ? AppColors.seniorInkMuted : ink),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: hollow ? AppColors.seniorInkMuted : ink,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row of 앱 설정, as it really is: the button, then the three words.
class ManualSettingRow extends StatelessWidget {
  const ManualSettingRow({
    super.key,
    required this.label,
    required this.face,
    this.nameStep,
    this.colourStep,
    this.deleteStep,
  });

  final String label;
  final Color face;
  final int? nameStep;
  final int? colourStep;
  final int? deleteStep;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: face,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.seniorInk,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _Word(label: '이름', step: nameStep),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _Word(label: '색깔', step: colourStep, swatch: face),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _Word(
                label: '지우기',
                step: deleteStep,
                ink: AppColors.seniorSos,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Word extends StatelessWidget {
  const _Word({
    required this.label,
    this.step,
    this.swatch,
    this.ink = AppColors.seniorInk,
  });

  final String label;
  final int? step;
  final Color? swatch;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          // The one being pointed at is ringed, because a badge alone is a
          // small thing to find on a drawing somebody is seeing once.
          color: step == null
              ? AppColors.seniorHairline
              : AppColors.seniorPrimary,
          width: step == null ? 1.4 : 2.4,
        ),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (step case final n?) ...[ManualBadge(n), const SizedBox(width: 5)],
            if (swatch case final colour?) ...[
              Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ①, ②. In the app's own terracotta rather than anything Android uses, so
/// it reads as something the drawing added and not as a control to look for.
class ManualBadge extends StatelessWidget {
  const ManualBadge(this.step, {super.key, this.size = 19});

  final int step;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.seniorPrimary,
        shape: BoxShape.circle,
      ),
      child: Text(
        '$step',
        style: TextStyle(
          fontSize: size * 0.62,
          height: 1,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// The arrow that joins a number to the thing it means.
class ManualArrow extends StatelessWidget {
  const ManualArrow({super.key, this.down = true});

  final bool down;

  @override
  Widget build(BuildContext context) {
    return Icon(
      down ? Icons.south_rounded : Icons.east_rounded,
      size: 22,
      color: AppColors.seniorPrimary,
    );
  }
}

/// A drawing's frame, so it reads as *a phone screen* rather than as loose
/// shapes on the card.
class ManualFrame extends StatelessWidget {
  const ManualFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.seniorSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.seniorHairline, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [child],
      ),
    );
  }
}
