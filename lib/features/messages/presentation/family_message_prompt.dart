import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/family_message.dart';
import '../../family/application/senior_pairing_controller.dart';
import '../application/unread_notice.dart';

/// A message from the family, drawn over the whole home screen.
///
/// It covers the tiles, which is the same cost the two consent cards pay and
/// is paid here for a different reason. Those cover the home because they
/// have to be answered; this one covers it because **a senior does not go
/// looking.** A quiet mark beside a button is read by somebody who already
/// knows to look for it, and the person this app is for is the person who
/// does not. Their daughter wrote to them, and that is worth the tiles for
/// as long as it takes to press one of two buttons.
///
/// It is last in the layer. 안심 케어 and the handover are questions only the
/// parent can answer and money is already held against one of them; a message
/// waits its turn behind both.
class FamilyMessagePrompt extends ConsumerWidget {
  const FamilyMessagePrompt({super.key, required this.message});

  static const openKey = Key('family-message-open');
  static const laterKey = Key('family-message-later');

  final FamilyMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guardians = ref.watch(seniorGuardiansProvider).value ?? const [];
    final from = guardians
        .where((g) => g.guardianAccountId == message.senderGuardianId)
        .map((g) => g.displayName)
        .firstWhere((n) => n != null && n.isNotEmpty, orElse: () => null);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          // Whose it is comes first. 메시지가 왔어요 tells a senior nothing
          // they can act on; a name tells them whether to stop what they
          // were doing.
          //
          // 보냈어요, not 보내셨어요. The reader is the parent and the sender
          // is their own child, so honouring the child to them is backwards.
          textAlign: TextAlign.center,
          '${from ?? '가족'}님이 보냈어요',
          style: const TextStyle(
            fontSize: 27,
            height: 1.35,
            fontWeight: FontWeight.w900,
            color: AppColors.seniorInk,
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          decoration: BoxDecoration(
            color: AppColors.seniorCard,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            message.body?.trim().isNotEmpty == true
                ? message.body!.trim()
                : '사진을 보냈어요',
            // Three lines of the message, then the conversation. The card is
            // an invitation to read it, not the place it is read.
            textAlign: TextAlign.center,
            maxLines: 3,
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
            key: openKey,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.seniorPrimary,
            ),
            // Opening the conversation is what marks it read, so the card
            // goes on its own once they come back.
            onPressed: () => context.push(Routes.familyMessages),
            child: const Text(
              '읽어 보기',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 72,
          child: TextButton(
            key: laterKey,
            // Quieter than 읽어 보기 on purpose. What is on the other side of
            // this card is their family, and the app should not be even-handed
            // about whether they look.
            //
            // It never tells the server. 읽음 확인 means 어머니가 두 시에
            // 읽으셨다, and a card pushed aside without looking is not that.
            onPressed: () =>
                ref.read(dismissedNoticeProvider.notifier).dismiss(message.id),
            child: const Text(
              '나중에 볼게요',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w700,
                color: AppColors.seniorInkMuted,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
