import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/support_contact.dart';

import '../../../core/theme/app_colors.dart';
import '../data/care_capabilities.dart';
import '../../../data/remote/senior_link_repository.dart';
import '../../../domain/subscription.dart';
import '../../guardian/application/guardian_home_apps_controller.dart';
import '../application/care_controller.dart';
import '../../guardian/presentation/widgets/guardian_surfaces.dart';

/// Widget keys the tests drive.
class GuardianCareKeys {
  GuardianCareKeys._();

  static const buyCare = Key('care-buy');
  static const waiting = Key('care-waiting');
  static const refused = Key('care-refused');
  static const active = Key('care-active');
  static const message = Key('care-message');
  static const alerts = Key('care-alerts');
  static const cancel = Key('care-cancel');
  static const cancelConfirm = Key('care-cancel-confirm');
  static const cancelling = Key('care-cancelling');
  static const contact = Key('care-contact');
}

/// 돌봄 — 안심 케어 and the family plan.
///
/// The whole shape of this screen comes from one rule in
/// `06_PERMISSION_AND_POLICY`: paying does not turn 안심 케어 on. The senior
/// agrees afterwards, on their own phone, and a refusal refunds. So there is a
/// state between paying and working, and it says so rather than showing a
/// half-on feature.
class GuardianCareTab extends ConsumerWidget {
  const GuardianCareTab({super.key});

  /// Wording follows `06_PERMISSION_AND_POLICY`: location is a periodic check
  /// rather than tracking, and the call alert is about numbers absent from the
  /// contact list, not about anything heard during the call.
  /// Each carries its own mark. They wore the same clock once, which turned a
  /// list of different capabilities into a wall of identical rows.
  ///
  /// 모르는 번호 통화 알림 was a fourth and is gone. Play grants `READ_CALL_LOG`
  /// to default phone and messaging apps, and this is a launcher — the
  /// permission was unlikely to be granted and the feature would have been
  /// sold before anyone found out.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(selectedSeniorProfileProvider);
    final care = ref.watch(careStateProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, GuardianHeading.crown, 20, 32),
      children: [
        const GuardianHeading(title: '안심 케어'),
        const SizedBox(height: GuardianHeading.gap),
        if (profile == null)
          const _Card(
            child: Text(
              '부모님을 먼저 연결해 주세요. 안심 케어는 부모님 한 분씩 신청합니다.',
              style: TextStyle(fontSize: 15, height: 1.5),
            ),
          )
        else
          _Card(
            child: _CareState(seniorName: profile.displayName, care: care),
          ),
        const _Card(child: _Features()),
        if (profile != null) _Card(child: _Alerts(seniorProfileId: profile.id)),
        // **연결 관리 was here and moved to 홈.** Nothing in it was about
        // 안심 케어 - leaving a parent, reconnecting a phone, a name, a number, signing out - and a guardian who has not
        // bought the tier has no reason to open this tab, which left them
        // with no route to any of it.
        //
        // What belongs here instead is the two things this tab owes: a way
        // out of what it sells, and somewhere to write.
        const _Bottom(),
      ],
    );
  }
}

class _CareState extends ConsumerWidget {
  const _CareState({required this.seniorName, required this.care});

  final String seniorName;
  final AsyncValue<CareState> care;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (care) {
      AsyncData(:final value) => switch (value.stage) {
        CareStage.notBought => _Buy(seniorName: seniorName),
        // The honest middle state: money has been taken and nothing is on.
        CareStage.waitingOnSenior => _Notice(
          noticeKey: GuardianCareKeys.waiting,
          title: '$seniorName님의 허락을 기다리고 있어요',
          detail:
              '부모님 폰에 동의 화면이 떴습니다. 허락하시면 바로 켜집니다.\n'
              '아직은 아무 기능도 동작하지 않아요.',
        ),
        CareStage.refused => _Notice(
          noticeKey: GuardianCareKeys.refused,
          title: '$seniorName님이 원하지 않으셨어요',
          // A refusal is final and refunded. It is not a retry prompt.
          detail:
              '결제는 환불 처리되었습니다. 무료 기능은 그대로 쓰실 수 있어요.\n'
              '부모님과 이야기해 보신 뒤에 다시 신청하실 수 있습니다.',
          child: _Buy(seniorName: seniorName, label: '다시 신청하기'),
        ),
        CareStage.active => _Notice(
          noticeKey: GuardianCareKeys.active,
          title: '안심 케어가 켜져 있어요',
          detail: '$seniorName님이 허락하셨습니다.',
        ),
        // 해지했고, 남은 기간은 그대로 쓴다. Said as what is still true
        // first: a guardian who reads 해지되었습니다 and then finds the
        // readings still working thinks something went wrong.
        CareStage.cancelling => _Notice(
          noticeKey: GuardianCareKeys.cancelling,
          title: '남은 기간까지 쓰실 수 있어요',
          detail: switch (value.subscription?.currentPeriodEnd) {
            final end? =>
              '${end.year}년 ${end.month}월 ${end.day}일까지 그대로 쓰실 수 있어요.\n'
                  '그 뒤로는 다음 결제가 없습니다.',
            // No Billing yet, so nothing knows the date. Saying 남은 기간
            // without one is true; inventing a day is not.
            null =>
              '다음 결제는 없습니다. 남은 기간까지는 지금처럼 쓰실 수 있어요.\n'
                  '부모님 폰은 그대로입니다.',
          },
        ),
      },
      AsyncError() => const Text('안심 케어 상태를 읽지 못했어요.'),
      _ => const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: CircularProgressIndicator(),
        ),
      ),
    };
  }
}

