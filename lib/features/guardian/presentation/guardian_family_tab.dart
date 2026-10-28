import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/remote/senior_link_repository.dart';
import '../../../domain/pair_link.dart';
import '../application/guardian_home_apps_controller.dart';
import '../application/guardian_pairing_controller.dart';
import '../application/guardian_session_controller.dart';
import 'widgets/guardian_surfaces.dart';

/// Widget keys the tests drive.
class GuardianFamilyKeys {
  GuardianFamilyKeys._();

  static const invite = Key('guardian-family-invite');
  static const enterCode = Key('guardian-family-enter-code');
  static const codeField = Key('guardian-family-code-field');
  static const nameField = Key('guardian-family-name-field');
  static const phoneField = Key('guardian-family-phone-field');
  static const confirm = Key('guardian-family-confirm');
  static const message = Key('guardian-family-message');
  static const issuedCode = Key('guardian-family-issued-code');
  static const guardians = Key('guardian-family-guardians');
  static const recovery = Key('guardian-family-recovery');
  static const signOut = Key('guardian-family-sign-out');
  static const signOutConfirm = Key('guardian-family-sign-out-confirm');
  static const familyInvite = Key('guardian-family-invite-family');
  static const requestPrimary = Key('guardian-family-request-primary');
}

/// 부모님 연결하기, on its own, for the one screen that needs it alone.
///
/// **The 홈 tab says 아직 연결된 부모님이 없어요 and then had to send them
/// somewhere else to fix it** - 가족 탭에서 부모님을 추가하면, on a tab the
/// guardian had not opened and had no reason to. The thing to do goes
/// directly under the sentence saying it has not been done.
class GuardianConnectParentCard extends StatelessWidget {
  const GuardianConnectParentCard({super.key, this.heading = true});

  /// The 홈 tab's own title is already 부모님 연결하기, so the card repeats it
  /// there and says it once in the 연결 관리 block, where nothing else does.
  final bool heading;

  @override
  Widget build(BuildContext context) =>
      GuardianCard(child: _ConnectParent(heading: heading));
}

/// 연결 관리 — who else is looking after them, inviting a sibling, getting a
/// replaced phone back, and signing out.
///
/// **It was its own tab and is not any more.** Five destinations with 가족
/// last meant the only route to 로그아웃, and to inviting a sibling, was a
/// tab nobody opened; connecting a parent - the one thing on it a new
/// guardian needs - now sits on 홈 where the app says it is missing. What
/// is left is the once-in-a-while half, so it is a block at the bottom of a
/// page that already scrolls rather than a destination of its own.
class GuardianFamilySection extends ConsumerWidget {
  const GuardianFamilySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(selectedSeniorProfileProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        const GuardianHeading(title: '연결 관리'),
        const SizedBox(height: 14),
        // **Only once there is a parent.** With none, 홈 carries this card
        // under its own 아직 연결된 부모님이 없어요, and the two would be the
        // same form twice in one tree - an `IndexedStack` keeps every tab
        // built, so they would be two widgets wearing one key. Here it is
        // for adding a second parent.
        if (profile != null) ...[
          const _Card(child: _ConnectParent()),
          _Card(child: _Guardians(seniorProfileId: profile.id)),
          _Card(
            child: _CodeCard(
              key: GuardianFamilyKeys.familyInvite,
              title: '가족 초대하기',
              // Free per the PRD; the uploaded design had put this behind
              // 안심 케어.
              detail: '형제자매도 함께 돌볼 수 있어요. 무료입니다.',
              action: '초대 번호 만들기',
              issue: (c) => c.createFamilyInvite(profile.id),
              hint: '초대받은 분이 앱에서 이 번호를 넣으면 함께 돌볼 수 있어요. 7일 동안 쓸 수 있어요.',
            ),
          ),
          _Card(
            child: _CodeCard(
              key: GuardianFamilyKeys.recovery,
              title: '부모님 폰 다시 연결하기',
              detail:
                  '폰을 바꾸셨거나 앱을 지웠다 다시 까셨을 때 쓰세요. '
                  '홈 화면과 설정이 그대로 돌아옵니다.',
              action: '연결 번호 만들기',
              issue: (c) => c.createRecoveryCode(profile.id),
              hint: '부모님 폰의 가족 연결 화면에 이 번호를 넣어 주세요. 24시간 동안 쓸 수 있어요.',
            ),
          ),
        ],
        const SizedBox(height: 8),
        const _Card(child: _SignOut()),
      ],
    );
  }
}

