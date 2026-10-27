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
enum AppCategory {
  phone,
  message,
  kakao,
  youtube,
  camera,
  gallery,
  contact,

  /// An app already on this phone, chosen from the list it offers.
  ///
  /// The six above are *kinds* of app — the phone opens whichever dialer or
  /// gallery its owner already uses. This one is a named package, because a
  /// senior's 고스톱 or their bank has no category and nothing can stand in
  /// for it.
  ///
  /// It is why this exists at all: seniors do not fail at opening apps, they
  /// fail at **finding** them, and the app they most want is usually not one
  /// of six categories. `home_apps.app_type` has had `'installed_app'` in its
  /// check constraint and a `package_name` column since Phase 4 —
  /// `05_DATA_MODEL` anticipated it and nothing had ever written one.
  installed,

  /// The three that are not apps at all.
  ///
  /// 가족 opens the conversation; 소리 and 인터넷 change the phone. They were
  /// fixed widgets with hard-coded words and colours, which made them the
  /// only things on a senior's home screen that their family could not
  /// rename or recolour - on the half of the app whose whole job is that the
  /// family can.
  ///
  /// They are buttons now, so renaming, recolouring and the sync to
  /// `home_apps` all come for free. What they are *not* is grid tiles: each
  /// has a fixed place on both home screens, and [fixedSlot] is what keeps
  /// them out of the grid and out of the 어떤 버튼인가요 sheet.
  family,
  sound,
  internet,
}

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
    // Neutral on purpose: the tile carries the app's own icon, and a strong
    // face behind a foreign logo fights it. The senior can recolour it.
    AppCategory.installed => AppColors.seniorMore,
    // 가족 keeps the amber it already wore; the two phone controls
    // keep the sand. Changing them here would change what a senior
    // already has, since the saved button only stores an override.
    AppCategory.family => AppColors.seniorFamily,
    AppCategory.sound || AppCategory.internet => AppColors.seniorUtility,
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
    AppCategory.installed => AppColors.seniorMoreLight,
    // 가족 keeps the amber it already wore; the two phone controls
    // keep the sand. Changing them here would change what a senior
    // already has, since the saved button only stores an override.
    AppCategory.family => AppColors.seniorFamilyLight,
    AppCategory.sound || AppCategory.internet => AppColors.seniorUtilityLight,
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
    AppCategory.installed => AppColors.seniorMoreDeep,
    // 가족 keeps the amber it already wore; the two phone controls
    // keep the sand. Changing them here would change what a senior
    // already has, since the saved button only stores an override.
    AppCategory.family => AppColors.seniorFamilyDeep,
    AppCategory.sound || AppCategory.internet => AppColors.seniorUtilityDeep,
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
    AppCategory.installed => AppColors.seniorMoreWall,
    // 가족 keeps the amber it already wore; the two phone controls
    // keep the sand. Changing them here would change what a senior
    // already has, since the saved button only stores an override.
    AppCategory.family => AppColors.seniorFamilyWall,
    AppCategory.sound || AppCategory.internet => AppColors.seniorUtilityWall,
  };

  /// What the icon and the label are drawn in.
  ///
  /// White on every face but the yellow one, which is too light to carry it —
  /// 카카오톡 sat at 2.4:1 against white and would have shipped looking washed
  /// out. A yellow face takes ink, exactly as the 가족 button does.
  /// 사람 shares 가족's amber for the same reason it shares its meaning, and
  /// inherits the same constraint: that amber cannot hold white either.
  Color get letteringColor => switch (this) {
    // A light face cannot hold white. 카카오톡 sat at 2.4:1 against it and
    // 가족's amber is the lightest value in the whole palette; the sand the
    // two phone controls wear is lighter still.
    AppCategory.kakao ||
    AppCategory.contact ||
    AppCategory.family ||
    AppCategory.sound ||
    AppCategory.internet => AppColors.seniorInk,
    _ => Colors.white,
  };

  /// True for the three that have a place of their own on both home screens.
  ///
  /// They are saved and synced like every other button - that is how they
  /// became renameable - but they are never drawn in the grid and never
  /// offered in the 어떤 버튼인가요 sheet. There is exactly one of each and
  /// the senior did not put it there.
  bool get fixedSlot =>
      this == AppCategory.family ||
      this == AppCategory.sound ||
      this == AppCategory.internet;

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
    AppCategory.installed => '앱',
    AppCategory.family => '가족',
    AppCategory.sound => '소리',
    AppCategory.internet => '인터넷',
  };

  /// Whether a home screen may hold more than one of these.
  ///
  /// Six of the kinds are *the* dialer, *the* gallery, *the* messenger — a
  /// second one opens the same app and is a duplicate the senior cannot tell
  /// from the first. 사람 and 폰에 있는 앱 are the opposite: a family has
  /// several people in it and a phone has eighty apps, and offering one of
  /// each would make the whole feature useless after the first use.
  bool get repeatable =>
      this == AppCategory.contact || this == AppCategory.installed;

  /// What the 어떤 버튼인가요? sheet calls this kind.
  ///
  /// Separate from [defaultLabel], which prefills the name dialog: an
  /// installed app never reaches that dialog, because it arrives carrying the
  /// name the phone already shows for it.
  String get pickerLabel => switch (this) {
    AppCategory.installed => '폰에 있는 앱',
    _ => defaultLabel,
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
    AppCategory.family => Icons.family_restroom,
    AppCategory.sound => Icons.volume_up_rounded,
    AppCategory.internet => Icons.wifi_rounded,
    // Only drawn until the app's real icon arrives, and on the guardian's
    // half, which never receives one.
    AppCategory.installed => Icons.apps_rounded,
  };
}
