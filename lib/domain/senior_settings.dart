import 'app_category.dart';
import 'launcher_app.dart';

/// The fewest buttons a home screen may be reduced to.
///
/// Four, because that is `defaultEasyApps` - the arrangement the product
/// ships as the simplest one worth having. Below it the screen stops being a
/// launcher.
const minimumHomeButtons = 4;

/// Which launcher home the senior sees. Chosen during onboarding (Phase 1).
enum ScreenMode { easy, detailed }

/// How large the launcher draws its text. Three steps rather than a slider:
/// the choice has to be legible to someone who cannot read the current size.
enum FontSize {
  normal(1.0),
  large(1.2),
  extraLarge(1.45),
  largest(1.7);

  const FontSize(this.scale);

  /// Multiplier applied to the launcher's text sizes.
  final double scale;
}

/// Persistent senior-facing settings.
///
/// Everything here has to outlive a restart — this app is the phone's home
/// screen, so losing it means the senior's phone silently reverts.
class SeniorSettings {
  const SeniorSettings({
    this.screenMode,
    this.fontSize = FontSize.normal,
    this.apps = const [],
    this.removedSlots = const {},
  });

  /// `null` means the senior has not chosen a mode yet.
  final ScreenMode? screenMode;
  final FontSize fontSize;

  /// The home buttons in display order. Empty until a mode is chosen, at which
  /// point the defaults for that mode are written here and become editable.
  final List<LauncherApp> apps;

  /// Which of 가족, 소리, 인터넷 and 긴급 구조 요청 the family has taken off
  /// the home screen.
  ///
  /// **Recorded rather than inferred from the list, and that is the whole
  /// design of it.** A slot button absent from [apps] has always meant
  /// *nobody has edited this yet, use the default* - which is what let a
  /// saved list written before these existed still draw all four. Reading
  /// absence as removal instead would mean every one of those settings lost
  /// its four buttons the moment this shipped, and there is nothing in the
  /// list that tells the two apart.
  ///
  /// It is on the settings rather than in `home_apps` because `home_apps`
  /// holds rows, and the thing being recorded is the absence of one.
  final Set<AppCategory> removedSlots;

  SeniorSettings copyWith({
    ScreenMode? screenMode,
    FontSize? fontSize,
    List<LauncherApp>? apps,
    Set<AppCategory>? removedSlots,
  }) => SeniorSettings(
    screenMode: screenMode ?? this.screenMode,
    fontSize: fontSize ?? this.fontSize,
    apps: apps ?? this.apps,
    removedSlots: removedSlots ?? this.removedSlots,
  );

  /// The slot button for [category], or null when the family took it off.
  ///
  /// One place decides, so a home screen cannot draw a button the settings
  /// screen thinks is gone.
  LauncherApp? slot(AppCategory category) {
    if (removedSlots.contains(category)) return null;
    for (final app in apps) {
      if (app.category == category) return app;
    }
    return fixedSlotApps.firstWhere((a) => a.category == category);
  }

  /// Every button actually on the home screen: the grid tiles and whichever
  /// of the four slot buttons is still there.
  int get homeButtonCount =>
      seniorGridApps(apps.isEmpty ? defaultEasyApps : apps).length +
      [for (final app in fixedSlotApps) slot(app.category)].nonNulls.length;

  /// Whether one more may be taken off.
  ///
  /// **Four is the floor**, and it is a floor rather than a warning because
  /// the thing being emptied is somebody's home screen. The four slot buttons
  /// became removable on 2026-10-28, which for the first time made an empty
  /// home screen reachable - and a senior looking at a blank phone cannot be
  /// told what to press to get their buttons back, which is the whole reason
  /// this app exists.
  ///
  /// It is not enforced by hiding 지우기. A button that does nothing is read
  /// as the phone being broken; the refusal says the number instead and
  /// offers the way round it, which is the rule every other refusal in this
  /// product follows.
  bool get canRemoveButton => homeButtonCount > minimumHomeButtons;

  /// The slot kinds that can be put back, in their fixed order.
  List<AppCategory> get addableSlots => [
    for (final app in fixedSlotApps)
      if (removedSlots.contains(app.category)) app.category,
  ];

  Map<String, Object?> toJson() => {
    'screenMode': screenMode?.name,
    'fontSize': fontSize.name,
    'apps': apps.map((a) => a.toJson()).toList(),
    'removedSlots': [for (final c in removedSlots) c.name],
  };

  /// Anything unrecognised falls back to the default rather than throwing:
  /// an older or half-written payload must not brick the launcher.
  factory SeniorSettings.fromJson(Map<String, Object?> json) {
    final apps = json['apps'];
    final removed = json['removedSlots'];
    return SeniorSettings(
      screenMode: _byName(ScreenMode.values, json['screenMode']),
      fontSize: _byName(FontSize.values, json['fontSize']) ?? FontSize.normal,
      removedSlots: removed is List
          ? {for (final name in removed) ?_byName(AppCategory.values, name)}
          : const {},
      apps: apps is List
          ? apps
                .whereType<Map<String, Object?>>()
                .map(LauncherApp.fromJson)
                .nonNulls
                .toList(growable: false)
          : const [],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SeniorSettings &&
      other.screenMode == screenMode &&
      other.fontSize == fontSize &&
      _sameApps(other.apps, apps) &&
      other.removedSlots.length == removedSlots.length &&
      other.removedSlots.containsAll(removedSlots);

  @override
  int get hashCode => Object.hash(
    screenMode,
    fontSize,
    Object.hashAll(apps),
    Object.hashAllUnordered(removedSlots),
  );

  static bool _sameApps(List<LauncherApp> a, List<LauncherApp> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

T? _byName<T extends Enum>(List<T> values, Object? name) {
  if (name is! String) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}
