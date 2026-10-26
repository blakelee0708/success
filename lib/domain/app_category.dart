import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Visual category for a launcher tile. Drives the clay gradient + icon.
/// Colors come verbatim from `design-reference/see/launcher.jsx` APPS.
///
/// 사람 takes 가족's amber rather than a colour of its own. A new one was
/// tried and there is nowhere to put it: the warm band is already at 13°
/// (영상), 32° (더 보기), 36° (가족) and 37° (카카오톡), and anything that fits
/// between them is indistinguishable from its neighbours at arm's length.
/// Sharing the amber is also the honest reading — 가족 버튼 and a person
/// button mean the same thing, and the icon and the name are what tell one
/// person from another.
/// `contact` is not an app. It is a person — 딸 영희, 남편, 주치의 — and the
/// button dials the number the guardian typed instead of opening anything.
/// Seniors fail at *finding people* far more often than at finding apps:
/// opening 연락처 and scrolling is where they give up.
enum AppCategory { phone, message, kakao, youtube, camera, gallery, contact }

extension AppCategoryStyle on AppCategory {
  /// Darker gradient stop (c2 in launcher.jsx).
  Color get baseColor => switch (this) {
    AppCategory.phone => AppColors.seniorButtonGreen,
    AppCategory.message => AppColors.seniorButtonBlue,
    AppCategory.kakao => AppColors.seniorButtonYellow,
    AppCategory.youtube => AppColors.seniorButtonRed,
    AppCategory.camera => AppColors.seniorButtonPurple,
    AppCategory.gallery => AppColors.seniorButtonPink,
    AppCategory.contact => AppColors.seniorFamily,
  };

  /// Lit top of the face.
  Color get lightColor => switch (this) {
    AppCategory.phone => AppColors.seniorButtonGreenLight,
    AppCategory.message => AppColors.seniorButtonBlueLight,
    AppCategory.kakao => AppColors.seniorButtonYellowLight,
    AppCategory.youtube => AppColors.seniorButtonRedLight,
    AppCategory.camera => AppColors.seniorButtonPurpleLight,
    AppCategory.gallery => AppColors.seniorButtonPinkLight,
    AppCategory.contact => AppColors.seniorFamilyLight,
  };

  /// Shaded foot of the face, where it turns away from the light.
  Color get deepColor => switch (this) {
    AppCategory.phone => AppColors.seniorButtonGreenDeep,
    AppCategory.message => AppColors.seniorButtonBlueDeep,
    AppCategory.kakao => AppColors.seniorButtonYellowDeep,
    AppCategory.youtube => AppColors.seniorButtonRedDeep,
    AppCategory.camera => AppColors.seniorButtonPurpleDeep,
    AppCategory.gallery => AppColors.seniorButtonPinkDeep,
    AppCategory.contact => AppColors.seniorFamilyDeep,
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
    AppCategory.contact => AppColors.seniorFamilyWall,
  };

  /// What the icon and the label are drawn in.
  ///
  /// White on every face but the yellow one, which is too light to carry it —
  /// 카카오톡 sat at 2.4:1 against white and would have shipped looking washed
  /// out. A yellow face takes ink, exactly as the 가족 button does.
  /// 사람 shares 가족's amber for the same reason it shares its meaning, and
  /// inherits the same constraint: that amber cannot hold white either.
  Color get letteringColor =>
      this == AppCategory.kakao || this == AppCategory.contact
      ? AppColors.seniorInk
      : Colors.white;

  /// True for a button that dials a number rather than opening an app.
  bool get isContact => this == AppCategory.contact;

  /// What a button of this kind is called when it is first made.
  ///
  /// Adding a button used to hard-code `AppCategory.message` on both sides,
  /// so a button called 딸 came out blue, wore the 문자 icon and opened the
  /// messaging app. The kind is chosen now, and this is what it suggests.
  String get defaultLabel => switch (this) {
    AppCategory.phone => '전화',
    AppCategory.message => '문자',
    AppCategory.kakao => '카카오톡',
    AppCategory.youtube => '영상 보기',
    AppCategory.camera => '사진찍기',
    AppCategory.gallery => '사진 보기',
    AppCategory.contact => '가족',
  };

  /// Nearest Material glyph to the launcher.jsx custom icon.
  IconData get icon => switch (this) {
    AppCategory.phone => Icons.call,
    AppCategory.message => Icons.sms,
    AppCategory.kakao => Icons.chat_bubble,
    AppCategory.youtube => Icons.smart_display,
    AppCategory.camera => Icons.photo_camera,
    AppCategory.gallery => Icons.photo_library,
    AppCategory.contact => Icons.person_rounded,
  };
}
