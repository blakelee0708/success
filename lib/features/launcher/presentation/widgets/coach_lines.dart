import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// The body of a card that is said *before* a screen we do not own appears.
///
/// Shared by the home-app chooser and the internet panel because they are one
/// situation: a system screen, in the system's words, arriving over an app a
/// senior was told would be simple. The only thing that stops it reading as a
/// fault is knowing it is coming and what to press.
///
/// **Every line is a whole line, and a test measures it rather than counting.**
/// `목록에서 「One UI 홈」을 누르고` is seventeen characters, the length the
/// consent cards settled on, and it still ran 14px past its box - 「」 are full
/// width and latin letters are not, so a glyph count and a width answer
/// different questions. An empty string is a gap, not a line.
class CoachLines extends StatelessWidget {
  const CoachLines({
    super.key,
    required this.lines,
    required this.footnote,
    this.figure,
    this.figureAfterLine,
  });

  final List<String> lines;

  /// A drawing placed among the lines, for the one of these two screens that
  /// has something to show. The home-app coach draws the chooser; the
  /// internet one has nothing to draw, because the panel it precedes is a
  /// sheet of toggles with no single thing to press.
  final Widget? figure;

  /// Which line the figure follows. The home-app card puts it straight after
  /// 이제 이런 창이 나와요, which is where 이런 points.
  final int? figureAfterLine;

  /// The quiet last line, for the phones that word it differently. It is
  /// small and muted on purpose: leading with an exception most readers will
  /// never meet is wrong-footing.
  final String footnote;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, line) in lines.indexed) ...[
          if (line.isEmpty)
            const SizedBox(height: 14)
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                line,
                style: const TextStyle(
                  fontSize: 19,
                  height: 1.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.seniorInk,
                ),
              ),
            ),
          if (figure != null && i == figureAfterLine)
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: figure,
            ),
        ],
        const SizedBox(height: 14),
        Text(
          footnote,
          style: const TextStyle(
            fontSize: 16,
            height: 1.45,
            fontWeight: FontWeight.w500,
            color: AppColors.seniorInkMuted,
          ),
        ),
      ],
    );
  }
}
