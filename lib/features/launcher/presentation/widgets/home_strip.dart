import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/clock.dart';
import '../../../../core/format/korean_clock.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/clay_pad.dart';
import '../../../../domain/family_message.dart';
import '../../../messages/application/message_controller.dart';
import '../../../family/application/senior_pairing_controller.dart';

/// The band across the top of 정말 쉬운 화면: the time, and the family.
///
/// It exists because the home screen had 211px of nothing at the bottom and
/// square tiles could not fill it. Rather than stretch the tiles into tall
/// rectangles, the slack became one wide thing worth looking at.
///
/// Two jobs, in the order a senior needs them. The clock answers the question
/// they picked the phone up to ask. Underneath it is whoever is looking after
/// them: their child's newest message when there is one, and the way to
/// connect a family when there is not — the same slot `04_SCREEN_SPEC` gives
/// to 가족 연결 또는 자녀 이름.
class HomeStrip extends ConsumerWidget {
  const HomeStrip({super.key});

  static const stripKey = Key('home-strip');

  /// Shown while nobody is attached to this phone.
  static const connectKey = Key('home-strip-connect');

  /// Shown once somebody is.
  static const messageKey = Key('home-strip-message');

  /// The newest thing the family said, which is not the same as the newest
  /// message: a senior who has just replied should not be shown their own
  /// words back as though they were news.
  static FamilyMessage? _latestFromFamily(List<FamilyMessage> all) {
    for (final message in all.reversed) {
      if (!message.isFromSenior && (message.body?.isNotEmpty ?? false)) {
        return message;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(nowProvider)();
    final guardians = ref.watch(seniorGuardiansProvider).value ?? const [];
    final connected = guardians.isNotEmpty;

    return ClayPad(
      light: AppColors.seniorCardLight,
      face: AppColors.seniorCard,
      deep: AppColors.seniorCardDeep,
      wall: AppColors.seniorCardWall,
      radius: 30,
      sheen: 0.3,
      onTap: () =>
          context.push(connected ? Routes.familyMessages : Routes.familyLink),
      child: Padding(
        key: stripKey,
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 16),
        // Scales down rather than overflowing, the same rule the tiles and
        // SOS follow. The band is the part that gives up height when the
        // 첫 화면 card appears or the text size goes to 아주 크게, so it is
        // the part that has to survive being squeezed.
        child: LayoutBuilder(
          builder: (context, box) => FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: box.maxWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The date sits above the clock rather than beside it: side by
                  // side, the two ran to 328px inside a 310px card and the date
                  // was pushed out of its own box.
                  Text(
                    koreanDate(now),
                    style: const TextStyle(
                      fontSize: 20,
                      height: 1.3,
                      fontWeight: FontWeight.w500,
                      color: AppColors.seniorInkMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    koreanTime(now),
                    // One line, always. `오후 7:14` broke after 오후 and came
                    // out two lines tall, and because the band is wrapped in
                    // a `FittedBox` the whole thing was then scaled to 0.79
                    // to fit — so the clock rendered at 43px while the code
                    // said 54 and nothing overflowed to say so. Raising the
                    // sizes could not help: every increase was absorbed by
                    // the same scaling. The third time this wrapper has
                    // hidden a fault in this file.
                    maxLines: 1,
                    softWrap: false,
                    style: const TextStyle(
                      fontSize: 60,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.5,
                      color: AppColors.seniorInk,
                    ),
                  ),
                  const SizedBox(height: 11),
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: AppColors.seniorHairline,
                  ),
                  const SizedBox(height: 11),
                  if (connected)
                    _Family(name: guardians.first.displayName ?? '가족')
                  else
                    const _Connect(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Connect extends StatelessWidget {
  const _Connect();

  @override
  Widget build(BuildContext context) {
    return Row(
      key: HomeStrip.connectKey,
      children: [
        const _Avatar(initial: null),
        const SizedBox(width: 14),
        const Expanded(
          child: Text(
            '가족을 연결해 보세요',
            // Wrapped too, for the same reason and with the same cost. Its
            // sibling in `_Family` already had this; this one was missed.
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.seniorInk,
            ),
          ),
        ),
        Icon(Icons.chevron_right, size: 26, color: AppColors.seniorInkMuted),
      ],
    );
  }
}

class _Family extends ConsumerWidget {
  const _Family({required this.name});

  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = ref.watch(conversationProvider).value ?? const [];
    final latest = HomeStrip._latestFromFamily(messages);

    return Row(
      key: HomeStrip.messageKey,
      children: [
        _Avatar(initial: name.characters.firstOrNull),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: AppColors.seniorInk,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                latest?.body ?? '이야기를 시작해 보세요',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF5E5A54),
                ),
              ),
            ],
          ),
        ),
        if (latest != null) ...[
          const SizedBox(width: 12),
          Container(
            width: 13,
            height: 13,
            decoration: const BoxDecoration(
              color: AppColors.seniorButtonRed,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ],
    );
  }
}

/// A small clay disc, so the face in the card is made of the same material as
/// everything else on the screen.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.initial});

  final String? initial;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 50,
      height: 50,
      child: ClayPad(
        light: AppColors.seniorMoreLight,
        face: AppColors.seniorMore,
        deep: AppColors.seniorMoreDeep,
        wall: AppColors.seniorMoreWall,
        radius: 25,
        wallHeight: 5,
        child: initial == null
            ? const Icon(Icons.group_outlined, size: 26, color: Colors.white)
            : Text(
                initial!,
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }
}
