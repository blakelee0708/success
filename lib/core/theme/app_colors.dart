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
  /// Headings, and the lettering on every face too light for white.
  ///
  /// A warm near-black rather than the #1B1A18 it was. On a white ground that
  /// value measured 17.4:1 — the highest in the app — and high contrast at
  /// this size is not free: the bright ground spreads into the strokes and
  /// large glyphs read as though they are bleeding. This is one step back
  /// from that at 13.2:1, warmed to the same side as the terracotta and the
  /// amber so the screen reads as one thing.
  ///
  /// It is not the brown that came out of the palette. That was #3A2410 and
  /// plainly brown; this is ink with warmth in it.
  static const seniorInk = Color(0xFF352F29);
  static const seniorInkMuted = Color(0xFF8E8A84); // quiet captions
  static const seniorHairline = Color(0xFFE3E4E6); // the rule inside the card

  // 가족 연결's 자녀와 연결하면 boxes, and the field a number is typed into.
  // Cream rather than the amber 가족 wears, because these are not pressable
  // and must not look like a button; the field is yellow so an empty white box
  // on a white ground stops being invisible.
  static const seniorWhyFace = Color(0xFFFFF4DF);
  static const seniorWhyWall = Color(0xFFEAD3A8);
  static const seniorWhyIcon = Color(0xFFB9741A);
  static const seniorCodeField = Color(0xFFFFF6B8);

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

  /// 소리 and 인터넷, the two controls that change the phone rather than
  /// open an app.
  ///
  /// Warm sand, and the warmth is the point: an ageing eye loses the short
  /// wavelengths first, so a cool grey control is the one a senior stops
  /// seeing. It is also the reason the first attempt failed - near-white
  /// `seniorCard` disappeared into the white ground, and these have to be
  /// found by somebody whose phone has gone quiet.
  ///
  /// A light face rather than a saturated one, deliberately. Terracotta read
  /// as a second 긴급 구조 요청 on the same screen, and the whole trouble
  /// with that is it is the colour a senior has been taught to press in a
  /// hurry. Sand is visible without claiming to be urgent, and it carries
  /// ink rather than white, the same rule the amber 가족 button follows.
  static const seniorUtilityLight = Color(0xFFFFF6E8);
  static const seniorUtility = Color(0xFFF4DFC2);
  static const seniorUtilityDeep = Color(0xFFE3C9A2);
  static const seniorUtilityWall = Color(0xFFC3A67C);

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
  static const splashInk = Color(0xFF352F29); // wordmark
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
  static const splashCardTitle = Color(0xFF352F29);

  // Guardian start screen — same paper, cooler ink.
  static const guardianStartBgTop = Color(0xFFFFFFFF);
  static const guardianStartBgMid = Color(0xFFFFFFFF);
  static const guardianStartBgBottom = Color(0xFFF7F7F8);
  static const guardianStartMuted = Color(0xFF85898F);
  static const guardianStartFaint = Color(0xFFA2A6AC);
  static const guardianStartAccent = Color(0xFFC4451F);
  static const guardianStartCardBorder = Color(0xFFE8E9EB);
  static const guardianStartBadgeFill = Color(0xFFF2F3F4);
  static const guardianStartBadgeBorder = Color(0xFFE0E2E5);
  static const kakaoYellow = Color(0xFFFEE500);
  static const kakaoInk = Color(0xFF191600);

  // ── Guardian — high-contrast white / blue (styles.css :root) ──
  // ── Guardian — blue gradients, settled 2026-10-20 ──
  //
  // `04_SCREEN_SPEC` gives this persona 파란 포인트, so none of the senior
  // rules reach here: no clay, no 26px lettering, and blue is the point
  // rather than the thing to avoid. The son or daughter reading this is not
  // the one with the ageing eyes.
  //
  // The hero is a saturated blue rather than the pastel it was drawn from.
  // Same hue; the pastel's white content is what put its own lettering at
  // 1.64:1. `guardian_palette_test.dart` measures all three stops.
  static const guardianHeroStart = Color(0xFF0B4FC4);
  static const guardianHeroMid = Color(0xFF1B5CD8);
  static const guardianHeroEnd = Color(0xFF2E6FE8);

  /// Cast under the hero. Blue rather than grey: a grey shadow on a tinted
  /// ground reads as dirt.
  static const guardianHeroShadow = Color(0xD90B4FC4);

  /// Still connected. A dot, never lettering — it is not legible at this size
  /// and does not need to be.
  static const guardianOnline = Color(0xFF7BF0A4);

  /// The ground: tinted at the crown, plain white by the foot, so the cards
  /// nearest the bottom still have something to sit against.
  static const guardianGroundTop = Color(0xFFEEF2FF);
  static const guardianGroundMid = Color(0xFFF7F9FF);
  static const guardianGroundEnd = Color(0xFFFFFFFF);

  /// A card is a gradient rather than a bordered box. Six bordered boxes in a
  /// column read as a grid and give nothing any precedence.
  static const guardianCardTop = Color(0xFFFFFFFF);
  static const guardianCardEnd = Color(0xFFF4F7FE);
  static const guardianCardShadow = Color(0x4D10245E);

  static const guardianInk = Color(0xFF191F28);
  static const guardianInkSoft = Color(0xFF4E5968);

  /// Captions. Deliberately darker than the #8B95A1 this family of palettes
  /// usually puts here: that measures 3.04 against white, under the bar for
  /// 12.5px before the card's own gradient is counted.
  static const guardianInkFaint = Color(0xFF5F6B7A);
  static const guardianInkDisabled = Color(0xFFAEB6C2);
  static const guardianRule = Color(0xFFEEF1F7);

  /// A text field's edge. `guardianRule` is a divider and vanishes as a box.
  static const guardianFieldEdge = Color(0xFFC5CEDB);

  /// The four blobs behind the action icons.
  static const guardianTintBlue = Color(0xFFE8F0FE);
  static const guardianTintBlueInk = Color(0xFF1A5FD0);
  static const guardianTintViolet = Color(0xFFEDEBFE);
  static const guardianTintVioletInk = Color(0xFF5A46D6);
  static const guardianTintGreen = Color(0xFFE6F6EC);
  static const guardianTintGreenInk = Color(0xFF1F7A3D);
  static const guardianTintAmber = Color(0xFFFFF2E0);
  static const guardianTintAmberInk = Color(0xFF9A6209);

  static const guardianPrimary = Color(0xFF0B5FD9); // --c-primary (deep blue)
  static const guardianBackground = Color(0xFFFFFFFF); // --c-bg
  static const guardianSurface = Color(0xFFF7F7F8); // neutral off-white
  static const guardianOnSurface = Color(0xFF1A1A1A); // --c-ink
  static const guardianBorder = Color(0xFFE3E4E6); // --c-line
  static const guardianAccent = Color(0xFFE8B500); // --c-accent (golden)
  static const guardianDanger = Color(0xFFC8102E); // --c-danger

  /// The unread count on the 메시지 tab.
  ///
  /// Not [guardianDanger]. An unread message from a parent is news, not an
  /// emergency, and the red this half already uses for 위험 has to keep
  /// meaning that. This is the app's own accent, which is also the colour of
  /// the one filled button on the half.
  static const guardianBadge = Color(0xFFE2563A);
}
