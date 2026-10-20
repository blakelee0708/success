import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/clay_pad.dart';
import '../../../../domain/app_category.dart';

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
Future<AppCategory?> askForCategory(BuildContext context) =>
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
              for (final category in AppCategory.values)
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
      label: category.defaultLabel,
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
                  category.defaultLabel,
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
