import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/router/routes.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/remote/senior_link_repository.dart';
import '../../../domain/guardian_notice.dart';
import '../../../domain/pair_link.dart';
import '../application/guardian_home_apps_controller.dart';
import '../application/guardian_pairing_controller.dart';
import '../application/guardian_session_controller.dart';
import '../../care/application/care_controller.dart';
import 'widgets/guardian_surfaces.dart';
import 'widgets/signup_consent_sheet.dart';

/// Widget keys the tests drive.
class GuardianFamilyKeys {
  GuardianFamilyKeys._();

  static const invite = Key('guardian-family-invite');
  static const enterCode = Key('guardian-family-enter-code');
  static const codeField = Key('guardian-family-code-field');
  static const nameField = Key('guardian-family-name-field');
  static const phoneField = Key('guardian-family-phone-field');
  static const myPhoneOnConnect = Key('guardian-family-connect-my-phone');
  static const confirm = Key('guardian-family-confirm');
  static const message = Key('guardian-family-message');
  static const issuedCode = Key('guardian-family-issued-code');
  static const sendInstallLink = Key('guardian-family-send-install-link');
  static const sendInviteCode = Key('guardian-family-send-invite-code');
  static const recovery = Key('guardian-family-recovery');
  static const signOut = Key('guardian-family-sign-out');
  static const signOutConfirm = Key('guardian-family-sign-out-confirm');
  static const myName = Key('guardian-family-my-name');
  static const myNameEdit = Key('guardian-family-my-name-edit');
  static const myNameField = Key('guardian-family-my-name-field');
  static const myPhone = Key('guardian-family-my-phone');
  static const myPhoneEdit = Key('guardian-family-my-phone-edit');
  static const myPhoneField = Key('guardian-family-my-phone-field');
  static const leave = Key('guardian-family-leave');
  static const leaveConfirm = Key('guardian-family-leave-confirm');
  static const deleteAccount = Key('guardian-family-delete-account');
  static const deleteConfirm = Key('guardian-family-delete-confirm');
  static const phoneChangeConfirm = Key('guardian-family-phone-change-confirm');
  static const privacy = Key('guardian-family-privacy');
  static const notice = Key('guardian-family-notice');
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

/// 연결 관리 — getting a replaced phone back, leaving, a name, a number,
/// signing out and deleting the account.
///
/// **It was its own tab and is not any more.** Five destinations with 가족
/// last meant the only route to 로그아웃 was a
/// tab nobody opened; connecting a parent - the one thing on it a new
/// guardian needs - now sits on 홈 where the app says it is missing. What
/// is left is the once-in-a-while half, so it is a block at the bottom of a
/// page that already scrolls rather than a destination of its own.
class GuardianFamilySection extends ConsumerWidget {
  const GuardianFamilySection({
    super.key,
    this.title = '연결 관리',
    this.notices = true,
  });

  /// 연결 관리 once there is a parent; 내 계정 when there is none, because
  /// nothing under it is a connection then - it is a name, a number, the
  /// policy, signing out and deleting the account.
  final String title;

