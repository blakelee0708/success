import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_category.dart';
import '../../../domain/launcher_app.dart';

/// A well-known kind of app, resolved on the platform side by intent rather
/// than by package name.
///
/// Naming a package would pick one phone's dialer and break every other, so
/// anything the system has a category for is asked for that way. Only apps
/// with no category — 카카오톡, 유튜브 — are named.
enum LaunchIntent { dial, messaging, camera, gallery, browser }

/// What tapping one home button should open.
class LaunchRequest {
  const LaunchRequest({this.packageName, this.intent, this.fallbackUrl});

  /// Tried first when set.
  final String? packageName;

  /// Tried when there is no package, or the named one is not installed.
  final LaunchIntent? intent;

  /// Last resort, opened in whatever handles links. Set only where the web
  /// version is genuinely usable — for 유튜브 it is, for 카카오톡 it is not, and
  /// dropping a senior onto a login page would be worse than saying nothing
  /// opened.
  final String? fallbackUrl;

  Map<String, Object?> toArguments() => {
    'packageName': packageName,
    'intent': intent?.name,
    'fallbackUrl': fallbackUrl,
  };

  @override
  bool operator ==(Object other) =>
      other is LaunchRequest &&
      other.packageName == packageName &&
      other.intent == intent &&
      other.fallbackUrl == fallbackUrl;

  @override
  int get hashCode => Object.hash(packageName, intent, fallbackUrl);
}

/// How a home button opens.
///
/// Takes the button rather than its category, because an `installed` one is
/// the package the senior picked and two of them differ only by that.
LaunchRequest launchRequestForApp(LauncherApp app) =>
    app.category == AppCategory.installed
    ? LaunchRequest(packageName: app.packageName)
    : launchRequestFor(app.category);

/// How each *kind* of home button opens.
///
/// 전화 resolves to ACTION_DIAL, never ACTION_CALL: `06_PERMISSION_AND_POLICY`
/// says the app must not place a call itself, and that rule is not only about
/// the SOS button.
LaunchRequest launchRequestFor(AppCategory category) => switch (category) {
  AppCategory.phone => const LaunchRequest(intent: LaunchIntent.dial),
  AppCategory.message => const LaunchRequest(intent: LaunchIntent.messaging),
  AppCategory.camera => const LaunchRequest(intent: LaunchIntent.camera),
  AppCategory.gallery => const LaunchRequest(intent: LaunchIntent.gallery),
  AppCategory.kakao => const LaunchRequest(packageName: 'com.kakao.talk'),
  // A contact never reaches here — the home screen sends it to the dialer
  // instead — but the switch has to be total, and `dial` is the honest
  // answer for a contact whose number went missing.
  AppCategory.contact => const LaunchRequest(intent: LaunchIntent.dial),
  AppCategory.youtube => const LaunchRequest(
    packageName: 'com.google.android.youtube',
    intent: LaunchIntent.browser,
    fallbackUrl: 'https://m.youtube.com',
  ),
  // Never reached: `launchRequestForApp` answers for this one, because the
  // package is on the button and not on the kind. The switch has to be total.
  AppCategory.installed => const LaunchRequest(),
};

/// One app already on this phone, as the picker offers it.
class InstalledApp {
  const InstalledApp({
    required this.packageName,
    required this.label,
    this.icon,
  });

  final String packageName;

  /// The name the phone shows for it, which is the name the senior is
  /// looking for — not a package id and not our own word for it.
  final String label;

  /// Its own icon, PNG. Null where the phone could not render one; the app is
  /// still offered, because it is being picked by name.
  final Uint8List? icon;
}

/// Opening other apps, and the launcher's own standing on this phone.
abstract interface class AppLauncher {
  /// Every app on this phone with a launcher icon, by name.
  ///
  /// Empty where the platform cannot say — a desktop build, `flutter test`.
  /// A caller must render that as *nothing to choose from* rather than as an
  /// error, the same way every other channel read here degrades.
  ///
  /// **Never called to draw a tile.** The home screen keeps each chosen
  /// app's icon beside its button instead; nothing a senior is looking at may
  /// wait on this channel, and this one is the slowest of them.
  Future<List<InstalledApp>> installedApps();

  /// False when nothing on the phone could handle it — usually the app is
  /// simply not installed.
  Future<bool> open(LaunchRequest request);

  /// Null when the platform cannot say: on a desktop or under `flutter test`
  /// there is no home app to be. Callers must not read that as "no", or every
  /// test would render a prompt asking to become the launcher.
  Future<bool?> isDefaultHome();

  /// Opens the system's home-app chooser. On Android 10 and up this is the
  /// in-app role dialog; older versions fall back to the settings screen.
  ///
  /// False when nothing opened. Phones differ about which of those screens
  /// they have, and a senior left looking at an unchanged screen cannot tell
  /// a refused chooser from a broken button — so the caller has to be able to
  /// say something.
  Future<bool> openHomeSettings();
}

class MethodChannelAppLauncher implements AppLauncher {
  const MethodChannelAppLauncher();

  static const channel = MethodChannel('jalboine/launcher');

  @override
  Future<bool> open(LaunchRequest request) async {
    try {
      return await channel.invokeMethod<bool>('open', request.toArguments()) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<List<InstalledApp>> installedApps() async {
    try {
      final rows = await channel.invokeListMethod<Object?>('installedApps');
      return [
        for (final row in rows ?? const [])
          if (row is Map && row['package'] is String && row['label'] is String)
            InstalledApp(
              packageName: row['package'] as String,
              label: row['label'] as String,
              icon: row['icon'] as Uint8List?,
            ),
      ];
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  @override
  Future<bool?> isDefaultHome() async {
    try {
      return await channel.invokeMethod<bool>('isDefaultHome');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<bool> openHomeSettings() async {
    try {
      return await channel.invokeMethod<bool>('openHomeSettings') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

/// Records what it was asked to open, for tests and for builds with no
/// platform side.
class FakeAppLauncher implements AppLauncher {
  FakeAppLauncher({this.installed = true, this.defaultHome});

  /// Set false to behave like a phone without the app installed.
  bool installed;

  /// What [isDefaultHome] answers. Null means "cannot say", the same as a
  /// platform that does not implement the channel.
  bool? defaultHome;

  /// Set false to behave like a phone that opens no chooser at all.
  bool homeSettingsOpens = true;

  final List<LaunchRequest> opened = [];
  int homeSettingsOpened = 0;

  /// What the phone offers to pick from. Empty by default, which is what a
  /// platform that cannot answer gives back — so a screen that does not
  /// handle the empty case fails in a test rather than on someone's mother's
  /// phone.
  List<InstalledApp> apps = const [];
  int appsListed = 0;

  @override
  Future<bool> open(LaunchRequest request) async {
    opened.add(request);
    return installed;
  }

  @override
  Future<List<InstalledApp>> installedApps() async {
    appsListed++;
    return apps;
  }

  @override
  Future<bool?> isDefaultHome() async => defaultHome;

  @override
  Future<bool> openHomeSettings() async {
    homeSettingsOpened++;
    return homeSettingsOpens;
  }
}

final appLauncherProvider = Provider<AppLauncher>(
  (ref) => const MethodChannelAppLauncher(),
);

/// Whether this app is the phone's home app. Null while unknown.
final isDefaultHomeProvider = FutureProvider<bool?>(
  (ref) => ref.watch(appLauncherProvider).isDefaultHome(),
);
