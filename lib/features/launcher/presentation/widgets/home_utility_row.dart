import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../domain/device_status.dart';
import '../../../../domain/app_category.dart';
import '../../../../domain/senior_settings.dart';
import '../../application/senior_settings_controller.dart';
import '../../application/ringer_controller.dart';
import 'internet_card.dart';
import 'home_pill.dart';

/// 소리 and 인터넷, on both home screens, under the tiles.
///
/// **They are deliberately not tiles.** Every app button on these screens is
/// an icon above a label in a category colour; these are an icon *beside* a
/// label, at well under half the height.
///
/// The sand is `seniorUtility`, and three colours were tried before it.
/// Near-white vanished into the ground. Brown is 더 보기's and 설정's, which
/// says the right thing but is a dark low-chroma colour, and an ageing eye
/// loses exactly that first. Terracotta was the most visible of the four and
/// the worst idea: it is already 영상 보기's and 긴급 구조 요청's, so a second
/// red bar on the same screen is one a senior may press in a hurry thinking
/// it is the SOS they were taught to reach for. A senior reads the
/// difference before they read the words, which matters because pressing one
/// of these does not open anything - it changes the phone, or it hands them
/// over to a screen the phone drew. A thing that behaves differently should
/// not be dressed as the things around it.
///
/// The shape is also what makes them affordable. 자세한 화면 is eight cells
/// at 108px rows with one empty slot: two more tiles would have made it 2x5,
/// dropped the rows to about 85px, and broken the 44px-icon-over-a-label
/// floor at 아주 크게 - silently, because every tile is a `FittedBox` and
/// nothing throws when this breaks. Lying down, the pair costs a little over
/// half a tile row. `home_fits_test` is what actually settles that.
class HomeUtilityRow extends ConsumerWidget {
  const HomeUtilityRow({super.key});

  /// 48, and the number is not a taste.
  ///
  /// 자세한 화면 had exactly 68px of slack between the grid's floor and the
  /// band's full height - measured, not guessed. The first attempt took 70
  /// and `home_fits_test` failed by **2 pixels**: the band dropped to its
  /// 110px floor and drew at 0.47 scale, which would have put the clock on
  /// that screen at half the size of the one next door. Nothing overflowed
  /// and nothing threw, which is how this file's three predecessors shipped.
  ///
  /// 48 plus the 10px gap leaves 10px in hand. 정말 쉬운 화면 has 88 to spare
  /// and could carry a taller pill, but one size across both screens is worth
  /// more than a few pixels: the two homes reading as two different apps is a
  /// fault this project has already fixed once.
  static const height = 48.0;

  /// The gap above it. Smaller than `HomeBody.sectionGap` because these
  /// belong with the tiles they sit under, not with the 가족 row below.
  static const gapAbove = 10.0;

  static const soundKey = Key('home-utility-sound');
  static const internetKey = Key('home-utility-internet');

  /// Whether this row has anything to draw. Both buttons gone and the row
  /// takes no height at all, rather than leaving a 48px band of nothing where
  /// they used to be.
  static bool visibleFor(SeniorSettings settings) =>
      settings.slot(AppCategory.sound) != null ||
      settings.slot(AppCategory.internet) != null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ringer = ref.watch(ringerControllerProvider);
    // The senior's own words and colours. They are ordinary saved buttons,
    // which is how the family can rename and recolour them from either phone;
    // what keeps them out of the grid is `fixedSlot`.
    final settings =
        ref.watch(seniorSettingsControllerProvider).value ??
        const SeniorSettings();
    // Null when the family took it off. One gone leaves the other the whole
    // width at the same small height; both gone and `HomeBody` draws no row
    // at all, which is what `visibleFor` answers.
    final soundButton = settings.slot(AppCategory.sound);
    final internetButton = settings.slot(AppCategory.internet);
    return Row(
      children: [
        if (soundButton case final sound?)
          Expanded(
            child: HomePill(
              key: soundKey,
              // Null is *this phone has not said yet*, never 무음. Under
              // `flutter test` the channel never answers at all, and a button
              // claiming the ringer is off when nobody asked is the same
              // fabrication as a battery reading of 0%.
              // The state is appended to whatever they called it, so a button
              // renamed 벨소리 still says which way it is set.
              label: switch (ringer) {
                RingerMode.normal => '${sound.label} 켜짐',
                RingerMode.vibrate => '진동',
                RingerMode.silent => '${sound.label} 꺼짐',
                null => sound.label,
              },
              // Null gets the speaker too, because the label beside it is the
              // neutral 소리 and the icon must not contradict it. A vibration
              // glyph there claims a state nobody has reported yet - the same
              // fabrication as a battery reading of 0%, in a smaller space.
              icon: switch (ringer) {
                RingerMode.vibrate => Icons.vibration_rounded,
                RingerMode.silent => Icons.volume_off_rounded,
                RingerMode.normal || null => Icons.volume_up_rounded,
              },
              light: sound.lightColor,
              face: sound.baseColor,
              deep: sound.deepColor,
              wall: sound.wallColor,
              ink: sound.letteringColor,
              sheen: 0.4,
              height: height,
              iconSize: 21,
              fontSize: 17,
              onTap: () => _toggleSound(context, ref),
            ),
          ),
        if (soundButton != null && internetButton != null)
          const SizedBox(width: 12),
        if (internetButton case final internet?)
          Expanded(
            child: HomePill(
              key: internetKey,
              label: internet.label,
              icon: internet.category.icon,
              light: internet.lightColor,
              face: internet.baseColor,
              deep: internet.deepColor,
              wall: internet.wallColor,
              ink: internet.letteringColor,
              sheen: 0.4,
              height: height,
              iconSize: 21,
              fontSize: 17,
              onTap: () => openInternetCard(context, ref),
            ),
          ),
      ],
    );
  }

  Future<void> _toggleSound(BuildContext context, WidgetRef ref) async {
    final ok = await ref.read(ringerControllerProvider.notifier).toggle();
    if (ok || !context.mounted) return;
    // Do Not Disturb can take the call and leave the ringer where it was.
    // Saying nothing would leave a senior pressing a button that does
    // nothing, on the screen they came to because the phone already seemed
    // broken.
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('ringer-refused'),
        backgroundColor: AppColors.seniorSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: const Text(
          '지금은 폰이 바꾸지 못하게 해 두었어요.\n\n'
          '폰 설정에서 방해 금지를 끄시면\n다시 바꾸실 수 있어요.',
          style: TextStyle(
            fontSize: 19,
            height: 1.5,
            fontWeight: FontWeight.w700,
            color: AppColors.seniorInk,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(
              '알겠어요',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppColors.seniorPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
