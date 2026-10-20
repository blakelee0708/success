import 'launcher_app.dart';

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
  });

  /// `null` means the senior has not chosen a mode yet.
  final ScreenMode? screenMode;
  final FontSize fontSize;

  /// The home buttons in display order. Empty until a mode is chosen, at which
  /// point the defaults for that mode are written here and become editable.
  final List<LauncherApp> apps;

  SeniorSettings copyWith({
    ScreenMode? screenMode,
    FontSize? fontSize,
    List<LauncherApp>? apps,
  }) => SeniorSettings(
    screenMode: screenMode ?? this.screenMode,
    fontSize: fontSize ?? this.fontSize,
    apps: apps ?? this.apps,
  );

  Map<String, Object?> toJson() => {
    'screenMode': screenMode?.name,
    'fontSize': fontSize.name,
    'apps': apps.map((a) => a.toJson()).toList(),
  };

  /// Anything unrecognised falls back to the default rather than throwing:
  /// an older or half-written payload must not brick the launcher.
  factory SeniorSettings.fromJson(Map<String, Object?> json) {
    final apps = json['apps'];
    return SeniorSettings(
      screenMode: _byName(ScreenMode.values, json['screenMode']),
      fontSize:
          _byName(FontSize.values, json['fontSize']) ?? FontSize.normal,
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
      _sameApps(other.apps, apps);

  @override
  int get hashCode => Object.hash(screenMode, fontSize, Object.hashAll(apps));

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
