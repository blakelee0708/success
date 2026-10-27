import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import 'app_category.dart';

/// A colour a senior, or their guardian, can put on a button by hand.
///
/// **Fourteen, round the whole circle.** It was five, all warm — which is the
/// terracotta family at three brightnesses rather than a choice — and the
/// point of letting someone recolour a button is that they can tell it apart
/// from the one beside it.
///
/// `04_SCREEN_SPEC` asks for a 난색 **기반** 팔레트, and that is what this
/// still is: the ground, the ink and the headings are warm, and the five
/// originals are kept. The tiles were never monochrome — 문자 is blue,
/// 사진찍기 purple, 사진 보기 pink, 전화 green — so a palette that reaches
/// those is describing what the screen already looks like.
///
/// The ban on blue and teal in `CLAUDE.md` is about colours *this app*
/// chooses for things like 가족 and 더 보기, where an ageing eye has to pick
/// one object out of several it did not place. Somebody choosing a colour for
/// their own 딸 button is the opposite case: they picked it because they can
/// see it. What is not negotiable is the 3:1 lettering floor, and that is
/// measured below rather than assumed.
///
/// Each carries only its face. The other three clay colours and the
/// lettering are **derived**, because a hand-kept table of 56 values drifts
/// and because the derivation is what guarantees a new colour cannot be added
/// without a wall darker than its face.
enum ButtonColor {
  // The five that existed before, at their original values. Their *names* are
  // what `button_color` stores, on disk and on the server, and an unknown name
  // reads back as null — so renaming one silently resets every button already
  // set to it.
  vermilion(Color(0xFFE24C2B)),
  orange(Color(0xFFF0902B)),
  yellow(Color(0xFFE8B22E)),
  rust(Color(0xFFC4451F)),
  rose(Color(0xFFD96A8A)),
  // The nine that complete the circle.
  amber(Color(0xFFEDA42F)),
  lime(Color(0xFF95B846)),
  green(Color(0xFF55A05C)),
  teal(Color(0xFF3C9E91)),
  sky(Color(0xFF3997BD)),
  blue(Color(0xFF4B7FC4)),
  indigo(Color(0xFF5C56B2)),
  purple(Color(0xFF8F63BE)),
  magenta(Color(0xFFB867B1)),
  brown(Color(0xFF85614D));

  const ButtonColor(this.color);

  /// The face.
  final Color color;

  /// Lit top of the face.
  Color get lightColor => _shift(satScale: 0.72, value: 0.13);

  /// Shaded foot, where the face turns away from the light.
  Color get deepColor => _shift(sat: 0.05, value: -0.14);

  /// The side wall the tile stands on, and always the darkest of the four.
  /// Without it the tile is a rectangle rather than an object.
  Color get wallColor => _shift(sat: 0.07, value: -0.23);

  /// White or ink, whichever the face can actually hold.
  ///
  /// Measured rather than listed. The floor is 3:1, which is what lettering
  /// this size needs, and the yellows cannot reach it with white — they take
  /// ink, exactly as the 카카오톡 tile does.
  Color get letteringColor {
    final white = _contrast(color, const Color(0xFFFFFFFF));
    final inked = _contrast(color, AppColors.seniorInk);
    return white >= inked ? const Color(0xFFFFFFFF) : AppColors.seniorInk;
  }

  /// The hand-tuned category colours sit within these offsets of their own
  /// face, so a derived set lands among them rather than beside them.
  Color _shift({double sat = 0, double satScale = 1, double value = 0}) {
    final hsv = HSVColor.fromColor(color);
    return hsv
        .withSaturation((hsv.saturation * satScale + sat).clamp(0.0, 1.0))
        .withValue((hsv.value + value).clamp(0.0, 1.0))
        .toColor();
  }

  static double _contrast(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }
}

/// A single launcher home button.
///
/// [id] is what survives editing: renaming or recolouring a button must not
/// make it a different button, and reordering must not rewrite anything else.
class LauncherApp {
  const LauncherApp({
    required this.id,
    required this.label,
    required this.category,
    this.color,
    this.phoneNumber,
  });

