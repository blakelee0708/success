import 'package:flutter/material.dart';

/// Color tokens for the two app personas.
///
/// Values are extracted verbatim from the canonical design sources in
/// `design-reference/see/`:
///   - Senior (피보호자): `launcher.jsx` (PAGE_BG / INK / APPS tiles / SOS)
///     and `splash.jsx` (SplashC terracotta CTA).
///   - Guardian (보호자): `styles.css` `:root` high-contrast token set.
class AppColors {
  AppColors._();

  // ── Senior — white ground, extruded clay buttons ──
  //
  // Settled in the 2026-10-20 design review, which replaced the cream ground
  // of `launcher.jsx` with white and gave every pressable thing a lit top, a
  // shaded bottom and a side wall. The tile hues are that review's, a shade
  // off `launcher.jsx`'s originals; the approved mock is the source now.
  static const seniorBackground = Color(0xFFFFFFFF); // the ground is white
  static const seniorInk = Color(0xFF1B1A18); // headings, amber lettering
  static const seniorInkMuted = Color(0xFF8E8A84); // the date above the clock
  static const seniorHairline = Color(0xFFE3E4E6); // the rule inside the card

  /// The two home buttons. Blue and teal went first — short-wavelength
  /// colours are the first an ageing eye loses, which is why 가족 is amber
  /// (lettered in ink, since amber is too light for white) and 더 보기 brown.
  static const seniorFamily = Color(0xFFF2A93B);
  static const seniorFamilyLight = Color(0xFFFFD98A);
  static const seniorFamilyDeep = Color(0xFFD08B1E);
  static const seniorFamilyWall = Color(0xFFB0720F);
  static const seniorMore = Color(0xFF6B5945);
  static const seniorMoreLight = Color(0xFF9A866E);
  static const seniorMoreDeep = Color(0xFF52412F);
  static const seniorMoreWall = Color(0xFF3F3122);

  /// An empty cell in the 자세한 화면 grid. Neutral greys, not the muted clay
  /// the slot used to be drawn in — the beige came out of the senior palette
  /// in the 2026-10-20 review. Hollow rather than extruded on purpose: it is
  /// the one shape on the home screen that is not yet a thing to press.
  static const seniorSlotFill = Color(0xFFFBFBFC);
  static const seniorSlotBorder = Color(0xFFC7C9CC);
  static const seniorSlotInk = Color(0xFF75797F);

  /// The raised card the clock and the family line sit on. Its face is
  /// tinted rather than pure white: on a white ground a white card has no
  /// edge, and the clock looked like it was floating outside its own box.
  static const seniorCardLight = Color(0xFFFFFFFF);
  static const seniorCard = Color(0xFFF7F7F8);
  static const seniorCardDeep = Color(0xFFEAEBEC);
  static const seniorCardWall = Color(0xFFD2D4D7);

  static const seniorCreamLegacy = Color(0xFFFDF7EE); // splash only
  static const seniorBackgroundEnd = Color(
    0xFFF6EBDA,
  ); // gradient bottom (soft clay)
  static const seniorSurface = Color(0xFFFFFFFF); // card / list-row surface
  static const seniorPrimary = Color(
    0xFFE0481C,
  ); // terracotta CTA (SplashC btn / voice)
  static const seniorOnSurface = Color(0xFF3A2410); // INK — primary text
  static const seniorTextSecondary = Color(
    0xFF7A5A40,
  ); // INK_SOFT — secondary text
  static const seniorBorder = Color(
    0xFFC9A98C,
  ); // muted clay (chevron / divider)
  static const seniorSos = Color(0xFFE13A24); // SOS face (긴급 구조)
  static const seniorSosLight = Color(0xFFFB8168);
  static const seniorSosDeep = Color(0xFFBB2113);
  static const seniorSosWall = Color(0xFF981610);

