import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// The blue card at the top of the guardian's home tab.
///
/// It carries two numbers and nothing else, and both are things the server
/// actually holds: when the parent's phone last checked in, and how much of
/// the family's monthly message allowance is left.
///
/// What it must never carry is an assurance. The server knows a phone
/// connected; it does not know the parent is well, and this is the most
/// reassuring-looking object on the screen — which is exactly why it is the
/// one that must not reassure on no evidence. Where there is no check-in,
/// [headline] says so rather than rounding up to something comforting. Same
/// rule that took the mocked 배터리 72% off this screen.
class GuardianHeroCard extends StatelessWidget {
  const GuardianHeroCard({
    super.key,
    required this.subject,
    required this.headline,
    required this.caption,
    required this.metric,
    required this.metricCaption,
    this.online = false,
  });

  /// `어머니 · 갤럭시 A54`.
  final String subject;

  final String headline;
  final String caption;
  final String metric;
  final String metricCaption;
  final bool online;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(-1, -0.6),
            end: Alignment(1, 0.6),
            colors: [
              AppColors.guardianHeroStart,
              AppColors.guardianHeroMid,
              AppColors.guardianHeroEnd,
            ],
            stops: [0, 0.55, 1],
          ),
        ),
        child: Stack(
          children: [
            // The two translucent discs the design is built around. They are
            // the only decoration here that does not need an illustrator.
            const Positioned(
              right: -44,
              top: -46,
              child: _Disc(size: 156, opacity: 0.15),
            ),
            const Positioned(
              right: 22,
              bottom: -60,
              child: _Disc(size: 100, opacity: 0.10),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (online) ...[
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: AppColors.guardianOnline,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          subject,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // One figure at each end of the card, and each scales down
                  // on its own. Wrapping the whole row in a single FittedBox
                  // instead collapses it to its content width and leaves both
                  // figures huddled on the left — which is what shipped the
                  // first time, and is not the card that was approved.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: _Figure(value: headline, caption: caption),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: _Figure(
                            value: metric,
                            caption: metricCaption,
                            alignment: CrossAxisAlignment.end,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.value,
    required this.caption,
    this.alignment = CrossAxisAlignment.start,
  });

  final String value;
  final String caption;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 26,
            height: 1,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.9,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          caption,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _Disc extends StatelessWidget {
  const _Disc({required this.size, required this.opacity});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: opacity),
        shape: BoxShape.circle,
      ),
    );
  }
}