/// 로그아웃. `04_SCREEN_SPEC` puts it in the guardian's 설정 탭; this app
/// folded that tab into 가족, and the row went missing in the fold —
/// `signOut()` has been on the controller since Phase 4 with nothing calling
/// it, so a guardian signed in on a borrowed phone had no way off it.
///
/// Quiet on purpose. It is the last thing on the tab and it is not a filled
/// button: nobody opens this app in order to leave it.
class _SignOut extends ConsumerWidget {
  const _SignOut();

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: GuardianFamilyKeys.signOutConfirm,
        title: const Text('로그아웃할까요?'),
        // What it does *not* do. A guardian who reads 로그아웃 as 연결 끊기
        // will never press it, and one who presses it expecting that is
        // worse off still.
        content: const Text(
          '부모님 폰은 그대로입니다. 홈 화면도, 연결도 바뀌지 않아요.\n'
          '다시 로그인하시면 이어서 쓰실 수 있어요.',
          style: TextStyle(fontSize: 14.5, height: 1.55),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('그만두기'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('로그아웃'),
          ),
        ],
      ),
    );
    if (go != true || !context.mounted) return;

    await ref.read(guardianLoginControllerProvider.notifier).signOut();
    if (!context.mounted) return;
    // Back to the launch gate rather than staying put. Nothing redirects this
    // route on its own, so a dashboard built from a session that no longer
    // exists would go on showing the last parent's name until the app was
    // restarted.
    context.go(Routes.firstScreen);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: GuardianFamilyKeys.signOut,
        onPressed: () => _confirm(context, ref),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.guardianInkSoft,
          padding: EdgeInsets.zero,
        ),
        icon: const Icon(Icons.logout_rounded, size: 18),
        label: const Text(
          '로그아웃',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// The two paths from `07_PHASE_PLAN`, side by side.
class _ConnectParent extends ConsumerStatefulWidget {
  const _ConnectParent({this.heading = true});

  final bool heading;

  @override
  ConsumerState<_ConnectParent> createState() => _ConnectParentState();
}

class _ConnectParentState extends ConsumerState<_ConnectParent> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _byCode = false;
  bool _busy = false;
  String? _error;
  PairLink? _issued;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '부모님을 부를 이름을 넣어 주세요.');
      return;
    }
    if (_byCode && _code.text.trim().length < 4) {
      setState(() => _error = '부모님이 불러주신 4자리 번호를 넣어 주세요.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final controller = ref.read(guardianPairingControllerProvider.notifier);
      if (_byCode) {
        await controller.claimCode(
          code: _code.text,
          displayName: name,
          phoneNumber: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        );
        if (mounted) setState(() => _issued = null);
      } else {
        final link = await controller.inviteSenior(
          displayName: name,
          phoneNumber: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        );
        if (mounted) setState(() => _issued = link);
      }
    } on SeniorLinkException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object {
      if (mounted) setState(() => _error = '연결하지 못했어요. 잠시 후 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final issued = _issued;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.heading) ...[
          const Text(
            '부모님 연결하기',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              color: AppColors.guardianInk,
            ),
          ),
          const SizedBox(height: 10),
        ],
        GuardianSwitcher(
          options: const [
            ('설치 문자 보내기', Icons.sms_rounded),
            ('불러주신 번호 넣기', Icons.dialpad_rounded),
          ],
          selected: _byCode ? 1 : 0,
          onSelected: (i) => setState(() {
            _byCode = i == 1;
            _error = null;
            _issued = null;
          }),
        ),
        const SizedBox(height: 14),
        Text(
          _byCode
              ? '부모님 폰의 가족 연결 화면에 4자리 번호가 나옵니다. '
                    '그 번호를 불러 주시면 여기에 넣어 주세요. '
                    '번호로는 전화번호를 알 수 없어서, 이름과 번호는 여기서 받습니다.'
              : '설치 링크가 담긴 문자를 문자 앱에 채워 드립니다. '
                    '보내기는 직접 눌러 주세요.',
          style: const TextStyle(
            fontSize: 14,
            height: 1.5,
            color: AppColors.guardianInkFaint,
          ),
        ),
        const SizedBox(height: 14),
        if (_byCode) ...[
          TextField(
            key: GuardianFamilyKeys.codeField,
            controller: _code,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              letterSpacing: 8,
              fontWeight: FontWeight.w700,
            ),
            decoration: guardianField(label: '부모님이 불러주신 번호'),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          key: GuardianFamilyKeys.nameField,
          controller: _name,
          enabled: !_busy,
          // **Nobody saves their mother under her name.** The label asked
          // for 부모님 이름 and this is what the senior reads on their own
          // home screen, so 엄마 and 아빠 are the answers it should invite.
          decoration: guardianField(label: '부모님 이름 또는 애칭', hint: '엄마, 아빠, 어머니'),
        ),
        const SizedBox(height: 12),
        TextField(
          key: GuardianFamilyKeys.phoneField,
          controller: _phone,
          enabled: !_busy,
          keyboardType: TextInputType.phone,
          decoration: guardianField(label: '부모님 전화번호', helper: '비워 두셔도 됩니다'),
        ),
        if (_error case final message?) ...[
          const SizedBox(height: 10),
          Text(
            message,
            key: GuardianFamilyKeys.message,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 14),
        GuardianPrimaryButton(
          key: _byCode
              ? GuardianFamilyKeys.enterCode
              : GuardianFamilyKeys.invite,
          onPressed: _busy ? null : _submit,
          icon: _byCode ? Icons.link_rounded : Icons.sms_rounded,
          label: _busy ? '준비하는 중이에요' : (_byCode ? '연결하기' : '문자 앱 열기'),
        ),
        if (issued != null) ...[
          const SizedBox(height: 16),
          // Never "문자를 보냈어요": the app hands the message to the messaging
          // app and cannot see what happens after that.
          const Text(
            '문자 앱에 내용을 채워 두었어요. 보내기는 직접 눌러 주세요.',
            style: TextStyle(fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 10),
          _IssuedCode(
            code: issued.code,
            hint:
                '문자가 열리지 않거나 링크로 연결이 안 되면, '
                '부모님께 이 번호를 불러 주세요.',
          ),
        ],
      ],
    );
  }
}

