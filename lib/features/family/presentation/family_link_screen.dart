import '../../launcher/presentation/widgets/go_home_bar.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format/korean_particle.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/clay_pad.dart';

import '../../../data/remote/senior_link_repository.dart';
import '../../../domain/pair_link.dart';
import '../../launcher/application/senior_settings_controller.dart';
import '../../launcher/presentation/widgets/senior_notice_layer.dart';
import '../application/senior_pairing_controller.dart';
import 'link_consent_prompt.dart';

/// Widget keys the tests drive.
class FamilyLinkKeys {
  FamilyLinkKeys._();

  static const showCode = Key('family-link-show-code');
  static const waiting = Key('family-link-waiting');
  static const visibility = Key('family-link-visibility');
  static const top = Key('family-link-top');
  static const topContent = Key('family-link-top-content');
  static const shownCode = Key('family-link-shown-code');
  static const code = Key('family-link-code');
  static const submit = Key('family-link-submit');
  static const message = Key('family-link-message');
  static const connected = Key('family-link-connected');
  static const guardians = Key('family-link-guardians');
  static const removeConfirm = Key('family-link-remove-confirm');
}

/// 가족 연결 on the parent's phone.
///
/// Offers both directions at once, because which one applies is not something
/// the senior should have to work out:
///
/// * 이 폰 번호 보여주기 — the 4-digit code their child types (경로 B).
/// * 번호 넣기 — a number their child read out, for a replacement phone or an
///   install link that did not survive.
class FamilyLinkScreen extends ConsumerStatefulWidget {
  const FamilyLinkScreen({super.key});

  @override
  ConsumerState<FamilyLinkScreen> createState() => _FamilyLinkScreenState();
}

