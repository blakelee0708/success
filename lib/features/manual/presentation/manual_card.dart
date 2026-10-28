import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../data/manual_topics.dart';

class ManualCardKeys {
  const ManualCardKeys._();

  static const card = Key('manual-card');
  static const understood = Key('manual-card-understood');
}

/// One thing, one card, **one button**.
///
/// The button says 이해했어요 and there is nothing beside it. A pair of
/// buttons on a card that is only telling somebody something is a question
/// where there is none, and this app has already had to rewrite two pairs
/// that each read as the other one. There is nothing here to agree to, undo
/// or cancel: the card has been read or it has not.
///
/// The drawing comes first and the words follow it, because what the words
/// refer to is in the drawing. `이제 이런 창이 나와요` on the home-app coach
/// learnt the same order.
Future<void> openManualCard(BuildContext context, ManualTopic topic) {
  return showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      key: ManualCardKeys.card,
      backgroundColor: AppColors.seniorSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(22, 24, 22, 0),
      contentPadding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
      title: Text(
        topic.title,
        style: const TextStyle(
          fontSize: 25,
          height: 1.35,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.5,
          color: AppColors.seniorInk,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            topic.drawing,
            const SizedBox(height: 16),
            for (final line in topic.lines)
              if (line.isEmpty)
                const SizedBox(height: 12)
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    line,
                    style: const TextStyle(
                      fontSize: 20,
                      height: 1.45,
                      fontWeight: FontWeight.w700,
                      color: AppColors.seniorInk,
                    ),
                  ),
                ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      actions: [
        SizedBox(
          width: double.infinity,
          // The same filled terracotta 첫 화면으로 가기 wears, because it is
          // the same kind of thing: the one way off this card.
          child: FilledButton(
            key: ManualCardKeys.understood,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.seniorPrimary,
              minimumSize: const Size.fromHeight(64),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '이해했어요',
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
