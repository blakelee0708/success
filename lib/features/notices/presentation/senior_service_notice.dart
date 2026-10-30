import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/remote/announcement_repository.dart';
import '../application/notice_providers.dart';

/// A 공지 on the parent's home, inside `SeniorNoticeLayer`'s card.
///
/// Drawn like the family message card it sits beside - the same scrim, the
/// same type - with two differences that are the point of it:
///
/// - **The sender is the company, said in so many words.** 잘보이네에서 알려
///   드려요 rather than a title written for the guardian's screen: a senior
///   needs to know this is not their family before they read what it says.
/// - **One button, and it is final.** There is nothing to agree to or put
///   off, which is the rule 사용법 settled on (이해했어요). Closing it is kept
///   on this phone and never sent anywhere.
class SeniorServiceNotice extends ConsumerWidget {
  const SeniorServiceNotice({super.key, required this.notice});

  static const cardKey = Key('senior-service-notice');
  static const okKey = Key('senior-service-notice-ok');

  final Announcement notice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      key: cardKey,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '잘보이네에서\n알려 드려요',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 27,
            height: 1.35,
            fontWeight: FontWeight.w900,
            color: AppColors.seniorInk,
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.seniorCard,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            notice.body,
            // Written on the server by somebody who may not count lines, on a
            // card that may not scroll. Five lines and then it stops, rather
            // than pushing the button off the screen.
            textAlign: TextAlign.center,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 22,
              height: 1.55,
              fontWeight: FontWeight.w700,
              color: AppColors.seniorInk,
            ),
          ),
        ),
        const SizedBox(height: 26),
        SizedBox(
          height: 72,
          child: FilledButton(
            key: okKey,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.seniorPrimary,
            ),
            onPressed: () =>
                ref.read(dismissedNoticesProvider.notifier).dismiss(notice.id),
            child: const Text(
              '확인했어요',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }
}
