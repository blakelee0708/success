import 'package:flutter/material.dart';

/// A button drawn as a solid object: lit on top, shaded at the foot, standing
/// on a visible side wall.
///
/// Every pressable thing on the senior's home is one of these — the app tiles,
/// 가족, 더 보기, SOS and the card the clock sits on. One widget rather than
/// five copies, because the thing that makes the look hold together is that
/// they are all lit from the same direction.
///
/// Three things here are doing the work, and dropping any one of them leaves a
/// flat rectangle:
///
/// * **The wall.** A shadow with no blur, offset straight down. It reads as the
///   side of the button rather than as a shadow, which is what tells a senior
///   this is a thing to press. It is always the darkest colour of the four.
/// * **The face gradient.** Light at the top, base in the middle, deep at the
///   foot, as though lit from above.
/// * **The sheen.** CSS says this with two `inset` shadows; Flutter has no
///   inset shadow, so it is a gradient overlay painted over the face and under
///   the content — white at the crown, nothing in the middle, black at the
///   foot. Painting it *under* the content matters: as a `foregroundDecoration`
///   it would wash out the icon and the label too.
class ClayPad extends StatelessWidget {
  const ClayPad({
    super.key,
    required this.light,
    required this.face,
    required this.deep,
    required this.wall,
    required this.child,
    this.radius = 34,
    this.wallHeight = 9,
    this.sheen = 1,
    this.onTap,
  });

  /// The lit crown, the body, the shaded foot, and the side wall.
  final Color light;
  final Color face;
  final Color deep;
  final Color wall;

  final Widget child;
  final double radius;

  /// How thick the button looks. The smaller pads use a shorter wall so they
  /// do not out-shout the tiles.
  final double wallHeight;

  /// How strongly the lit crown and shaded foot are painted. Full strength is
  /// tuned for a saturated face; the near-white card the clock sits on takes a
  /// fraction of it, because at full strength its foot reads as grime rather
  /// than shade.
  final double sheen;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final corners = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: corners,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [light, face, deep],
          stops: const [0, 0.48, 1],
        ),
        boxShadow: [
          BoxShadow(
            color: wall,
            offset: Offset(0, wallHeight),
            spreadRadius: -1,
          ),
          BoxShadow(
            color: wall.withValues(alpha: 0.7),
            offset: Offset(0, wallHeight * 2.4),
            blurRadius: 28,
            spreadRadius: -14,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: corners,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.32 * sheen),
                      Colors.white.withValues(alpha: 0),
                      Colors.black.withValues(alpha: 0.18 * sheen),
                    ],
                    stops: const [0, 0.45, 1],
                  ),
                ),
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(onTap: onTap, child: Center(child: child)),
            ),
          ],
        ),
      ),
    );
  }
}
