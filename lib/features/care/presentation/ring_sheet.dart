import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/remote/ring_repository.dart';
import '../../guardian/application/guardian_home_apps_controller.dart';
import '../../guardian/presentation/widgets/guardian_surfaces.dart';
import '../application/guardian_ring_controller.dart';

/// Where a guardian makes their parent's phone loud, and says why.
///
/// The message is not an extra. `request_phone_ring` substitutes
/// `전화 한 번만 주세요.` for a blank, so the parent is never shouted at by a
/// phone with nothing to say — but the guardian's own words are better than
/// any default, and the three chips exist because somebody worried enough to
/// open this is not in the mood to compose.
class RingSheet extends ConsumerStatefulWidget {
  const RingSheet({super.key});

  static const sheetKey = Key('ring-sheet');
  static const fieldKey = Key('ring-sheet-field');
  static const sendKey = Key('ring-sheet-send');
  static const resultKey = Key('ring-sheet-result');

  /// The chips. Short because they are read at a glance and because each has
  /// to fit one line of a 72px pill.
  ///
  /// The first is the whole feature in five syllables and is what the server
  /// falls back to anyway. The other two are the two reasons a child rings a
  /// parent who is not picking up.
  static const phrases = <String>[
    '전화 한 번만 주세요.',
    '어디세요?',
    '괜찮으세요?',
  ];

  static Future<void> open(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const RingSheet(key: RingSheet.sheetKey),
    );
  }

  @override
  ConsumerState<RingSheet> createState() => _RingSheetState();
}

class _RingSheetState extends ConsumerState<RingSheet> {
  final _message = TextEditingController();

  @override
  void initState() {
    super.initState();
    // A result from the last time this was opened is not the first thing to
    // read now. Deferred because the sheet is being built as this runs.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(guardianRingControllerProvider.notifier).reset();
    });
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(guardianRingControllerProvider);
    final name = ref.watch(selectedSeniorProfileProvider)?.displayName;
    final sending = state is RingSending;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${name ?? '부모님'} 폰을 울릴까요',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: AppColors.guardianInk,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '무음이어도 알람 소리로 울립니다. 60초 뒤에 저절로 꺼져요.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: AppColors.guardianInkFaint,
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final phrase in RingSheet.phrases)
                      _Chip(
                        label: phrase,
                        // Replaces rather than appends: these are whole
                        // messages, not words to build one out of, and a
                        // guardian who taps two in a row meant the second.
                        onTap: sending
                            ? null
                            : () => setState(() {
                                _message.text = phrase;
                              }),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  key: RingSheet.fieldKey,
                  controller: _message,
                  enabled: !sending,
                  maxLength: 60,
                  maxLines: 2,
                  minLines: 2,
                  textInputAction: TextInputAction.newline,
                  // Named, because this is the one colour on the sheet that
                  // is not. Everything else here is an explicit value -
                  // `guardianField`'s borders, the chips, the button - and
                  // the cursor was the single thing left reading the theme,
                  // which drew it terracotta. Wrapping the sheet in
                  // `Theme(data: AppTheme.guardian)` was tried first and
                  // changed nothing: the rendered PNG came back
                  // byte-identical, so the wrap was removed rather than kept
                  // as a comment claiming a fix it did not make.
                  cursorColor: AppColors.guardianPrimary,
                  decoration: guardianField(
                    label: '하실 말씀',
                    hint: '비워 두면 전화 한 번만 주세요 라고 전해집니다',
                  ),
                ),
                const SizedBox(height: 4),
                GuardianPrimaryButton(
                  key: RingSheet.sendKey,
                  label: sending ? '보내는 중' : '울리기',
                  icon: Icons.volume_up_rounded,
                  onPressed: sending
                      ? null
                      : () => ref
                            .read(guardianRingControllerProvider.notifier)
                            .send(_message.text),
                ),
                if (state is RingSettled) ...[
                  const SizedBox(height: 14),
                  _Result(outcome: state.outcome),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.guardianTintBlue,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.guardianTintBlueInk,
            ),
          ),
        ),
      ),
    );
  }
}

/// What came back, in one sentence the guardian can act on.
///
/// Four different sentences rather than 보냈어요 for all of them. The one
/// that matters most is [RingSenderDown]: it is the only one that is nobody's
/// phone being off, and the only one worth telling the owner about.
class _Result extends StatelessWidget {
  const _Result({required this.outcome});

  final RingOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final (text, good) = switch (outcome) {
      RingSent() => ('울렸어요. 부모님 폰에서 소리가 납니다.', true),
      RingMissed(miss: RingMiss.neverConnected) => (
        '부모님 폰이 아직 연결되기 전이에요.',
        false,
      ),
      RingMissed() => (
        '부모님 폰에 닿지 않았어요. 폰이 꺼져 있을 수 있어요.',
        false,
      ),
      RingRefused(:final message) => (message, false),
      RingSenderDown() => (
        '지금은 보낼 수 없어요. 잠시 후에 다시 해 주세요.',
        false,
      ),
    };

    return Container(
      key: RingSheet.resultKey,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: good
            ? AppColors.guardianTintGreen
            : AppColors.guardianTintAmber,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            good ? Icons.check_circle_rounded : Icons.info_rounded,
            size: 18,
            color: good
                ? AppColors.guardianTintGreenInk
                : AppColors.guardianTintAmberInk,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.45,
                fontWeight: FontWeight.w700,
                color: good
                    ? AppColors.guardianTintGreenInk
                    : AppColors.guardianTintAmberInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