/// A card that issues a code on demand and then shows it.
class _CodeCard extends ConsumerStatefulWidget {
  const _CodeCard({
    super.key,
    required this.title,
    required this.detail,
    required this.action,
    required this.issue,
    required this.hint,
  });

  final String title;
  final String detail;
  final String action;
  final Future<PairLink> Function(GuardianPairingController) issue;
  final String hint;

  @override
  ConsumerState<_CodeCard> createState() => _CodeCardState();
}

class _CodeCardState extends ConsumerState<_CodeCard> {
  PairLink? _link;
  String? _error;
  bool _busy = false;

  Future<void> _issue() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final link = await widget.issue(
        ref.read(guardianPairingControllerProvider.notifier),
      );
      if (mounted) setState(() => _link = link);
    } on SeniorLinkException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object {
      if (mounted) setState(() => _error = '번호를 만들지 못했어요. 잠시 후 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final link = _link;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: AppColors.guardianInk,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          widget.detail,
          style: const TextStyle(
            fontSize: 14,
            height: 1.55,
            color: AppColors.guardianInkSoft,
          ),
        ),
        const SizedBox(height: 12),
        if (link == null)
          GuardianPrimaryButton(
            onPressed: _busy ? null : _issue,
            icon: Icons.add_rounded,
            label: _busy ? '만드는 중이에요' : widget.action,
          )
        else
          _IssuedCode(code: link.code, hint: widget.hint),
        if (_error case final message?) ...[
          const SizedBox(height: 10),
          Text(
            message,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }
}

class _IssuedCode extends StatelessWidget {
  const _IssuedCode({required this.code, required this.hint});

  final String code;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Scales down rather than clipping: six wide-tracked digits overflow a
        // narrow phone otherwise.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: SelectableText(
            code,
            key: GuardianFamilyKeys.issuedCode,
            style: const TextStyle(
              fontSize: 34,
              letterSpacing: 8,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          hint,
          style: const TextStyle(
            fontSize: 13,
            height: 1.55,
            color: AppColors.guardianInkFaint,
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => Clipboard.setData(ClipboardData(text: code)),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.guardianPrimary,
            side: const BorderSide(color: AppColors.guardianRule),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: const Text('번호 복사하기'),
        ),
      ],
    );
  }
}

/// Everyone looking after this parent, and the one action that can change who
/// speaks for them.
class _Guardians extends ConsumerWidget {
  const _Guardians({required this.seniorProfileId});

  final String seniorProfileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guardians = ref.watch(guardiansForSelectedProvider);

    return Column(
      key: GuardianFamilyKeys.guardians,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '연결된 가족',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: AppColors.guardianInk,
          ),
        ),
        const SizedBox(height: 10),
        switch (guardians) {
          AsyncData(:final value) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final guardian in value)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    '${guardian.displayName ?? guardian.email ?? '보호자'}'
                    '${guardian.isPrimary ? ' · 대표 보호자' : ''}',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              if (value.every((g) => !g.isPrimary) || value.length > 1) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  key: GuardianFamilyKeys.requestPrimary,
                  onPressed: () => _requestPrimary(context, ref),
                  child: const Text('대표 보호자 맡기'),
                ),
                const SizedBox(height: 6),
                // The approval is the whole mechanism: everyone else in this
                // list is a guardian, so nothing they agree among themselves
                // establishes which one the senior wants answering for them.
                const Text(
                  '부모님 폰에서 허락하셔야 바뀝니다.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.guardianInkFaint,
                  ),
                ),
              ],
            ],
          ),
          AsyncError() => const Text('가족 목록을 불러오지 못했어요.'),
          _ => const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          ),
        },
      ],
    );
  }

  Future<void> _requestPrimary(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(guardianPairingControllerProvider.notifier)
          .requestPrimary(seniorProfileId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('부모님 폰에 허락을 요청했어요.')));
    } on SeniorLinkException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
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
