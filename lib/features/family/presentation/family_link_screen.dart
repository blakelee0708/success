import '../../launcher/presentation/widgets/go_home_bar.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
  static const shownCode = Key('family-link-shown-code');
  static const code = Key('family-link-code');
  static const submit = Key('family-link-submit');
  static const message = Key('family-link-message');
  static const connected = Key('family-link-connected');
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              child: MediaQuery.withClampedTextScaling(
                // Raising the text size is the point of this app, so the code and
                // the field grow with it rather than being pinned small.
                minScaleFactor: scale?.scale ?? 1.0,
                maxScaleFactor: scale?.scale ?? 1.0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (connected)
                      const _Connected()
                    else ...[
                      const _ShowCode(),
                      const SizedBox(height: 34),
                      const Divider(
                        height: 2,
                        thickness: 2,
                        color: AppColors.seniorHairline,
                      ),
                      const SizedBox(height: 26),
                      _EnterCode(
                        controller: _code,
                        busy: _busy,
                        error: _error,
                        onSubmit: _enterCode,
                      ),
                    ],
                    const SizedBox(height: 30),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
        const Text(
          '자녀분에게\n이 번호를 불러 주세요',
          style: TextStyle(
            fontSize: 25,
            height: 1.4,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.6,
            color: AppColors.seniorInk,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          '자녀분이 그 번호를 넣으면 연결됩니다.',
          style: TextStyle(
            fontSize: 18,
            height: 1.5,
            color: AppColors.seniorInkMuted,
          ),
        ),
        const SizedBox(height: 20),
        switch (pairing) {
          AsyncData(value: final link?) => _Code(link: link),
          AsyncError() => const Text(
            '번호를 받지 못했어요. 인터넷 연결을 확인해 주세요.',
            style: TextStyle(fontSize: 18, height: 1.5),
          ),
          AsyncLoading() => const Center(child: CircularProgressIndicator()),
          // The one thing on this screen a senior can do on their own, so it
          // is the one that looks like the answer. Red and white rather than
          // the amber 가족 wears elsewhere: that amber sits at hue 36°, one
          // degree off the 카카오톡 tile, and its 95% value is the highest in
          // the palette — it reads as washed out beside everything else.
          _ => SizedBox(
            key: FamilyLinkKeys.showCode,
            height: 140,
            child: ClayPad(
              light: AppColors.seniorButtonRedLight,
              face: AppColors.seniorButtonRed,
              deep: AppColors.seniorButtonRedDeep,
              wall: AppColors.seniorButtonRedWall,
              radius: 30,
              onTap: () =>
                  ref.read(seniorPairingControllerProvider.notifier).showCode(),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.phone_iphone, size: 40, color: Colors.white),
                      SizedBox(height: 10),
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
        // Scales down rather than clipping: four wide-tracked digits overflow a
        // narrow phone at 아주 크게 otherwise.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            link.code,
            key: FamilyLinkKeys.shownCode,
            style: const TextStyle(
              fontSize: 64,
              letterSpacing: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 14),
        // **A number alone reads as a dead end.** The phone is asking the
        // server every three seconds whether the child has typed it, and
        // nothing on screen said so - so the senior waited, decided it was
        // broken, and pressed 가족 연결 again. The spinner is the whole
        // message: something is happening and you do not have to do it.
        Row(
          key: FamilyLinkKeys.waiting,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.6),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                '자녀분이 번호를 넣으면\n바로 연결돼요',
                style: TextStyle(
                  fontSize: 18,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // Saying it expires is the difference between a number that stopped
        // working and a phone that seems broken.
        const Text(
          '이 번호는 10분 동안만 쓸 수 있어요',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 17, height: 1.5),
        ),
      ],
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
        // Quieter than the half above on purpose. This one cannot be done at
        // all without a number already in hand, so it is a question for the
        // few it applies to rather than a second choice for everyone.
        const Text(
          '자녀분이 먼저 번호를 알려 주셨나요?',
          style: TextStyle(
            fontSize: 19,
            height: 1.5,
            fontWeight: FontWeight.w700,
            color: AppColors.seniorInkMuted,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          key: FamilyLinkKeys.code,
          controller: controller,
          enabled: !busy,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          style: const TextStyle(
            fontSize: 32,
            letterSpacing: 8,
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.seniorSlotFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(
                color: AppColors.seniorSlotBorder,
                width: 2.5,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(
                color: AppColors.seniorSlotBorder,
                width: 2.5,
              ),
            ),
          ),
        ),
        if (error case final message?) ...[
          const SizedBox(height: 16),
          Text(
            message,
            key: FamilyLinkKeys.message,
            style: TextStyle(
              fontSize: 18,
              height: 1.5,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          key: FamilyLinkKeys.submit,
          height: 72,
          child: ClayPad(
            light: AppColors.seniorMoreLight,
            face: AppColors.seniorMore,
            deep: AppColors.seniorMoreDeep,
            wall: AppColors.seniorMoreWall,
            radius: 26,
            onTap: busy ? null : onSubmit,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  busy ? '연결하는 중이에요' : '연결하기',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Connected extends StatelessWidget {
  const _Connected();

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
      ],
    );
  }
}
