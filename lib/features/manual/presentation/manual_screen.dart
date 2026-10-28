import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/clay_pad.dart';
import '../../launcher/presentation/widgets/go_home_bar.dart';
import '../data/manual_topics.dart';
import 'manual_card.dart';

/// 사용법, on the senior's own phone.
///
/// **Nothing here is swiped and nothing is scrolled.** Those are the two
/// gestures this app's readers fail at most, and a manual that needs either
/// is a manual that stops being read partway. So: seven rows that fit one
/// screen at every text size, one press each, and a card with one button.
///
/// **It is a list, not a tour.** A senior who opens this is stuck on exactly
/// one thing. Paging them through six others first is how a manual gets
/// closed.
///
/// The rows are shorter than 설정's (72px against 92) and that is what makes
/// seven fit. The label scales inside a fixed height, which is how every
/// other screen in this app survives 제일 크게 - the row does not grow with
/// the type, so the list cannot start scrolling at the largest size, which is
/// the size the reader who needs this is most likely to be using.
class ManualScreen extends StatelessWidget {
  const ManualScreen({super.key});

  static const listKey = Key('manual-list');

  static Key row(String topic) => Key('manual-row-$topic');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.seniorBackground,
      appBar: AppBar(
        backgroundColor: AppColors.seniorBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          '사용법',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.6,
            color: AppColors.seniorInk,
          ),
        ),
      ),
      bottomNavigationBar: const SafeArea(child: GoHomeBar()),
      body: SafeArea(
        child: Padding(
          key: listKey,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final topic in manualTopics)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _Row(topic: topic),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.topic});

  final ManualTopic topic;

  @override
  Widget build(BuildContext context) {
    return ClayPad(
      key: ManualScreen.row(topic.key),
      light: AppColors.seniorMoreLight,
      face: AppColors.seniorMore,
      deep: AppColors.seniorMoreDeep,
      wall: AppColors.seniorMoreWall,
      radius: 20,
      onTap: () => openManualCard(context, topic),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(
          children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  topic.title,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.chevron_right_rounded, size: 26, color: Colors.white),
          ],
        ),
      ),
    );
  }
}