class _FamilyLinkScreenState extends ConsumerState<FamilyLinkScreen> {
  final _code = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _enterCode() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(seniorPairingControllerProvider.notifier)
          .enterCode(_code.text);
      ref.invalidate(seniorGuardiansProvider);
    } on SeniorLinkException catch (e) {
      // A mistyped number is the likely cause and the one thing they can fix.
      if (mounted) setState(() => _error = e.message);
    } on Object {
      if (mounted) setState(() => _error = '연결하지 못했어요. 인터넷 연결을 확인해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = ref.watch(seniorSettingsControllerProvider).value?.fontSize;
    // Connected means a guardian is attached, not merely that this phone has a
    // profile — showing a code creates one, and nobody has claimed it yet.
    final connected =
        (ref.watch(seniorGuardiansProvider).value ?? const []).isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('가족 연결')),
      bottomNavigationBar: const SafeArea(child: GoHomeBar()),
      // The question has to be answerable where the person is standing.
      // 경로 B ends with the senior on this screen holding the number out,
      // and that is the moment their child types it - so the card arrives
      // here, not two screens away. Without the `Stack` the layer has
      // nothing to fill and the senior had to press Back to be asked.
      body: Stack(
        children: [
          SafeArea(
            child: MediaQuery.withClampedTextScaling(
              // Raising the text size is the point of this app, so the code and
              // the field grow with it rather than being pinned small.
              minScaleFactor: scale?.scale ?? 1.0,
              maxScaleFactor: scale?.scale ?? 1.0,
              child: connected
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Connected(
                            guardians:
                                ref.watch(seniorGuardiansProvider).value ??
                                const [],
                          ),
                          const SizedBox(height: 30),
                          const _Visibility(),
                        ],
                      ),
                    )
                  // **One screen, and no scrolling at all.** Photographed on a
                  // real Galaxy on 2026-10-31 with 연결하기 under the fold: a
                  // senior typed the number their child read out and found
                  // nothing to press. Three things made room - the red pad
                  // came down from 140 to 110, the field and 연결하기 share a
                  // row, and 자녀가 보는 것 waits until there is a family to
                  // see.
                  //
                  // What is left is fixed at the bottom and the top gives way:
                  // the half that tells them what to do shrinks to fit rather
                  // than pushing the field off the screen. It is 1:1 at every
                  // size but 제일 크게, and it is also what keeps the field in
                  // view when the keyboard comes up and takes half the height.
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Flexible(
                            child: LayoutBuilder(
                              // No alignment on the wrapper: one would make it
                              // fill the space and push the field to the
                              // bottom of the screen, away from the number.
                              builder: (context, box) => Container(
                                key: FamilyLinkKeys.top,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.topCenter,
                                  child: SizedBox(
                                    key: FamilyLinkKeys.topContent,
                                    width: box.maxWidth,
                                    child: const Column(
                                      children: [
                                        _WhyConnect(),
                                        SizedBox(height: 22),
                                        _ShowCode(),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Divider(
                            height: 2,
                            thickness: 2,
                            color: AppColors.seniorHairline,
                          ),
                          const SizedBox(height: 18),
                          _EnterCode(
                            controller: _code,
                            busy: _busy,
                            error: _error,
                            onSubmit: _enterCode,
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          // Questions only. An unread message is not one, and this screen is
          // one task long.
          const SeniorNoticeLayer(messages: false),
        ],
      ),
    );
  }
}

/// 자녀가 보는 것, under 연결되었어요.
class _Visibility extends StatelessWidget {
  const _Visibility();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // **자녀가 보는 것 lives here now.** It was a row in 설정 and 설정 had
        // to fit one screen without scrolling - the rule 사용법 has had from
        // the start and this one never did, with more than half the list
        // below the fold. This screen is where it belongs anyway: what the
        // children can see is about the family, and the question only has a
        // subject once there is one.
        SizedBox(
          key: FamilyLinkKeys.visibility,
          height: 84,
          child: ClayPad(
            light: AppColors.seniorButtonYellowLight,
            face: AppColors.seniorButtonYellow,
            deep: AppColors.seniorButtonYellowDeep,
            wall: AppColors.seniorButtonYellowWall,
            radius: 26,
            onTap: () => context.push(Routes.familyVisibility),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  // Yellow cannot hold white lettering, the same rule the
                  // 카카오톡 tile and the amber 가족 button follow.
                  Icon(
                    Icons.visibility_rounded,
                    size: 34,
                    color: AppColors.seniorInk,
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '자녀가 보는 것',
                            style: TextStyle(
                              fontSize: 23,
                              height: 1.2,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                              color: AppColors.seniorInk,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            '무엇이 전해지는지 누르세요',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: AppColors.seniorInk,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: 10),
                  Icon(
                    Icons.chevron_right,
                    size: 28,
                    color: AppColors.seniorInk,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 경로 B. The number is generated here and typed by the guardian.
class _ShowCode extends ConsumerStatefulWidget {
  const _ShowCode();

  @override
  ConsumerState<_ShowCode> createState() => _ShowCodeState();
}

class _ShowCodeState extends ConsumerState<_ShowCode> {
  Timer? _poll;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// While a code is on screen, ask every few seconds whether anyone has
  /// claimed it. A senior should see the screen change by itself rather than
  /// be asked to check — they have no way to know when their child finished
  /// typing.
  void _watchForGuardian() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) {
      ref.invalidate(seniorGuardiansProvider);
      // **And whether they are being asked to agree.** Since the consent
      // card exists, a claimed code does not attach a guardian - it raises a
      // question on this phone. Refreshing only the roster left this screen
      // spinning at a senior whose child had already typed the number.
      ref.invalidate(pendingGuardianLinkProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final pairing = ref.watch(seniorPairingControllerProvider);
    // **Started from the state, not from the tap.** Hanging it off the
    // button's handler meant one path set the timer and every other way of
    // arriving at a code - a rebuild, a code already in hand - set nothing,
    // and the senior was left looking at a number that never stopped being
    // a number.
    ref.listen(seniorPairingControllerProvider, (_, next) {
      if (next is AsyncData && next.value != null) _watchForGuardian();
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        switch (pairing) {
          AsyncData(value: final link?) => _Code(link: link),
          AsyncError() => const Text(
            '번호를 받지 못했어요.\n인터넷 연결을 확인해 주세요.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              height: 1.5,
              fontWeight: FontWeight.w700,
              color: AppColors.seniorInk,
            ),
          ),
          AsyncLoading() => const Center(child: CircularProgressIndicator()),
          // The one thing on this screen a senior can do on their own, so it
          // is the one that looks like the answer. Red and white rather than
          // the amber 가족 wears elsewhere: that amber sits at hue 36°, one
          // degree off the 카카오톡 tile, and its 95% value is the highest in
          // the palette — it reads as washed out beside everything else.
          _ => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                key: FamilyLinkKeys.showCode,
                // 112, down from 140, so everything down to 첫 화면으로 가기
                // fits one screen. Still more than half again the height of
                // 연결하기 (72), which is what keeps it reading as the answer
                // rather than as one of two.
                height: 112,
                child: ClayPad(
                  light: AppColors.seniorButtonRedLight,
                  face: AppColors.seniorButtonRed,
                  deep: AppColors.seniorButtonRedDeep,
                  wall: AppColors.seniorButtonRedWall,
                  radius: 30,
                  onTap: () => ref
                      .read(seniorPairingControllerProvider.notifier)
                      .showCode(),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.phone_iphone,
                            size: 30,
                            color: Colors.white,
                          ),
                          SizedBox(height: 6),
                          Text(
                            '번호 보여주기',
                            style: TextStyle(
                              fontSize: 30,
                              height: 1.1,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.8,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            '여기를 누르세요',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const _OneLine('자녀분이 이 번호를 넣으면 연결돼요', fontSize: 20),
            ],
          ),
        },
      ],
    );
  }
}

class _Code extends StatelessWidget {
  const _Code({required this.link});

  final PairLink link;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Where the red pad was, so the heading arrives with the number
        // rather than sitting over a button nobody has pressed yet.
        const _OneLine('자녀분에게 이 번호를 불러 주세요', fontSize: 22),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            link.code,
            key: FamilyLinkKeys.shownCode,
            style: const TextStyle(
              fontSize: 64,
              height: 1.1,
              letterSpacing: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.seniorInk,
            ),
          ),
        ),
        const SizedBox(height: 2),
        const _OneLine('이 번호는 10분 동안만 쓸 수 있어요', fontSize: 18),
      ],
    );
  }
}

/// A line that stays one line. Left to wrap, Korean breaks between syllables
/// and leaves the tail of a word alone underneath; this shrinks instead.
class _OneLine extends StatelessWidget {
  const _OneLine(this.text, {required this.fontSize});

  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: fontSize,
          height: 1.4,
          fontWeight: FontWeight.w700,
          color: AppColors.seniorInk,
        ),
      ),
    );
  }
}