class _Buy extends ConsumerStatefulWidget {
  const _Buy({required this.seniorName, this.label = '안심 케어 신청하기'});

  final String seniorName;
  final String label;

  @override
  ConsumerState<_Buy> createState() => _BuyState();
}

class _BuyState extends ConsumerState<_Buy> {
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label == '안심 케어 신청하기') ...[
          const Text(
            '월 5,900원',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            '언제든 해지할 수 있습니다. '
            '${widget.seniorName}님이 허락하셔야 켜지고, '
            '원하지 않으시면 결제는 환불됩니다.',
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 12),
        ],
        if (_error case final message?) ...[
          Text(
            message,
            key: GuardianCareKeys.message,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 10),
        ],
        GuardianPrimaryButton(
          key: GuardianCareKeys.buyCare,
          onPressed: _busy ? null : _buy,
          icon: Icons.favorite_rounded,
          label: _busy ? '신청하는 중이에요' : widget.label,
        ),
      ],
    );
  }

  Future<void> _buy() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(careControllerProvider.notifier).buyCare();
    } on SeniorLinkException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object {
      if (mounted) setState(() => _error = '신청하지 못했어요. 잠시 후 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.noticeKey,
    required this.title,
    required this.detail,
    this.child,
  });

  final Key noticeKey;
  final String title;
  final String detail;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: noticeKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: AppColors.guardianInk,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          detail,
          style: const TextStyle(
            fontSize: 14,
            height: 1.55,
            color: AppColors.guardianInkSoft,
          ),
        ),
        if (child case final it?) ...[const SizedBox(height: 14), it],
      ],
    );
  }
}

class _Features extends StatelessWidget {
  const _Features();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '안심 케어로 할 수 있는 일',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: AppColors.guardianInk,
          ),
        ),
        const SizedBox(height: 14),
        for (final capability in builtCareCapabilities)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _Feature(capability: capability),
          ),
        // **Shown only when something is actually below it**, which is new
        // since the list emptied. 소리 울리기 was the last `planned`
        // capability and it is out of the product, so an unguarded banner
        // would warn a guardian about nothing at all - which reads either as
        // the app being broken or as something being hidden from them, on
        // the screen that takes their money.
        if (plannedCareCapabilities.isNotEmpty) ...[
          const SizedBox(height: 2),
          // Said once, plainly, and given enough weight to be read: nothing
          // below this is built, and a paid screen that looks ready is a
          // promise. It was a 13px grey line, the least visible thing on the
          // screen it is most important to be honest on.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.guardianTintAmber,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.schedule_rounded,
                  size: 17,
                  color: AppColors.guardianTintAmberInk,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '아래 기능은 아직 준비 중입니다. 신청하셔도 지금은 동작하지 않아요.',
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.guardianTintAmberInk,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          for (final capability in plannedCareCapabilities)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _Feature(capability: capability),
            ),
        ],
      ],
    );
  }
}

/// One capability: a tinted mark, a name and what it does.
///
/// A mark rather than a number — numbered badges said these were steps, and
/// nobody does them in order. All four wore the same clock once, which turned
/// four different things into a wall of identical rows.
class _Feature extends StatelessWidget {
  const _Feature({required this.capability});

  final CareCapability capability;

  @override
  Widget build(BuildContext context) {
    final CareCapability(:icon, :tint, :tintInk, :title, :detail) = capability;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: tint,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 19, color: tintInk),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: AppColors.guardianInk,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                detail,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.5,
                  color: AppColors.guardianInkFaint,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Alerts extends ConsumerWidget {
  const _Alerts({required this.seniorProfileId});

  final String seniorProfileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(careAlertsProvider).value ?? const <CareAlert>[];
    if (alerts.isEmpty) return const SizedBox.shrink();

    return Column(
      key: GuardianCareKeys.alerts,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '알림',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: AppColors.guardianInk,
          ),
        ),
        const SizedBox(height: 10),
        for (final alert in alerts)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (alert.body case final body?)
                  Text(body, style: const TextStyle(fontSize: 14, height: 1.4)),
              ],
            ),
          ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GuardianCard(child: child),
    );
  }
}

