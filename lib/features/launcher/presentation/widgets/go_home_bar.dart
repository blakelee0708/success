import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/theme/app_colors.dart';

/// The way out of every screen a senior can reach, written as a word.
///
/// The `←` in the top-left corner was the only exit on five of these screens,
/// and it is the worst arrangement usability work on older adults describes:
/// they navigate by content rather than by menus and buttons, and the
/// assisted buttons around the corners are the ones they are measured *not
/// noticing at all*. On top of that it is a symbol rather than a word, and an
/// icon whose meaning is distant from its function is the other thing those
/// studies single out.
///
/// 앱 설정 reached this conclusion on its own and grew a 첫 화면으로 가기 at
/// the bottom. This is that button, shared, so the other screens stop being
/// the ones where a senior gets stuck.
///
/// **It goes all the way home, not back one screen.** Several of these
/// screens have more than one way in - 설정 and the hollow slot both reach
/// 앱 설정, 설정 and the home both reach the conversation - so popping leaves
/// half the visitors standing somewhere they did not come from, with another
/// exit to find. Going home is also what makes the label true.
class GoHomeBar extends StatelessWidget {
  const GoHomeBar({super.key, this.note});

  static const buttonKey = Key('go-home');

  /// An optional line under the button. 앱 설정 uses it to say the change has
  /// already been saved, so the button cannot be read as 저장.
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: buttonKey,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.seniorPrimary,
                minimumSize: const Size.fromHeight(68),
              ),
              onPressed: () => context.go(Routes.firstScreen),
              child: const Text(
                '첫 화면으로 가기',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              ),
            ),
          ),
          if (note != null) ...[
            const SizedBox(height: 10),
            Text(
              note!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.seniorInkMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