  /// Off where the page has already drawn [GuardianNotices] at the top. A
  /// guardian whose parent cut the link should read that first, not under
  /// the connect form at the bottom of the page.
  final bool notices;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(selectedSeniorProfileProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        GuardianHeading(title: title),
        const SizedBox(height: 14),
        if (notices) const GuardianNotices(),
        // **Only once there is a parent.** With none, 홈 carries the connect
        // form under its own 아직 연결된 부모님이 없어요. Here it is only for
        // the parent's new phone.
        if (profile != null) ...[
          // Keyed: an unkeyed child in a list is matched by position, and a
          // card appearing above this one once threw the form's State away
          // mid-submit.
          const _Card(
            key: ValueKey('connect'),
            child: _ConnectParent(phoneChange: true),
          ),
          _Card(
            key: const ValueKey('recovery'),
            child: _CodeCard(
              key: GuardianFamilyKeys.recovery,
              title: '부모님 폰 다시 연결하기',
              // **The other way round is usually quicker and is said first.**
              // A parent with a new phone does what they always do - press
              // 번호 보여주기 - so most of the time the four digits already
              // exist and the child only has to type them above, where the
              // app asks whether the phone was replaced. This card is for
              // when the child noticed first.
              detail:
                  '부모님이 새 폰에서 번호 보여주기를 누르셨다면, 위에 그 번호를 넣는 쪽이 빠릅니다.\n'
                  '먼저 아셨다면 여기서 번호를 만들어 부모님께 불러 주세요. '
                  '홈 화면과 글씨 크기가 그대로 돌아옵니다.',
              action: '연결 번호 만들기',
              issue: (c) => c.createRecoveryCode(profile.id),
              hint: '부모님 폰의 가족 연결 화면에 이 번호를 넣어 주세요. 24시간 동안 쓸 수 있어요.',
            ),
          ),
        ],
        if (profile != null)
          _Card(
            key: const ValueKey('leave'),
            child: _Leave(
              seniorProfileId: profile.id,
              seniorName: profile.displayName,
            ),
          ),
        const _Card(key: ValueKey('my-name'), child: _MyName()),
        const _Card(key: ValueKey('my-phone'), child: _MyPhone()),
        const SizedBox(height: 8),
        const _Card(key: ValueKey('legal'), child: _Legal()),
        const SizedBox(height: 8),
        const _Card(key: ValueKey('sign-out'), child: _SignOut()),
        const SizedBox(height: 8),
        const _Card(key: ValueKey('delete-account'), child: _DeleteAccount()),
      ],
    );
  }
}

/// 부모님이 부르시는 이름, after the one-question screen has asked for it.
///
/// It is asked once, before the dashboard, and it is what a senior reads on
/// their own phone - so it needs somewhere to be corrected when a guardian
/// typed it in a hurry or their mother started calling them something else.
class _MyName extends ConsumerStatefulWidget {
  const _MyName();

  @override
  ConsumerState<_MyName> createState() => _MyNameState();
}

class _MyNameState extends ConsumerState<_MyName> {
  bool _busy = false;