/// 자녀와 연결하면 - why anybody would press the red pad, said before it.
///
/// Two boxes with a picture each rather than a paragraph: the first draft was
/// sentences, and a screen of sentences is the one thing this reader will not
/// read. The words are the owner's (2026-10-31). What a child can change is
/// the home buttons, which is what the second box says and all it says.
class _WhyConnect extends StatelessWidget {
  const _WhyConnect();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _OneLine('자녀와 연결하면', fontSize: 21),
        SizedBox(height: 10),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _WhyBox(
                  icon: Icons.chat_bubble_rounded,
                  lines: ['자녀와 쉽게', '문자를 주고받아요'],
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: _WhyBox(
                  icon: Icons.grid_view_rounded,
                  lines: ['자녀분이 쉽게 버튼을', '바꿔 드려요'],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 12),
        // The consent card is what makes this true, and saying it here means
        // the card is not a surprise when it arrives.
        _OneLine('어르신이 허락하셔야 연결돼요', fontSize: 18),
      ],
    );
  }
}

class _WhyBox extends StatelessWidget {
  const _WhyBox({required this.icon, required this.lines});

  final IconData icon;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.seniorWhyFace,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(color: AppColors.seniorWhyWall, offset: Offset(0, 5)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 34, color: AppColors.seniorWhyIcon),
            const SizedBox(height: 6),
            // Both lines in one box so they shrink together - fitted one at a
            // time, the longer line came out smaller than the line under it.
            // And held at 18px at every text size, so the two boxes match:
            // `자녀분이 쉽게 버튼을` is the widest line on the screen, and
            // grown with the rest it would be drawn smaller than the box
            // beside it.
            MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.0,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  children: [
                    for (final line in lines)
                      Text(
                        line,
                        maxLines: 1,
                        softWrap: false,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          height: 1.4,
                          fontWeight: FontWeight.w700,
                          color: AppColors.seniorInk,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Recovery, and the 경로 A fallback. One field for both — the senior was told
/// "type this number", not which kind of number it is.
class _EnterCode extends StatelessWidget {
  const _EnterCode({
    required this.controller,
    required this.busy,
    required this.error,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool busy;
  final String? error;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Dark and centred now, like everything else on this screen. It was
        // grey on purpose, to be quieter than the half above - and grey 19px
        // was read on a real phone as not there at all. Being smaller than
        // the red pad is quiet enough. `PairLink.codeMessage` quotes it, so
        // the guardian's text and this line change together.
        const _OneLine(enterCodeQuestion, fontSize: 22),
        const SizedBox(height: 12),
        // The field and 연결하기 share a row. Stacked, 연결하기 was the first
        // thing pushed under the fold; side by side it stays in view with the
        // field when the keyboard comes up.
        SizedBox(
          height: 72,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 12,
                // The digits are 32px already and the row is fixed: past 1.3
                // four of them stop fitting the width.
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.3,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      TextField(
                        key: FamilyLinkKeys.code,
                        controller: controller,
                        enabled: !busy,
                        // Fills the row exactly rather than sizing itself, so
                        // the field and 연결하기 are one height at every size.
                        expands: true,
                        maxLines: null,
                        textAlignVertical: TextAlignVertical.center,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        style: const TextStyle(
                          fontSize: 32,
                          letterSpacing: 8,
                          fontWeight: FontWeight.w700,
                          color: AppColors.seniorInk,
                        ),
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          filled: true,
                          fillColor: AppColors.seniorCodeField,
                          border: _codeBorder(AppColors.seniorInk),
                          enabledBorder: _codeBorder(AppColors.seniorInk),
                          focusedBorder: _codeBorder(AppColors.seniorPrimary),
                          disabledBorder: _codeBorder(AppColors.seniorInk),
                        ),
                      ),
                      // ① 번호 넣기, until something is typed. The owner's
                      // sentence - press the box, type the number, press
                      // 연결하기 - is said by the two numbers instead: three
                      // lines of instructions is what this reader skips.
                      // Drawn over the field rather than as its hint, which
                      // would scale with the digits and lose the badge.
                      IgnorePointer(
                        child: ListenableBuilder(
                          listenable: controller,
                          builder: (context, _) => controller.text.isEmpty
                              ? const Center(
                                  child: _Step(
                                    number: 1,
                                    label: '번호 넣기',
                                    ink: AppColors.seniorInk,
                                    badgeInk: AppColors.seniorCodeField,
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 10,
                child: SizedBox(
                  key: FamilyLinkKeys.submit,
                  child: ClayPad(
                    light: AppColors.seniorMoreLight,
                    face: AppColors.seniorMore,
                    deep: AppColors.seniorMoreDeep,
                    wall: AppColors.seniorMoreWall,
                    radius: 26,
                    onTap: busy ? null : onSubmit,
                    child: Center(
                      child: busy
                          ? const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 10),
                              child: _OneLineOn(
                                '연결하는 중이에요',
                                color: Colors.white,
                              ),
                            )
                          : const _Step(
                              number: 2,
                              label: '연결하기',
                              ink: Colors.white,
                              badgeInk: AppColors.seniorMoreDeep,
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (error case final message?) ...[
          const SizedBox(height: 16),
          Text(
            message,
            key: FamilyLinkKeys.message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 19,
              height: 1.5,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}

/// 가족과 연결되었어요, and the one thing only this phone can do about it.
///
/// **One child per row, each with its own 끊기.** A single 가족 연결을 끊기
/// that took everybody off was considered and refused: the person a mother
/// is cross with is usually one of them, and a button that cannot tell her
/// children apart makes her choose between all of them and none.
///
/// It is here because this is the screen about her family and the path is
/// already in 사용법. And it is the only place it can be: the server scopes
/// the removal to the profile whose **active device** is the caller, so a
/// guardian cannot do it from their own phone - which is the point, since
/// this is the one decision that is hers.
class _Connected extends ConsumerStatefulWidget {
  const _Connected({required this.guardians});

  final List<GuardianLink> guardians;

  @override
  ConsumerState<_Connected> createState() => _ConnectedState();
}

class _ConnectedState extends ConsumerState<_Connected> {
  bool _busy = false;

  Future<void> _remove(GuardianLink guardian) async {
    final name = guardian.displayName ?? '자녀분';
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: FamilyLinkKeys.removeConfirm,
        title: Text(
          '${gwaWa(name)} 연결을 끊을까요?',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        // **잃는 것이 없다는 말이 먼저.** The same rule the 사용하지 않기
        // dialog and the guardian's 로그아웃 both follow: a senior who reads
        // this as losing their buttons will never press it, and one who is
        // afraid of that will not ask.
        content: Text(
          '${iGa(name)} 이 폰을 볼 수 없게 됩니다.\n'
          '버튼과 글씨 크기는 그대로 있어요.\n'
          '나중에 다시 연결하실 수 있어요.',
          style: const TextStyle(fontSize: 19, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(
              '아니요, 그대로 둘게요',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            // Deliberately the quieter of the two, the same as the 네 that
            // hands back the home screen. What is being offered here is
            // giving something up, and a terracotta 네 beside a grey refusal
            // is the app leaning on somebody to take it.
            style: TextButton.styleFrom(
              foregroundColor: AppColors.seniorInkMuted,
            ),
            child: const Text(
              '네',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(seniorPairingControllerProvider.notifier)
          .removeGuardian(guardian.guardianAccountId);
    } on Object {
      // The link is still there and still on screen. Nothing to explain: a
      // senior cannot act on a failure to reach the server.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: FamilyLinkKeys.connected,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.check_circle,
          size: 72,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 20),
        const Text(
          '가족과 연결되었어요',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        const Text(
          '이제 자녀분이 이 폰의 화면을\n정리해 드릴 수 있어요',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, height: 1.6),
        ),
        const SizedBox(height: 26),
        Column(
          key: FamilyLinkKeys.guardians,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final guardian in widget.guardians)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        guardian.displayName ?? '자녀분',
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          color: AppColors.seniorInk,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => _remove(guardian),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.seniorInkMuted,
                      ),
                      child: const Text(
                        '연결 끊기',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// The question over the field. `PairLink.codeMessage` quotes it in the text
/// a guardian sends, so the parent can match the two by eye - which only
/// works while they are the same words.
const enterCodeQuestion = '자녀분이 번호를 주셨나요?';

OutlineInputBorder _codeBorder(Color color) => OutlineInputBorder(
  borderRadius: BorderRadius.circular(20),
  borderSide: BorderSide(color: color, width: 3),
);

/// ① 번호 넣기 / ② 연결하기: the order, said by a number in a disc.
class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.label,
    required this.ink,
    required this.badgeInk,
  });

  final int number;
  final String label;
  final Color ink;
  final Color badgeInk;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: ink, shape: BoxShape.circle),
              child: Text(
                '$number',
                style: TextStyle(
                  fontSize: 18,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  color: badgeInk,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.4,
                color: ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OneLineOn extends StatelessWidget {
  const _OneLineOn(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }
}
