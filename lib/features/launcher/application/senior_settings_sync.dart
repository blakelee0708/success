import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../data/remote/home_apps_repository.dart';
import '../../../data/remote/senior_link_repository.dart';
import '../../../data/senior_link_store.dart';
import '../../../domain/launcher_app.dart';
import '../../../domain/senior_settings.dart';

/// Carries the launcher's settings between the parent's phone and the server.
///
/// Both directions fail quietly. The senior's home screen is drawn from what is
/// on disk, and it has to keep being drawn on a phone with no signal, in a
/// hospital, or with the account not yet linked — so a failed sync is a missing
/// update, never a broken launcher. The boolean return is for callers that want
/// to know (and for tests); no screen shows an error because of it.
class SeniorSettingsSync {
  const SeniorSettingsSync({
    required SeniorLinkStore linkStore,
    required HomeAppsRepository homeApps,
    required SeniorLinkRepository links,
  }) : _linkStore = linkStore,
       _homeApps = homeApps,
       _links = links;

  final SeniorLinkStore _linkStore;
  final HomeAppsRepository _homeApps;
  final SeniorLinkRepository _links;

  /// Sends the current arrangement up. Returns false when this phone is not
  /// linked yet or the write did not land.
  Future<bool> push(SeniorSettings settings) async {
    final profileId = (await _linkStore.load()).seniorProfileId;
    if (profileId == null) return false;
    try {
      await _homeApps.replace(profileId, settings.apps);
      await _links.updateProfileSettings(
        profileId,
        screenMode: settings.screenMode,
        fontSize: settings.fontSize,
      );
      return true;
    } on Object {
      return false;
    }
  }

  /// Folds the server's copy into [current]. Returns null when there is nothing
  /// to apply, so a caller can tell "no change" from "an empty home screen".
  ///
  /// An empty button list from the server is ignored rather than adopted: a
  /// profile that has never been pushed to reads as zero rows, and taking that
  /// literally would wipe a home screen the senior is already using.
  Future<SeniorSettings?> pull(SeniorSettings current) async {
    final profileId = (await _linkStore.load()).seniorProfileId;
    if (profileId == null) return null;
    try {
      final profile = await _links.fetchProfile(profileId);
      final apps = await _homeApps.fetch(profileId);
      final merged = profile.applyTo(current);
      final next = apps.isEmpty
          ? merged
          : merged.copyWith(apps: _keepIcons(apps, current.apps));
      return next == current ? null : next;
    } on Object {
      return null;
    }
  }
}

/// Puts the locally held app icons back on the rows that came down.
///
/// An installed-app button carries its chosen app's icon in bytes, and those
/// bytes are deliberately **never sent to the server** — the guardian does
/// not receive the list of what is on their parent's phone. So every row that
/// comes back has a null icon, and applying it verbatim would wipe the real
/// one on every resume: the tile would go from the senior's 고스톱 logo to a
/// grey glyph, and stay there.
///
/// Same rule the device-status column follows — *null means the other side
/// could not say, never that there is nothing.*
List<LauncherApp> _keepIcons(
  List<LauncherApp> fromServer,
  List<LauncherApp> local,
) {
  final icons = {
    for (final app in local)
      if (app.iconBytes != null) app.id: app.iconBytes!,
  };
  if (icons.isEmpty) return fromServer;
  return [
    for (final app in fromServer)
      app.iconBytes == null && icons.containsKey(app.id)
          ? app.copyWith(iconBytes: icons[app.id])
          : app,
  ];
}

final seniorSettingsSyncProvider = Provider<SeniorSettingsSync>(
  (ref) => SeniorSettingsSync(
    linkStore: ref.watch(seniorLinkStoreProvider),
    homeApps: ref.watch(homeAppsRepositoryProvider),
    links: ref.watch(seniorLinkRepositoryProvider),
  ),
);
