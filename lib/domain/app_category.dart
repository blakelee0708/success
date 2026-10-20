import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Visual category for a launcher tile. Drives the clay gradient + icon.
/// Colors come verbatim from `design-reference/see/launcher.jsx` APPS.
enum AppCategory { phone, message, kakao, youtube, camera, gallery }

extension AppCategoryStyle on AppCategory {
  /// Darker gradient stop (c2 in launcher.jsx).
  Color get baseColor => switch (this) {
    AppCategory.phone => AppColors.seniorButtonGreen,
    AppCategory.message => AppColors.seniorButtonBlue,
    AppCategory.kakao => AppColors.seniorButtonYellow,
    AppCategory.youtube => AppColors.seniorButtonRed,
    AppCategory.camera => AppColors.seniorButtonPurple,
    AppCategory.gallery => AppColors.seniorButtonPink,
  };

  /// Lit top of the face.
  Color get lightColor => switch (this) {
    AppCategory.phone => AppColors.seniorButtonGreenLight,
    AppCategory.message => AppColors.seniorButtonBlueLight,
    AppCategory.kakao => AppColors.seniorButtonYellowLight,
    AppCategory.youtube => AppColors.seniorButtonRedLight,
    AppCategory.camera => AppColors.seniorButtonPurpleLight,
    AppCategory.gallery => AppColors.seniorButtonPinkLight,
  };

  /// Shaded foot of the face, where it turns away from the light.
  Color get deepColor => switch (this) {
    AppCategory.phone => AppColors.seniorButtonGreenDeep,
    AppCategory.message => AppColors.seniorButtonBlueDeep,
    AppCategory.kakao => AppColors.seniorButtonYellowDeep,
    AppCategory.youtube => AppColors.seniorButtonRedDeep,
    AppCategory.camera => AppColors.seniorButtonPurpleDeep,
    AppCategory.gallery => AppColors.seniorButtonPinkDeep,
  };

  /// The side wall the tile stands on — the thing that makes it an object
  /// rather than a rectangle. Always the darkest of the four.
  Color get wallColor => switch (this) {
    AppCategory.phone => AppColors.seniorButtonGreenWall,
    AppCategory.message => AppColors.seniorButtonBlueWall,
    AppCategory.kakao => AppColors.seniorButtonYellowWall,
    AppCategory.youtube => AppColors.seniorButtonRedWall,
    AppCategory.camera => AppColors.seniorButtonPurpleWall,
    AppCategory.gallery => AppColors.seniorButtonPinkWall,
  };

  /// What the icon and the label are drawn in.
  ///
  /// White on every face but the yellow one, which is too light to carry it —
  /// 카카오톡 sat at 2.4:1 against white and would have shipped looking washed
  /// out. A yellow face takes ink, exactly as the 가족 button does.
  Color get letteringColor =>
      this == AppCategory.kakao ? AppColors.seniorInk : Colors.white;

  /// Nearest Material glyph to the launcher.jsx custom icon.
  IconData get icon => switch (this) {
    AppCategory.phone => Icons.call,
    AppCategory.message => Icons.sms,
    AppCategory.kakao => Icons.chat_bubble,
    AppCategory.youtube => Icons.smart_display,
    AppCategory.camera => Icons.photo_camera,
    AppCategory.gallery => Icons.photo_library,
  };
}