  Future<void> _edit(String current) async {
    final controller = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('부모님이 뭐라고 부르세요?'),
        content: TextField(
          key: GuardianFamilyKeys.myNameField,
          controller: controller,
          autofocus: true,
          cursorColor: AppColors.guardianPrimary,
          decoration: guardianField(label: '부모님이 부르시는 이름', hint: '영희, 큰아들, 막내'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('그만두기'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    controller.dispose();
    // An empty answer leaves the old name standing: this is the one field in
    // the app that may not become blank, because the senior's card reads it.
    if (name == null || name.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(seniorLinkRepositoryProvider)
          .ensureGuardianAccount(displayName: name);
      ref.invalidate(guardianAccountProvider);
    } on Object {
      // The old name is still on the server and still on screen.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = ref.watch(guardianAccountProvider).value?.displayName ?? '';

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '부모님이 부르시는 이름',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: AppColors.guardianInk,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                name,
                key: GuardianFamilyKeys.myName,
                style: const TextStyle(
                  fontSize: 14.5,
                  color: AppColors.guardianInkSoft,
                ),
              ),
            ],
          ),
        ),
        TextButton(
          key: GuardianFamilyKeys.myNameEdit,
          onPressed: _busy ? null : () => _edit(name),
          child: const Text('바꾸기'),
        ),
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
  const _ConnectParent({this.heading = true, this.phoneChange = false});

  final bool heading;

  /// Once a parent is connected, the only number worth typing here is their
  /// new phone's. 1대1 - 무조건 자녀 하나, 부모 하나 - so the install text and
  /// the name for a second parent are gone from this card rather than left
  /// to produce a refusal.
  final bool phoneChange;

  @override
  ConsumerState<_ConnectParent> createState() => _ConnectParentState();
}

class _ConnectParentState extends ConsumerState<_ConnectParent> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _myPhone = TextEditingController();
  final _code = TextEditingController();
  bool _byCode = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _myPhone.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _byCode = widget.phoneChange;
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (!widget.phoneChange && name.isEmpty) {
      setState(() => _error = '부모님을 부를 이름을 넣어 주세요.');
      return;
    }
    if (_byCode && _code.text.trim().length < 4) {
      setState(() => _error = '부모님이 불러주신 4자리 번호를 넣어 주세요.');
      return;
    }
    // The parent pressed 번호 보여주기 on the new handset, which made a
    // second, empty profile. This card only exists once a parent is
    // connected, so the number is that new phone's and it moves onto the
    // parent this guardian already has.
    //
    // **Asked first, naming the parent.** The server takes any empty
    // profile, so a number shown on somebody else's phone - a father's, a
    // neighbour's - would move *that* handset onto this parent and take the
    // old one off. The 1대1 cleanup dropped the question for a while, on the
    // grounds that there is only one parent it can mean; that was true of
    // the profile and false of the phone.
    String? moveOnto;
    if (widget.phoneChange) {
      final existing = ref.read(linkedSeniorProfilesProvider).value ?? const [];
      if (existing.isEmpty) return;
      final parent = existing.first;
      final sure = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          key: GuardianFamilyKeys.phoneChangeConfirm,
          title: Text('${parent.displayName}님 폰을 새 폰으로 바꿀까요?'),
          content: Text(
            '방금 넣으신 번호가 ${parent.displayName}님의 새 폰에 나온 번호일 때만 '
            '바꿔 주세요.\n'
            '대화와 홈 화면, 글씨 크기가 새 폰으로 옮겨지고, 예전 폰은 연결이 풀립니다.',
            style: const TextStyle(fontSize: 14.5, height: 1.55),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('아니요'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('네, 새 폰이에요'),
            ),
          ],
        ),
      );
      if (sure != true) return;
      moveOnto = parent.id;
    }
    if (!mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final controller = ref.read(guardianPairingControllerProvider.notifier);
      final mine = _myPhone.text.trim();
      if (_byCode) {
        if (moveOnto != null) {
          await controller.movePhone(
            code: _code.text,
            seniorProfileId: moveOnto,
          );
        } else {
          await controller.claimCode(
            code: _code.text,
            displayName: name,
            // **내 번호, not 부모님's.** `claim_senior_pairing_code` writes
            // this to `guardian_accounts.phone_number`, which is the number
            // the parent's 긴급 연락 dials - and the form used to send the
            // 부모님 전화번호 field here, so connecting by code left the
            // senior's SOS button ringing her own phone. Found on the live
            // project with accounts already saved that way.
            phoneNumber: mine.isEmpty ? null : mine,
          );
        }
      } else {
        await controller.inviteSenior(
          displayName: name,
          // Here the number **is** the parent's: it is who the install SMS
          // is addressed to, and nothing else reads it.
          phoneNumber: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        );
      }
      // Saved on both paths, which is also new. 경로 A never asked for the
      // guardian's own number at all, so their parent's 보호자 tile stayed
      // 자녀분 전화번호가 아직 없어요 forever.
      if (mine.isNotEmpty) {
        await ref
            .read(seniorLinkRepositoryProvider)
            .ensureGuardianAccount(phoneNumber: mine);
        ref.invalidate(guardianAccountProvider);
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
    final issued = ref.watch(lastInviteProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.heading) ...[
          Text(
            widget.phoneChange ? '부모님이 폰을 바꾸셨나요?' : '부모님 연결하기',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              color: AppColors.guardianInk,
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (!widget.phoneChange)
          GuardianSwitcher(
            options: const [
              ('설치 문자 보내기', Icons.sms_rounded),
              ('불러주신 번호 넣기', Icons.dialpad_rounded),
            ],
            selected: _byCode ? 1 : 0,
            onSelected: (i) {
              // Cleared through the provider that holds it now, so switching
              // away from 설치 문자 takes the code off the screen.
              ref.read(lastInviteProvider.notifier).set(null);
              setState(() {
                _byCode = i == 1;
                _error = null;
              });
            },
          ),
        const SizedBox(height: 14),
        Text(
          widget.phoneChange
              ? '새 폰에서 가족 연결을 누르고 번호 보여주기를 누르시면 4자리 번호가 나옵니다. '
                    '그 번호를 넣으시면 대화와 홈 화면, 글씨 크기가 그대로 옮겨집니다.'
              : _byCode
              ? '부모님 폰에서 가족 연결을 누르고 번호 보여주기를 누르시면 4자리 번호가 나옵니다. '
                    '그 번호를 불러 주시면 여기에 넣어 주세요. '
                    '번호로는 전화번호를 알 수 없어서, 이름과 번호는 여기서 받습니다.'
              : (ref.watch(appConfigProvider).value?.storeListed ?? false)
              ? '번호를 만들면 보낼 문자 두 개를 준비해 드려요.\n'
                    '보내기는 문자 앱에서 직접 눌러 주세요.'
              : '번호를 만들면 보낼 문자를 준비해 드려요.\n'
                    '보내기는 문자 앱에서 직접 눌러 주세요.',
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
        // A new phone for the parent already here: no name to ask, and their
        // own number is a row further down 연결 관리.
        if (!widget.phoneChange) ...[
          TextField(
            key: GuardianFamilyKeys.nameField,
            controller: _name,
            enabled: !_busy,
            // **Nobody saves their mother under her name.** The label asked
            // for 부모님 이름 and this is what the senior reads on their own
            // home screen, so 엄마 and 아빠 are the answers it should invite.
            decoration: guardianField(
              label: '부모님 이름 또는 애칭',
              hint: '엄마, 아빠, 어머니',
            ),
          ),
          const SizedBox(height: 12),
          // **부모님 전화번호 only where it is the parent's number.** On the
          // SMS path it is who the message goes to. On the code path there is
          // nothing to send, and the one field used to be written into
          // `guardian_accounts.phone_number` - the number the senior's 긴급
          // 연락 dials - so connecting by code gave a mother a 보호자 button
          // that rang her own phone.
          if (!_byCode) ...[
            TextField(
              key: GuardianFamilyKeys.phoneField,
              controller: _phone,
              enabled: !_busy,
              keyboardType: TextInputType.phone,
              decoration: guardianField(
                label: '부모님 전화번호',
                helper: '문자를 보낼 번호입니다. 비워 두셔도 됩니다',
              ),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            key: GuardianFamilyKeys.myPhoneOnConnect,
            controller: _myPhone,
            enabled: !_busy,
            keyboardType: TextInputType.phone,
            // Why it is asked for, on the field. A number with no reason beside
            // it is the one people leave blank - and left blank, the parent's
            // 긴급 연락 has no 보호자 button at all.
            decoration: guardianField(
              label: '내 전화번호',
              helper: '부모님 폰의 긴급 연락에서 이 번호로 전화가 갑니다',
            ),
          ),
        ],
        if (_error case final message?) ...[
          const SizedBox(height: 10),
          Text(
            message,
            key: GuardianFamilyKeys.message,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 14),
        // **The number first, the texts after.** This button used to open
        // the messaging app straight away with one text carrying both the
        // link and the number, and the guardian never saw the number on this
        // screen until they came back - on the live server, to a page that
        // no longer had it. Once issued, the button gives way to the number
        // and the two texts, so pressing it twice cannot make a second
        // parent.
        if (_byCode || issued == null)
          GuardianPrimaryButton(
            key: _byCode
                ? GuardianFamilyKeys.enterCode
                : GuardianFamilyKeys.invite,
            onPressed: _busy ? null : _submit,
            icon: _byCode ? Icons.link_rounded : Icons.add_rounded,
            label: _busy ? '준비하는 중이에요' : (_byCode ? '연결하기' : '연결 번호 만들기'),
          )
        else
          GuardianInviteSender(
            link: issued.link,
            phoneNumber: issued.phoneNumber,
          ),
      ],
    );
  }
}

/// The install number, and the two texts that carry it.
///
/// Drawn in two places: under the connect form the moment the number is
/// made, and on 홈's 기다리고 있어요 page for as long as nobody has used it.
/// One widget for both, so the two cannot come to say different things about
/// the same number.
class GuardianInviteSender extends ConsumerWidget {
  const GuardianInviteSender({super.key, required this.link, this.phoneNumber});

  final PairLink link;

  /// Who the texts are addressed to. Null leaves the recipient for the
  /// guardian to pick in the messaging app, which is also what happens when
  /// this is drawn from the server's copy after a restart.
  final String? phoneNumber;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(guardianPairingControllerProvider.notifier);
    // **Before the app is on Play there is one text, not two.** The store
    // link opens a page that does not exist yet, and a parent who taps it
    // and lands on 찾을 수 없음 is worse off than one never sent it. Their
    // app is installed by hand until then. A server setting, so launch day
    // turns the link on without an update.
    final listed = ref.watch(appConfigProvider).value?.storeListed ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '연결 번호',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.guardianInkSoft,
          ),
        ),
        const SizedBox(height: 4),
        _IssuedCode(
          code: link.code,
          hint: '부모님 폰의 가족 연결 화면에 넣는 번호예요. 7일 동안 쓸 수 있어요.',
        ),
        const SizedBox(height: 16),
        // Never "문자를 보냈어요": the app hands each text to the messaging
        // app and cannot see what happens after that.
        Text(
          listed
              ? '아래 두 문자를 차례로 보내 주세요. '
                    '문자 앱이 열리면 보내기는 직접 눌러 주세요.'
              : '아래 문자를 보내 주세요. '
                    '문자 앱이 열리면 보내기는 직접 눌러 주세요.',
          style: const TextStyle(
            fontSize: 14,
            height: 1.5,
            color: AppColors.guardianInk,
          ),
        ),
        const SizedBox(height: 12),
        if (listed) ...[
          GuardianPrimaryButton(
            key: GuardianFamilyKeys.sendInstallLink,
            onPressed: () => unawaited(
              controller.sendInstallLink(link, phoneNumber: phoneNumber),
            ),
            icon: Icons.download_rounded,
            label: '① 설치 링크 보내기',
          ),
          const SizedBox(height: 10),
        ],
        GuardianPrimaryButton(
          key: GuardianFamilyKeys.sendInviteCode,
          onPressed: () => unawaited(
            controller.sendInviteCode(
              link,
              phoneNumber: phoneNumber,
              afterInstall: listed,
            ),
          ),
          icon: Icons.pin_rounded,
          label: listed ? '② 연결 번호 보내기' : '연결 번호 보내기',
        ),
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

class _Card extends StatelessWidget {
  const _Card({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GuardianCard(child: child),
    );
  }
}

/// 부모님이 끊으셨다는 한 줄.
///
/// **It is on this screen because nowhere else is left.** The moment a link
/// goes to `'removed'`, every provider behind the dashboard is refused by
/// RLS - the profile, the conversation, the readings - so without this the
/// app shows a guardian an empty 홈 and says nothing at all. An alert could
/// not do it: `alerts` hangs off the parent's profile and its policy is
/// `guardian_manages`, which is exactly what just went false.
///
/// Said once. Marked read as soon as it is drawn, because the thing it
/// reports is not an action waiting to be taken.
class GuardianNotices extends ConsumerStatefulWidget {
  const GuardianNotices({super.key});

  @override
  ConsumerState<GuardianNotices> createState() => _NoticesState();
}

class _NoticesState extends ConsumerState<GuardianNotices> {
  bool _marked = false;

  /// What this screen has already shown. Marking them read empties the next
  /// fetch, and the dashboard re-reads every fifteen seconds - so without
  /// this the line would vanish while the guardian was reading it.
  List<GuardianNotice> _shown = const [];

  @override
  Widget build(BuildContext context) {
    final fetched = ref.watch(guardianNoticesProvider).value ?? const [];
    if (fetched.isNotEmpty) _shown = fetched;
    final notices = _shown;
    if (notices.isEmpty) return const SizedBox.shrink();

    if (!_marked) {
      _marked = true;
      // Not awaited and not blocking the frame. A notice shown twice is a
      // smaller cost than a screen that waits on the network to draw.
      unawaited(
        ref.read(pairingRepositoryProvider).markNoticesRead([
          for (final n in notices) n.id,
        ]),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GuardianCard(
        child: Column(
          key: GuardianFamilyKeys.notice,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final notice in notices) ...[
              Text(
                notice.seniorName == null
                    ? notice.body
                    : '${notice.seniorName}님 · ${notice.body}',
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  height: 1.5,
                  color: AppColors.guardianInk,
                ),
              ),
              const SizedBox(height: 6),
            ],
            // **No reason, because the app does not know one** - and
            // guessing in writing at why somebody's mother cut the link
            // would be worse than silence. What it can say is what to do,
            // which is ask her.
            const Text(
              '다시 연결하시려면 부모님께 번호를 여쭤보고 아래 「불러주신 번호 넣기」에서 넣어 주세요.',
              style: TextStyle(
                fontSize: 14,
                height: 1.55,
                color: AppColors.guardianInkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 부모님 연결 끊기.
///
/// Theirs and nobody else's. The parent is not told - nothing changes on their phone beyond
/// the 가족 button going back to saying 가족 연결, and a notice would be the
/// app explaining somebody's child to them.
class _Leave extends ConsumerStatefulWidget {
  const _Leave({required this.seniorProfileId, required this.seniorName});

  final String seniorProfileId;
  final String seniorName;

  @override
  ConsumerState<_Leave> createState() => _LeaveState();
}

class _LeaveState extends ConsumerState<_Leave> {
  bool _busy = false;

  Future<void> _confirm() async {
    // Said only when it is true, and read before the dialog opens so the
    // sentence about the refund cannot appear for somebody with nothing to
    // refund. **Whose finger is on 끊기 does not change the money** - use
    // does, the same rule 해지 follows - so the line is the rule, not a
    // promise.
    final careLine = careLeavingLine(
      ref.read(careStateProvider).value?.stage,
      reconnect: true,
    );
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: GuardianFamilyKeys.leaveConfirm,
        title: Text('${widget.seniorName}님과 연결을 끊을까요?'),
        content: Text(
          // What is **not** lost, first. The same rule 로그아웃 follows, and
          // for the same reason: a guardian who thinks this changes their
          // mother's phone will never press it.
          '${widget.seniorName}님 폰은 그대로입니다. 버튼도 글씨 크기도 바뀌지 않아요.\n'
          '주고받은 메시지는 남지만 이 폰에서는 보이지 않게 됩니다.\n'
          '${careLine == null ? '' : '$careLine\n'}'
          '나중에 다시 연결하실 수 있어요.',
          style: const TextStyle(fontSize: 14.5, height: 1.55),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('아니요, 그대로 둘게요'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('네'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(guardianPairingControllerProvider.notifier)
          .leaveSenior(widget.seniorProfileId);
    } on SeniorLinkException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: GuardianFamilyKeys.leave,
        onPressed: _busy ? null : _confirm,
        style: TextButton.styleFrom(
          foregroundColor: AppColors.guardianInkSoft,
          padding: EdgeInsets.zero,
        ),
        icon: const Icon(Icons.link_off_rounded, size: 18),
        label: Text(
          '${widget.seniorName}님 연결 끊기',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// 내 전화번호 — the one number this app holds, and the one it could not
/// change.
///
/// **It is the number the parent's 긴급 연락 dials.** A guardian who changes
/// phone number and cannot correct it here leaves their mother's 보호자
/// button ringing a dead line, at the moment she is least able to work out
/// why. Nothing else in the app could fix that: 연결 관리 could change a
/// name and not this.
class _MyPhone extends ConsumerStatefulWidget {
  const _MyPhone();

  @override
  ConsumerState<_MyPhone> createState() => _MyPhoneState();
}

class _MyPhoneState extends ConsumerState<_MyPhone> {
  bool _busy = false;

  /// Owned by the State rather than built inside `_edit`.
  ///
  /// A controller disposed the moment `showDialog` returns is still attached
  /// to a dialog that is animating out, and the next frame rebuilds the
  /// field against a dead controller. It throws where nobody is looking -
  /// the dialog is already closing - so it reads as the save not happening.
  final _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _edit(String current) async {
    final controller = _field..text = current;
    final number = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('내 전화번호'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Why it is being asked for. A phone number with no reason given
            // beside it is the field people leave blank.
            const Text(
              '부모님 폰의 긴급 연락에서 이 번호로 전화가 갑니다.',
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 12),
            TextField(
              key: GuardianFamilyKeys.myPhoneField,
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.phone,
              cursorColor: AppColors.guardianPrimary,
              decoration: guardianField(label: '내 전화번호'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('그만두기'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (number == null || number.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(seniorLinkRepositoryProvider)
          .ensureGuardianAccount(phoneNumber: number);
      ref.invalidate(guardianAccountProvider);
    } on Object {
      // The old number is still on the server and still on screen.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final number = ref.watch(guardianAccountProvider).value?.phoneNumber ?? '';

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '내 전화번호',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: AppColors.guardianInk,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                // Never blank-looking: an empty value here means the parent's
                // SOS tile says 자녀분 전화번호가 아직 없어요, which is worth
                // saying on this row too.
                number.isEmpty ? '아직 없어요 · 부모님 긴급 연락에 쓰입니다' : number,
                key: GuardianFamilyKeys.myPhone,
                style: const TextStyle(
                  fontSize: 14.5,
                  color: AppColors.guardianInkSoft,
                ),
              ),
            ],
          ),
        ),
        TextButton(
          key: GuardianFamilyKeys.myPhoneEdit,
          onPressed: _busy ? null : () => _edit(number),
          child: const Text('바꾸기'),
        ),
      ],
    );
  }
}

/// 개인정보처리방침.
///
/// **It was only on the sign-up sheet**, so a guardian who had already signed
/// up could not find it anywhere in the app. Play expects it to be reachable
/// from inside, and a policy somebody agreed to once and can never read again
/// is a policy they did not read.
class _Legal extends StatelessWidget {
  const _Legal();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: GuardianFamilyKeys.privacy,
        onPressed: () => launchUrl(
          Uri.parse(privacyUrl),
          mode: LaunchMode.externalApplication,
        ),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.guardianInkSoft,
          padding: EdgeInsets.zero,
        ),
        icon: const Icon(Icons.description_outlined, size: 18),
        label: const Text(
          '개인정보처리방침 · 이용약관',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// 계정 삭제, which Play's user-data policy requires an app to offer **in the
/// app and from a web page** - and which says in as many words that
/// deactivating or suspending does not count. There was nothing here at all:
/// `lib/` held no 탈퇴 and no `deleteAccount`, only 로그아웃.
///
/// Two things about where it sits. It is **below 로그아웃**, because that is
/// what almost everyone looking for a way out actually wants, and it is the
/// quietest row on the screen. And it names what it is not: the parent's
/// phone keeps working, which is true and is the thing somebody about to
/// press this is most likely to fear.
class _DeleteAccount extends ConsumerStatefulWidget {
  const _DeleteAccount();

  @override
  ConsumerState<_DeleteAccount> createState() => _DeleteAccountState();
}

class _DeleteAccountState extends ConsumerState<_DeleteAccount> {
  bool _busy = false;

  Future<void> _confirm() async {
    final careLine = careLeavingLine(
      ref.read(careStateProvider).value?.stage,
      reconnect: false,
    );
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: GuardianFamilyKeys.deleteConfirm,
        title: const Text('계정을 지울까요?'),
        content: Text(
          // **되돌릴 수 없는 유일한 버튼**, so it is the only one in the app
          // whose dialog says so outright. Everything else that leaves is
          // reversible and says that instead.
          '이 계정과 연결, 신청 내역이 모두 지워집니다. 되돌릴 수 없어요.\n'
          '부모님 폰은 그대로 쓰실 수 있어요. 버튼도 글씨 크기도 그대로입니다.\n'
          '보내신 메시지는 부모님 폰에 남습니다. 부모님이 받으신 것이기도 하니까요.'
          '${careLine == null ? '' : '\n$careLine'}',
          style: const TextStyle(fontSize: 14.5, height: 1.55),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('아니요, 그대로 둘게요'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('계정 지우기'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(guardianLoginControllerProvider.notifier).deleteAccount();
      if (!mounted) return;
      // The account is gone, so the dashboard is pointed at nothing. Nothing
      // redirects this route on its own.
      context.go(Routes.firstScreen);
    } on Object {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('지우지 못했어요. 잠시 후 다시 시도해 주세요.')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: GuardianFamilyKeys.deleteAccount,
        onPressed: _busy ? null : _confirm,
        style: TextButton.styleFrom(
          foregroundColor: AppColors.guardianInkFaint,
          padding: EdgeInsets.zero,
        ),
        icon: const Icon(Icons.person_remove_outlined, size: 18),
        label: const Text(
          '계정 삭제',
          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
