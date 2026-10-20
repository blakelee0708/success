import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// The guardian app's ground: tinted blue at the crown, white by the foot.
///
/// One widget rather than a background colour because it is a gradient, and
/// because every tab has to sit on the same one or the bar underneath them
/// changes shade as you move between tabs.
class GuardianGround extends StatelessWidget {
  const GuardianGround({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(-0.1, -1),
          end: Alignment(0.1, 1),
          colors: [
            AppColors.guardianGroundTop,
            AppColors.guardianGroundMid,
            AppColors.guardianGroundEnd,
          ],
          stops: [0, 0.38, 0.72],
        ),
      ),
      child: child,
    );
  }
}

/// A card: a shallow gradient and a soft blue shadow, no border.
///
/// The bordered box it replaces was fine on its own and wrong six at a time —
/// a column of them reads as a grid, and nothing in a grid has precedence.
class GuardianCard extends StatelessWidget {
  const GuardianCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final corners = BorderRadius.circular(22);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: corners,
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.guardianCardTop,
            AppColors.guardianCardTop,
            AppColors.guardianCardEnd,
          ],
          stops: [0, 0.46, 1],
        ),
        boxShadow: const [
          BoxShadow(
            color: AppColors.guardianCardShadow,
            offset: Offset(0, 12),
            blurRadius: 26,
            spreadRadius: -16,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: corners,
        child: InkWell(
          onTap: onTap,
          borderRadius: corners,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// One of the four things a guardian can do from the home tab.
class GuardianActionCard extends StatelessWidget {
  const GuardianActionCard({
    super.key,
    required this.label,
    required this.detail,
    required this.icon,
    required this.tint,
    required this.tintInk,
    this.onTap,
  });

  final String label;

  /// What this is about *right now*, read off real data — the number of
  /// buttons actually on the parent's home screen, how long the conversation
  /// has been quiet. A card that says the same thing every day is furniture.
  final String detail;

  final IconData icon;
  final Color tint;
  final Color tintInk;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GuardianCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: tint,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, size: 23, color: tintInk),
            ),
            const SizedBox(height: 13),
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                height: 1.35,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
                color: AppColors.guardianInk,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.guardianInkFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A key-and-value line inside a [GuardianCard].
class GuardianFact extends StatelessWidget {
  const GuardianFact({
    super.key,
    required this.label,
    required this.value,
    this.first = false,
  });

  final String label;
  final String value;
  final bool first;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: first
          ? null
          : const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.guardianRule)),
            ),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.guardianInkSoft,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                color: AppColors.guardianInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The one filled button on a guardian screen.
///
/// It wears the hero's gradient rather than a flat `guardianPrimary`. A solid
/// slab of #0B5FD9 under a gradient card does not read as the same system —
/// it reads as a Material default that nobody styled, which is what it was.
class GuardianPrimaryButton extends StatelessWidget {
  const GuardianPrimaryButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;

  /// Null disables it, and it looks disabled — a gradient button that still
  /// looks pressable while it does nothing is worse than a grey one.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final corners = BorderRadius.circular(18);
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: corners,
            gradient: const LinearGradient(
              begin: Alignment(-1, -0.6),
              end: Alignment(1, 0.6),
              colors: [
                AppColors.guardianHeroStart,
                AppColors.guardianHeroMid,
                AppColors.guardianHeroEnd,
              ],
              stops: [0, 0.55, 1],
            ),
            boxShadow: enabled
                ? const [
                    BoxShadow(
                      color: AppColors.guardianHeroShadow,
                      offset: Offset(0, 10),
                      blurRadius: 22,
                      spreadRadius: -12,
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: corners,
            child: InkWell(
              onTap: onPressed,
              borderRadius: corners,
              child: SizedBox(
                height: 54,
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 20, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          label,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A screen's headline and its one line of explanation.
class GuardianHeading extends StatelessWidget {
  const GuardianHeading({super.key, required this.title, this.lede});

  /// How far down the screen a tab's headline starts.
  ///
  /// This is above and beyond the status bar, which `SafeArea` has already
  /// taken out — the headline is the first thing on the screen and it needs
  /// room to be that, not to look wedged under the clock. It was 20 on one
  /// tab and 26 on another, and both were too little.
  static const crown = 44.0;

  /// Between the headline and whatever the tab puts under it.
  static const gap = 22.0;

  final String title;
  final String? lede;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 25,
            height: 1.3,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8,
            color: AppColors.guardianInk,
          ),
        ),
        if (lede != null) ...[
          const SizedBox(height: 5),
          Text(
            lede!,
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              letterSpacing: -0.2,
              color: AppColors.guardianInkFaint,
            ),
          ),
        ],
      ],
    );
  }
}
