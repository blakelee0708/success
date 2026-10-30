import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../launcher/presentation/widgets/go_home_bar.dart';
import '../data/family_visibility.dart';

/// What the senior's family can see, on the senior's own phone.
///
/// The consent card asks once and goes away. After that a senior who wanted
/// to know what their children can see had nowhere to look, which is the gap
/// Play's rules about collecting an adult's data are aimed at and, separately,
/// a fair question for somebody whose home screen this is.
///
/// **It is not a second consent screen.** The card asks *may we turn this
/// on* and names only what is paid and built - listing the free readings
/// there would tell the senior that 아니요 stops something it does not stop.
/// This answers *what do they see*, so it names everything, and there is
/// nothing on it to press.
///
/// **보지 못합니다 is gone**, on the owner's call. It was five true lines -
/// 어디 계신지, 통화 내용과 통화 기록, 연락처, 어떤 앱을 쓰시는지, 사진첩 -
/// and the argument against them is that a list of things that are **not**
/// happening plants worries in a reader who did not arrive with them. This
/// reader is on their own phone, not reading a policy; the page that owes
/// the complete answer is `site/privacy.html`, which a reviewer reads.
class FamilyVisibilityScreen extends StatelessWidget {
  const FamilyVisibilityScreen({super.key});

  static const listKey = Key('family-visibility-list');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.seniorBackground,
      appBar: AppBar(
        backgroundColor: AppColors.seniorBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          '자녀가 보는 것',
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
        child: ListView(
          key: listKey,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            for (final sees in FamilySees.values) ...[
              _Section(sees: sees),
              const SizedBox(height: 22),
            ],
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.sees});

  final FamilySees sees;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          familySeesTitle(sees),
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
            color: AppColors.seniorInk,
          ),
        ),
        const SizedBox(height: 12),
        for (final item in familySees(sees))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    size: 22,
                    color: AppColors.seniorInk,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.line,
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
        if (familySeesNote(sees) case final note?)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              note,
              style: const TextStyle(
                fontSize: 18,
                height: 1.5,
                color: AppColors.seniorInkMuted,
              ),
            ),
          ),
      ],
    );
  }
}