  final String id;
  final String label;

  /// Drives the icon, and the colour when [color] is null.
  final AppCategory category;

  /// Set once the senior (or their guardian) picks a colour by hand.
  final ButtonColor? color;

  /// The number a `contact` button dials. Supplied by the guardian, so the
  /// parent's phone never needs a contacts permission to have their
  /// daughter on the home screen.
  ///
  /// Null on every other kind, and null on a contact the guardian has not
  /// finished setting up — [opensDialer] is what the home screen asks.
  final String? phoneNumber;

  /// Whether tapping this opens the dialer rather than an app. Both halves
  /// matter: a contact with no number has nothing to dial, and a number on
  /// any other kind would be ignored.
  bool get opensDialer =>
      category.isContact && (phoneNumber?.trim().isNotEmpty ?? false);

  /// The four colours actually drawn, and the lettering over them.
  ///
  /// All five defer to [color] together. Replacing only the face — which is
  /// what `AppTile` used to do by reading the category directly — leaves a
  /// green wall under a blue face, and white lettering on a yellow one.
  Color get baseColor => color?.color ?? category.baseColor;
  Color get lightColor => color?.lightColor ?? category.lightColor;
  Color get deepColor => color?.deepColor ?? category.deepColor;
  Color get wallColor => color?.wallColor ?? category.wallColor;
  Color get letteringColor =>
      color?.letteringColor ?? category.letteringColor;

  LauncherApp copyWith({
    String? label,
    AppCategory? category,
    String? phoneNumber,
  }) => LauncherApp(
    id: id,
    label: label ?? this.label,
    category: category ?? this.category,
    color: color,
    phoneNumber: phoneNumber ?? this.phoneNumber,
  );

  /// Separate from [copyWith] because clearing a colour is a real edit —
  /// `copyWith(color: null)` could not tell "leave it" from "reset it".
  LauncherApp withColor(ButtonColor? value) => LauncherApp(
    id: id,
    label: label,
    category: category,
    color: value,
    phoneNumber: phoneNumber,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'category': category.name,
    'color': color?.name,
    'phoneNumber': phoneNumber,
  };

  /// Returns null for a row that cannot be read, so one bad button does not
  /// take the whole home screen down with it.
  static LauncherApp? fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final label = json['label'];
    final category = _byName(AppCategory.values, json['category']);
    if (id is! String || label is! String || category == null) return null;
    return LauncherApp(
      id: id,
      label: label,
      category: category,
      color: _byName(ButtonColor.values, json['color']),
      phoneNumber: json['phoneNumber'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LauncherApp &&
      other.id == id &&
      other.label == label &&
      other.category == category &&
      other.color == color;

  @override
  int get hashCode => Object.hash(id, label, category, color);
}

T? _byName<T extends Enum>(List<T> values, Object? name) {
  if (name is! String) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}

/// Easy mode 2×2 grid (04_SCREEN_SPEC 정말 쉬운 화면).
const List<LauncherApp> defaultEasyApps = [
  LauncherApp(id: 'phone', label: '전화', category: AppCategory.phone),
  LauncherApp(id: 'message', label: '문자', category: AppCategory.message),
  LauncherApp(id: 'gallery', label: '앨범', category: AppCategory.gallery),
  LauncherApp(id: 'youtube', label: '영상 보기', category: AppCategory.youtube),
];

/// Detailed mode 6 buttons (04_SCREEN_SPEC 자세한 화면).
const List<LauncherApp> defaultDetailedApps = [
  LauncherApp(id: 'phone', label: '전화', category: AppCategory.phone),
  LauncherApp(id: 'message', label: '문자', category: AppCategory.message),
  LauncherApp(id: 'kakao', label: '카카오톡', category: AppCategory.kakao),
  LauncherApp(id: 'youtube', label: '영상 보기', category: AppCategory.youtube),
  LauncherApp(id: 'camera', label: '사진찍기', category: AppCategory.camera),
  LauncherApp(id: 'gallery', label: '사진 보기', category: AppCategory.gallery),
];
