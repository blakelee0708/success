import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
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
  static const familyPlan = Key('care-family-plan');
  static const message = Key('care-message');
  static const alerts = Key('care-alerts');
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
  static const features = <(IconData, Color, Color, String, String)>[
    (
      Icons.place_rounded,
      AppColors.guardianTintGreen,
      AppColors.guardianTintGreenInk,
      '위치 확인',
      '5분 주기로 어디 계신지 확인합니다',
    ),
    (
      Icons.battery_charging_full_rounded,
      AppColors.guardianTintBlue,
      AppColors.guardianTintBlueInk,
      '기기 상태 확인',
      '배터리 · 소리 · 인터넷을 5분 주기로 확인합니다',
    ),
    (
      Icons.download_rounded,
      AppColors.guardianTintViolet,
      AppColors.guardianTintVioletInk,
      '앱 설치 알림',
      '새 앱이 깔리면 알려드립니다',
    ),
  ];

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
        _Card(child: _FamilyPlan()),
        if (profile != null) _Card(child: _Alerts(seniorProfileId: profile.id)),
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
        const SizedBox(height: 10),
        // Said once, plainly, and given enough weight to be read: none of
        // these is built yet, and a paid screen that looks ready is a
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
        for (final (icon, tint, tintInk, title, detail)
            in GuardianCareTab.features)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
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
            ),
          ),
      ],
    );
  }
}

class _FamilyPlan extends ConsumerStatefulWidget {
  @override
  ConsumerState<_FamilyPlan> createState() => _FamilyPlanState();
}

class _FamilyPlanState extends ConsumerState<_FamilyPlan> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final has = ref.watch(hasFamilyPlanProvider).value ?? false;

    return Column(
      key: GuardianCareKeys.familyPlan,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '가족 플랜',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: AppColors.guardianInk,
          ),
        ),
        const SizedBox(height: 6),
        // Two different things that both say 가족: inviting a sibling to help
        // with one parent is free, and this is about looking after more than
        // one parent yourself.
        const Text(
          '부모님을 두 분 이상 돌보실 때 필요합니다. '
          '형제자매를 초대하는 것은 이 플랜과 무관하게 무료예요.',
          style: TextStyle(fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 12),
        if (has)
          const Text(
            '가족 플랜을 쓰고 계세요.',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.guardianInk,
            ),
          )
        else
          GuardianPrimaryButton(
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    try {
                      await ref
                          .read(careControllerProvider.notifier)
                          .buyFamilyPlan();
                    } on Object {
                      // The button stays; nothing changed.
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
            icon: Icons.people_rounded,
            label: _busy ? '신청하는 중이에요' : '가족 플랜 신청하기',
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
