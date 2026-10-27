import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/clay_pad.dart';
import '../../../../domain/app_category.dart';
import '../../../../domain/launcher_app.dart';

/// Keys the tests drive.
class CategoryPickerKeys {
  CategoryPickerKeys._();

  static const sheet = Key('category-picker');

  static Key option(AppCategory category) =>
      Key('category-picker-${category.name}');
}

/// Asks which kind of button is being added, before asking what to call it.
///
/// Both sides used to hard-code `AppCategory.message`, so a button called 딸
/// came out blue, wore the 문자 icon and opened the messaging app when the
/// senior pressed it. The kind decides all three, so it cannot be guessed.
///
/// Drawn as the tiles themselves rather than as a list of names: the senior,
/// or the son choosing on their behalf, is picking the thing they are about
/// to see on the home screen.
/// Kinds the home screen already holds are left out, unless they are
/// [AppCategoryStyle.repeatable].
///
/// Offering 전화 to a screen that already has 전화 is offering a second
/// button that opens the same app — a duplicate the senior cannot tell from
/// the first, on the one screen they cannot fix themselves. 사람 and 폰에
/// 있는 앱 stay, because a family has several people and a phone has eighty
/// apps.
///
/// [offer] is what the caller can actually follow through on.
///
/// The guardian's half passes a list without [AppCategory.installed]: picking
/// an app on the parent's phone means **reading the list of apps on the
/// parent's phone**, and that list is deliberately never sent off it. Showing
/// the option there would be offering something the next screen cannot do.
/// The three fixed slots are never offered. 가족, 소리 and 인터넷 each have a
/// place of their own on both home screens, there is exactly one of each, and
/// the senior did not put it there - so adding one is not a thing to offer.
/// They are still ordinary saved buttons, which is how the family renames and
/// recolours them.
final addableCategories = [
  for (final c in AppCategory.values) if (!c.fixedSlot) c,
];

Future<AppCategory?> askForCategory(
  BuildContext context, {
  List<AppCategory>? offer,
  List<LauncherApp> alreadyOn = const [],
}) =>
    showDialog<AppCategory>(
      context: context,
      builder: (context) => AlertDialog(
        key: CategoryPickerKeys.sheet,
        backgroundColor: AppColors.seniorSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: const Text(
          '어떤 버튼인가요?',
          style: TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
            color: AppColors.seniorInk,
          ),
        ),
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 12, 6),
        content: SizedBox(
          width: 320,
          child: GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.9,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final category in (offer ?? addableCategories))
                if (category.repeatable ||
                    !alreadyOn.any((a) => a.category == category))
                  _Option(category: category),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              '그만두기',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: AppColors.seniorInkMuted,
              ),
            ),
          ),
        ],
      ),
    );

class _Option extends StatelessWidget {
  const _Option({required this.category});

  final AppCategory category;

  @override
  Widget build(BuildContext context) {
    final ink = category.letteringColor;
    return Semantics(
      button: true,
      label: category.pickerLabel,
      child: ClayPad(
        key: CategoryPickerKeys.option(category),
        light: category.lightColor,
        face: category.baseColor,
        deep: category.deepColor,
        wall: category.wallColor,
        radius: 22,
        wallHeight: 6,
        onTap: () => Navigator.pop(context, category),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(category.icon, size: 26, color: ink),
                const SizedBox(width: 9),
                Text(
                  category.pickerLabel,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                    color: ink,
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