  // Senior launcher app-tile categories (c1 light → c2 base), from APPS in
  // launcher.jsx. Used by the home grid in Phase 1.
  static const seniorButtonGreen = Color(0xFF55A05D); // 전화
  static const seniorButtonGreenLight = Color(0xFF84C97C);
  static const seniorButtonGreenDeep = Color(0xFF3F7F48);
  static const seniorButtonGreenWall = Color(0xFF336A3C);
  static const seniorButtonBlue = Color(0xFF4A7FC4); // 메시지
  static const seniorButtonBlueLight = Color(0xFF78AEE6);
  static const seniorButtonBlueDeep = Color(0xFF35619C);
  static const seniorButtonBlueWall = Color(0xFF2C5287);
  static const seniorButtonYellow = Color(0xFFE09A2B); // 카카오톡
  static const seniorButtonYellowLight = Color(0xFFFFD98A);
  static const seniorButtonYellowDeep = Color(0xFFC47F19);
  static const seniorButtonYellowWall = Color(0xFFA86B13);
  static const seniorButtonRed = Color(0xFFDF4F28); // 유튜브
  static const seniorButtonRedLight = Color(0xFFFA8A64);
  static const seniorButtonRedDeep = Color(0xFFB83A17);
  static const seniorButtonRedWall = Color(0xFF9E2E11);
  static const seniorButtonPurple = Color(0xFF8E62BE); // 카메라
  static const seniorButtonPurpleLight = Color(0xFFC3A0E2);
  static const seniorButtonPurpleDeep = Color(0xFF6A4394);
  static const seniorButtonPurpleWall = Color(0xFF5A3880);
  static const seniorButtonPink = Color(0xFFCE6799); // 갤러리
  static const seniorButtonPinkLight = Color(0xFFEE95BE);
  static const seniorButtonPinkDeep = Color(0xFFAC4F7E);
  static const seniorButtonPinkWall = Color(0xFF94406B);

  // ── Splash / guardian entry (2026-07-29 design) ──
  // Warm paper gradient behind the hand illustration.
  static const splashBgTop = Color(0xFFFFFFFF);
  static const splashBgMid = Color(0xFFFFFFFF);
  static const splashBgBottom = Color(0xFFFFFFFF);
  static const splashInk = Color(0xFF1B1A18); // wordmark
  static const splashTagline = Color(0xFF75797F);
  static const splashAccent = Color(0xFFD93516); // tap circle, wordmark dot
  static const splashPromptInk = Color(0xFF7A3D24); // 스마트폰이 쉬워져요
  // The 가족 및 보호자 card: a near-white clay pad, so its own four steps
  // rather than the tiles'. They live here and not in the widget because the
  // lettering has to be measured against the face it actually sits on, and a
  // colour hidden inside a build method cannot be.
  static const splashCardFace = Color(0xFFFFFFFF); // guardian card
  static const splashCardDeep = Color(0xFFF5F6F7);
  static const splashCardWall = Color(0xFFDCDEE1);
  static const splashCardLabel = Color(0xFF6A6E74);
  static const splashCardTitle = Color(0xFF1B1A18);

  // Guardian start screen — same paper, cooler ink.
  static const guardianStartBgTop = Color(0xFFFFFFFF);
  static const guardianStartBgMid = Color(0xFFFFFFFF);
  static const guardianStartBgBottom = Color(0xFFF7F7F8);
  static const guardianStartInk = Color(0xFF1B1A18);
  static const guardianStartMuted = Color(0xFF85898F);
  static const guardianStartSub = Color(0xFF75797F);
  static const guardianStartFaint = Color(0xFFA2A6AC);
  static const guardianStartAccent = Color(0xFFC4451F);
  static const guardianStartLine = Color(0xFFE3E4E6);
  static const guardianStartCardBorder = Color(0xFFE8E9EB);
  static const guardianStartBadgeFill = Color(0xFFF2F3F4);
  static const guardianStartBadgeBorder = Color(0xFFE0E2E5);
  static const kakaoYellow = Color(0xFFFEE500);
  static const kakaoInk = Color(0xFF191600);

  // ── Guardian — high-contrast white / blue (styles.css :root) ──
  static const guardianPrimary = Color(0xFF0B5FD9); // --c-primary (deep blue)
  static const guardianBackground = Color(0xFFFFFFFF); // --c-bg
  static const guardianSurface = Color(0xFFF7F7F8); // neutral off-white
  static const guardianOnSurface = Color(0xFF1A1A1A); // --c-ink
  static const guardianBorder = Color(0xFFE3E4E6); // --c-line
  static const guardianAccent = Color(0xFFE8B500); // --c-accent (golden)
  static const guardianDanger = Color(0xFFC8102E); // --c-danger
}
