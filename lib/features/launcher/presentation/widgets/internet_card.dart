import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/clay_pad.dart';
import '../../../../domain/internet_status.dart';
import '../../data/phone_controls.dart';

/// What the phone is on, asked when the card opens.
///
/// A provider rather than a field so the card can be opened twice and get a
/// fresh answer: a senior who turns Wi-Fi on and comes back expects the card
/// to have noticed.
final internetStatusProvider = FutureProvider<InternetStatus>(
  (ref) => ref.read(phoneControlsProvider).internetStatus(),
);

class InternetCardKeys {
  const InternetCardKeys._();

  static const card = Key('internet-card');
  static const wifi = Key('internet-card-wifi');
  static const data = Key('internet-card-data');
  static const close = Key('internet-card-close');
}

/// 인터넷, and what it can honestly do.
///
/// **The app cannot switch either one.** `setWifiEnabled` has been a no-op
/// for ordinary apps since Android 10 and mobile data needs carrier
/// privileges. So this says what is happening and opens the one settings
/// screen the senior needs, and that is the whole of it.
///
/// **Wi-Fi and mobile data are two doors, and that was learnt from a
/// photograph of a real Galaxy.** The card this replaces announced a system
/// sheet carrying both; what arrived was Settings > 연결, where Wi-Fi is a
/// switch at the top and mobile data is not on the screen at all - two taps
/// further in, behind 모바일 네트워크 or 데이터 사용. A senior sent there to
/// turn their data on never finds it. So the choosing happens here, in words,
/// and the phone is handed exactly one job.
///
/// **It claims nothing it cannot see.** A phone that will not say what it is
/// on gets the card with both doors and no sentence about being connected -
/// the same card an unknown answer would produce anyway.
Future<void> openInternetCard(BuildContext context, WidgetRef ref) {
  // Fresh every time. The common path through this card is turn something on
  // and come back.
  ref.invalidate(internetStatusProvider);
  return showDialog<void>(
    context: context,
    builder: (_) => const _InternetCard(),
  );
}

class _InternetCard extends ConsumerWidget {
  const _InternetCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Never awaited. A channel that does not answer throws nothing at all, so
    // the card draws its both-doors form while the question is outstanding
    // rather than holding a senior on a spinner - the rule this codebase has
    // now written down five times.
    final status =
        ref.watch(internetStatusProvider).value ?? InternetStatus.unknown;

    return AlertDialog(
      key: InternetCardKeys.card,
      backgroundColor: AppColors.seniorSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(24, 26, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      title: Text(
        _headline(status),
        style: const TextStyle(
          fontSize: 24,
          height: 1.4,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.5,
          color: AppColors.seniorInk,
        ),
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Wi-Fi first in every case. It is the one a senior is most often
          // sent to turn on, and the only one that is a single switch at the
          // top of the screen it opens.
          if (status != InternetStatus.wifi)
            _Door(
              doorKey: InternetCardKeys.wifi,
              label: '와이파이 켜러 가기',
              icon: Icons.wifi_rounded,
              onTap: () => _go(
                context,
                ref.read(phoneControlsProvider).openWifiSettings(),
              ),
            ),
          if (status != InternetStatus.wifi && status != InternetStatus.mobile)
            const SizedBox(height: 10),
          if (status != InternetStatus.mobile)
            _Door(
              doorKey: InternetCardKeys.data,
              label: '데이터 켜러 가기',
              icon: Icons.signal_cellular_alt_rounded,
              onTap: () => _go(
                context,
                ref.read(phoneControlsProvider).openMobileDataSettings(),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            _footnote(status),
            style: const TextStyle(
              fontSize: 17,
              height: 1.45,
              fontWeight: FontWeight.w500,
              color: AppColors.seniorInkMuted,
            ),
          ),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      actions: [
        TextButton(
          key: InternetCardKeys.close,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            '닫기',
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              color: AppColors.seniorInkMuted,
            ),
          ),
        ),
      ],
    );
  }

  /// Told, never awaited, and the card closes on its own answer rather than
  /// the phone's.
  void _go(BuildContext context, Future<bool> opening) {
    unawaited(opening);
    Navigator.of(context).pop();
  }

  /// Every line is a whole line: at 24px in this card that is about twelve
  /// glyphs, so each is two short lines rather than one that wraps and leaves
  /// a syllable alone.
  static String _headline(InternetStatus status) => switch (status) {
    InternetStatus.wifi => '와이파이로\n잘 되고 있어요',
    InternetStatus.mobile => '데이터로\n잘 되고 있어요',
    InternetStatus.other => '인터넷이\n되고 있어요',
    InternetStatus.none => '인터넷이\n꺼져 있어요',
    // No claim either way. The phone did not say and neither do we.
    InternetStatus.unknown => '인터넷을\n켤 수 있어요',
  };

  static String _footnote(InternetStatus status) => switch (status) {
    // Already connected, so the door below is for changing rather than
    // fixing - and the reason to change is money.
    InternetStatus.wifi => '데이터로 바꾸시면 요금이 나갈 수 있어요.',
    InternetStatus.mobile => '집에서는 와이파이로 바꾸시면 요금이 안 나가요.',
    _ => '누르시면 폰 화면이 하나 나와요.\n다 하시면 뒤로 가기를 눌러 주세요.',
  };
}

/// One of the two doors.
class _Door extends StatelessWidget {
  const _Door({
    required this.doorKey,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final Key doorKey;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 74,
      child: ClayPad(
        key: doorKey,
        light: AppColors.seniorMoreLight,
        face: AppColors.seniorMore,
        deep: AppColors.seniorMoreDeep,
        wall: AppColors.seniorMoreWall,
        radius: 20,
        onTap: onTap,
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 28, color: Colors.white),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
