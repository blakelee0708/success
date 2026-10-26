import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/senior_settings_repository.dart';
import '../../../domain/app_category.dart';
import '../../../domain/launcher_app.dart';
import '../../../data/senior_link_store.dart';
import '../../../domain/senior_settings.dart';
import 'senior_settings_sync.dart';

/// Holds the senior's settings, loading from and saving to the repository.
///
/// Every edit writes through before the new state is published, so what the
/// screen shows is what survived to disk. On this app that matters more than
/// the extra await: it is the phone's home screen.
///
/// Since Phase 4 each write is also pushed to Supabase, but never in the path
/// the senior waits on: disk is the source of truth, the server is a copy, and
/// an edit must land at full speed on a phone with no signal.
class SeniorSettingsController extends AsyncNotifier<SeniorSettings> {
  Future<void>? _sync;

  /// The push started by the most recent write, for tests and for callers that
  /// need the server to have caught up. Never completes with an error.
  Future<void> get pendingSync => _sync ?? Future<void>.value();

  Future<void>? _pull;

  /// The start-up pull, for tests that need the server to have been read.
  Future<void> get pendingPull => _pull ?? Future<void>.value();

  @override
  Future<SeniorSettings> build() async {
    final saved = await ref.watch(seniorSettingsRepositoryProvider).load();

    // Then ask the server, without making the home screen wait for it. The
    // guardian's tab promises 부모님 폰이 꺼져 있으면 다음에 켤 때 적용돼요, and
    // until this existed nothing ever read the server except the moment the
    // phone was first linked — so an arrangement made the next day never
    // arrived. Awaiting it here instead would make a launcher with no signal
    // open on a spinner.
    _pull = _adoptServerCopy(saved);
    return saved;
  }

  /// Folds in whatever the server holds, if it differs. Silent on failure:
  /// the home screen is drawn from disk and has to keep working on a phone
  /// with no signal.
  Future<void> _adoptServerCopy(SeniorSettings from) async {
    // Only a phone that is actually a senior's has anything to read. The
    // guard is first so a guardian's phone — and every test that never links
    // one — does not reach the repositories behind the sync at all.
    final link = await ref.read(seniorLinkStoreProvider).load();
    if (link.seniorProfileId == null) return;

    final merged = await ref.read(seniorSettingsSyncProvider).pull(from);
    if (merged == null) return;
    await ref.read(seniorSettingsRepositoryProvider).save(merged);
    state = AsyncData(merged);
  }

  /// Adopts whatever the server holds for this phone's profile.
  ///
  /// Called after the phone is linked, so a guardian who arranged the home
  /// screen before the parent connected sees their arrangement take effect.
  Future<bool> pullFromServer() async {
    final current = state.value ?? const SeniorSettings();
    final merged = await ref.read(seniorSettingsSyncProvider).pull(current);
    if (merged == null) return false;
    await ref.read(seniorSettingsRepositoryProvider).save(merged);
    state = AsyncData(merged);
    return true;
  }

  /// Re-reads the server because the phone came back to the foreground.
  ///
  /// Same job as the start-up pull; a senior who leaves the launcher open for
  /// days would otherwise never see a change made in between.
  Future<void> refresh() =>
      _adoptServerCopy(state.value ?? const SeniorSettings());

  /// Picks the mode and, on a home that has no buttons yet, seeds that mode's
  /// defaults so there is something to edit.
  ///
  /// An existing arrangement is left alone — re-entering onboarding must not
  /// wipe a home the senior has already arranged.
  Future<void> chooseScreenMode(ScreenMode mode) async {
    final current = state.value ?? const SeniorSettings();
    await _write(
      current.copyWith(
        screenMode: mode,
        apps: current.apps.isEmpty ? _defaultsFor(mode) : current.apps,
      ),
    );
  }

  Future<void> setFontSize(FontSize size) async {
    final current = state.value ?? const SeniorSettings();
    await _write(current.copyWith(fontSize: size));
  }

  Future<void> renameApp(String id, String label) =>
      _mapApps((app) => app.id == id ? app.copyWith(label: label) : app);

  /// Pass null to drop back to the button's category colour.
  Future<void> setAppColor(String id, ButtonColor? color) =>
      _mapApps((app) => app.id == id ? app.withColor(color) : app);

  Future<void> removeApp(String id) async {
    final current = state.value ?? const SeniorSettings();
    await _write(
      current.copyWith(
        apps: current.apps.where((a) => a.id != id).toList(growable: false),
      ),
    );
  }

  /// Indices follow `ReorderableListView`: [newIndex] is read against the list
  /// as it still stands, before the dragged button is lifted out, so a move
  /// downward has to shed one place once it is.
  Future<void> reorderApps(int oldIndex, int newIndex) async {
    final current = state.value ?? const SeniorSettings();
    final apps = [...current.apps];
    if (oldIndex < 0 || oldIndex >= apps.length) return;
    final target = newIndex > oldIndex ? newIndex - 1 : newIndex;
    final moved = apps.removeAt(oldIndex);
    apps.insert(target.clamp(0, apps.length), moved);
    await _write(current.copyWith(apps: apps));
  }

  Future<void> addApp({
    required String label,
    required AppCategory category,
    String? phoneNumber,
  }) async {
    final current = state.value ?? const SeniorSettings();
    await _write(
      current.copyWith(
        apps: [
          ...current.apps,
          LauncherApp(
            id: _freshId(current.apps),
            label: label,
            category: category,
            phoneNumber: phoneNumber,
          ),
        ],
      ),
    );
  }

  /// Both halves of a person button at once. Renaming and renumbering are one
  /// edit: a number that can only be set at creation means a typo is fixed by
  /// deleting the button and starting over.
  Future<void> editContact(
    String id, {
    required String label,
    required String phoneNumber,
  }) => _mapApps(
    (app) => app.id == id
        ? app.copyWith(label: label, phoneNumber: phoneNumber)
        : app,
  );

  Future<void> _mapApps(LauncherApp Function(LauncherApp) transform) async {
    final current = state.value ?? const SeniorSettings();
    await _write(
      current.copyWith(
        apps: current.apps.map(transform).toList(growable: false),
      ),
    );
  }

  Future<void> _write(SeniorSettings settings) async {
    await ref.read(seniorSettingsRepositoryProvider).save(settings);
    state = AsyncData(settings);
    // Deliberately not awaited: the senior has already seen the change, and
    // holding the edit open for a round trip would make every rename feel like
    // a network operation. `push` swallows its own failures.
    _sync = ref.read(seniorSettingsSyncProvider).push(settings);
  }

  /// Buttons are identified by id rather than label, so two buttons may share
  /// a name; the counter only has to avoid ids already in use.
  static String _freshId(List<LauncherApp> apps) {
    final taken = apps.map((a) => a.id).toSet();
    var n = apps.length + 1;
    while (taken.contains('app$n')) {
      n++;
    }
    return 'app$n';
  }

  static List<LauncherApp> _defaultsFor(ScreenMode mode) => switch (mode) {
    ScreenMode.easy => defaultEasyApps,
    ScreenMode.detailed => defaultDetailedApps,
  };
}

final seniorSettingsControllerProvider =
    AsyncNotifierProvider<SeniorSettingsController, SeniorSettings>(
      SeniorSettingsController.new,
    );