/// The two things this tab owes, at the bottom of it.
///
/// **Text rows, not filled buttons.** Nobody opens this app in order to
/// cancel or to complain, so neither is given the weight of something to do -
/// the same reason 로그아웃 is a text button. They have to be *findable*
/// rather than prominent, which is what the tab promising 언제든 해지할 수
/// 있습니다 requires: a promise with no row under it anywhere is the app
/// saying something it has not built.
class _Bottom extends ConsumerWidget {
  const _Bottom();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(selectedSeniorProfileProvider);
    final stage = ref.watch(careStateProvider).value?.stage;
    // Only where there is something to cancel. 해지하기 on a tab nobody has
    // bought anything from is a button that can only produce an error.
    final canCancel =
        profile != null &&
        (stage == CareStage.active || stage == CareStage.waitingOnSenior);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        const Divider(color: AppColors.guardianRule, height: 24),
        if (canCancel)
          _BottomRow(
            rowKey: GuardianCareKeys.cancel,
            icon: Icons.highlight_off_rounded,
            label: '안심 케어 해지하기',
            onTap: () => _confirmCancel(
              context,
              ref,
              profile.displayName,
              started: stage == CareStage.active,
            ),
          ),
        // 이메일 rather than a number, because the reader is different. The
        // senior's 문의하기 dials; an adult with an ordinary phone writes,
        // and a refund or a cancellation is not a phone call.
        _BottomRow(
          rowKey: GuardianCareKeys.contact,
          icon: Icons.mail_outline_rounded,
          label: '문의하기',
          detail: supportEmail,
          onTap: () => _writeTo(context),
        ),
      ],
    );
  }

  Future<void> _confirmCancel(
    BuildContext context,
    WidgetRef ref,
    String seniorName, {
    required bool started,
  }) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: GuardianCareKeys.cancelConfirm,
        title: const Text('안심 케어를 해지할까요?'),
        // What is **not** lost comes first, the same rule 로그아웃 and
        // 연결 끊기 both follow. A guardian who reads 해지 as 연결 끊기 will
        // not press it, and one who presses it expecting that is worse off.
        //
        // **Two different outcomes.** A running month is kept to its end; one
        // the parent never agreed to has delivered nothing, so the server
        // refunds it and withdraws the question from their phone.
        content: Text(
          '${started ? '남은 기간까지는 지금처럼 쓰실 수 있어요. 다음 결제만 없습니다.' : '아직 부모님이 허락하지 않으셔서 쓰신 기간이 없어요. 결제한 금액은 돌려드립니다.'}\n'
          '$seniorName님 폰은 그대로입니다. 연결도, 홈 화면도, 메시지도 그대로예요.\n'
          '언제든 다시 신청하실 수 있어요.',
          style: const TextStyle(fontSize: 14.5, height: 1.55),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('아니요, 그대로 쓸게요'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('해지하기'),
          ),
        ],
      ),
    );
    if (go != true) return;
    try {
      await ref.read(careControllerProvider.notifier).cancelCare();
    } on SeniorLinkException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Opens the mail app with the address filled in.
  ///
  /// Not awaited and never reported as sent: the app hands the message to
  /// another app and cannot see what happens there, the same rule the install
  /// SMS and every dialled number follow.
  Future<void> _writeTo(BuildContext context) async {
    final uri = Uri(scheme: 'mailto', path: supportEmail);
    try {
      final opened = await launchUrl(uri);
      if (opened || !context.mounted) return;
    } on Object {
      if (!context.mounted) return;
    }
    // A phone with no mail app set up. The address is on the row either way,
    // so this puts it where it can be copied rather than reporting a fault.
    await Clipboard.setData(const ClipboardData(text: supportEmail));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('메일 주소를 복사했어요. $supportEmail')),
      );
  }
}

class _BottomRow extends StatelessWidget {
  const _BottomRow({
    required this.rowKey,
    required this.icon,
    required this.label,
    required this.onTap,
    this.detail,
  });

  final Key rowKey;
  final IconData icon;
  final String label;
  final String? detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: rowKey,
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: AppColors.guardianInkSoft,
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.centerLeft,
        ),
        icon: Icon(icon, size: 18),
        label: Text(
          detail == null ? label : '$label · ${detail!}',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
