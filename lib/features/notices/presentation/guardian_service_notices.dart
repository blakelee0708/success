import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/remote/announcement_repository.dart';
import '../../guardian/application/guardian_pairing_controller.dart';
import '../../guardian/presentation/widgets/guardian_surfaces.dart';
import '../application/notice_providers.dart';

/// 새 버전이 나왔어요 and any running 공지, at the top of the guardian's 홈.
///
/// Above everything else on the tab and drawn only when there is something
/// in it: a card that is always there is furniture, and one that is there
/// only when the company has something to say is read.
class GuardianServiceNotices extends ConsumerWidget {
  const GuardianServiceNotices({super.key});

  static const updateKey = Key('guardian-notice-update');
  static const updateNowKey = Key('guardian-notice-update-now');
  static const updateLaterKey = Key('guardian-notice-update-later');
  static Key noticeKey(String id) => Key('guardian-notice-$id');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final update = ref.watch(updateOfferProvider).value;
    final closed = ref.watch(dismissedNoticesProvider).value;
    final running = closed == null
        ? const <Announcement>[]
        : [
            for (final a
                in ref
                        .watch(
                          runningNoticesProvider(AnnouncementAudience.guardian),
                        )
                        .value ??
                    const <Announcement>[])
              if (!closed.contains(a.id)) a,
          ];
    if (update == null && running.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (update != null)
          _NoticeCard(
            key: updateKey,
            chip: '새 버전',
            title: '새 버전이 나왔어요',
            // What does not change first, the rule every leaving dialog
            // follows: somebody who reads 업데이트 as touching their mother's
            // phone will put it off for ever.
            body: '업데이트하시면 새로 생긴 기능을 쓰실 수 있어요. 부모님 폰은 그대로입니다.',
            action: GuardianPrimaryButton(
              key: updateNowKey,
              label: '업데이트하기',
              icon: Icons.system_update_rounded,
              onPressed: () => unawaited(
                launchUrl(
                  Uri.parse(
                    'https://play.google.com/store/apps/details?id=$applicationId',
                  ),
                  mode: LaunchMode.externalApplication,
                ).catchError((Object _) => false),
              ),
            ),
            closeKey: updateLaterKey,
            closeLabel: '나중에',
            onClose: () => ref.read(updateOfferProvider.notifier).later(),
          ),
        for (final a in running)
          _NoticeCard(
            key: noticeKey(a.id),
            chip: '공지',
            title: a.title,
            body: a.body,
            closeLabel: '닫기',
            onClose: () =>
                ref.read(dismissedNoticesProvider.notifier).dismiss(a.id),
          ),
      ],
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    super.key,
    required this.chip,
    required this.title,
    required this.body,
    required this.closeLabel,
    required this.onClose,
    this.action,
    this.closeKey,
  });

  final String chip;
  final String title;
  final String body;
  final Widget? action;
  final Key? closeKey;
  final String closeLabel;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GuardianCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.guardianTintBlue,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                child: Text(
                  chip,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.guardianTintBlueInk,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
                color: AppColors.guardianInk,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              style: const TextStyle(
                fontSize: 14.5,
                height: 1.55,
                color: AppColors.guardianInkSoft,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 14),
              SizedBox(width: double.infinity, child: action),
            ],
            const SizedBox(height: 4),
            TextButton(
              key: closeKey,
              onPressed: onClose,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.guardianInkSoft,
                padding: EdgeInsets.zero,
              ),
              child: Text(
                closeLabel,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
