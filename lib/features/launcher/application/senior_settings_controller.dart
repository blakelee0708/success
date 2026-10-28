import 'dart:typed_data';

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

  /// Renames or recolours one of the four slot buttons, adding it to the
  /// saved list the first time somebody does.
  ///
  /// They are not in either screen's defaults - seeding them changed the
  /// count and order of `defaultDetailedApps`, which the spec fixes - so a
  /// saved list holds one only once it has been edited. Until then the home
  /// screen falls back to [fixedSlotApps], which is also what covers settings
  /// written before these existed.
  Future<void> editFixedSlot(
    AppCategory category, {
    String? label,
    ButtonColor? color,
    bool clearColor = false,
  }) async {
    final current = state.value ?? const SeniorSettings();
    final apps = [...current.apps];
    final at = apps.indexWhere((a) => a.category == category);
    final base = at >= 0
        ? apps[at]
        : fixedSlotApps.firstWhere((a) => a.category == category);
    var next = label == null ? base : base.copyWith(label: label);
    if (clearColor || color != null) next = next.withColor(color);
    if (at >= 0) {
      apps[at] = next;
    } else {
      apps.add(next);
    }
    await _write(current.copyWith(apps: List.unmodifiable(apps)));
  }

  /// Returns false when the home screen is already at [minimumHomeButtons]
  /// and nothing was removed.
  ///
  /// The guard is here rather than only on the screen, because both phones
  /// call it: the senior's 앱 설정 and the guardian's 홈 화면 are two ways to
  /// the same list, and a floor that lived on one of them would not be a
  /// floor.
  Future<bool> removeApp(String id) async {
    final current = state.value ?? const SeniorSettings();
    if (!current.canRemoveButton) return false;
    // A slot button is remembered as removed rather than merely dropped from
    // the list. Absence has always meant *nobody has edited this yet, use the
    // default*, which is what still draws all four on a settings file written
    // before they existed; reading absence as removal would empty those
    // screens the moment this shipped.
    final slot = _slotCategoryOf(current, id);
    await _write(
      current.copyWith(
        // A slot button **stays in the list**, marked removed. Dropping the
        // row would throw away the name and colour the family gave it, and
        // putting it back later would hand the senior a button called 가족
        // where theirs said 영희. Nothing draws it: `slot` answers null while
        // the kind is in `removedSlots`, and `seniorGridApps` has never let
        // one into the grid.
        apps: slot != null
            ? current.apps
            : current.apps.where((a) => a.id != id).toList(growable: false),
        removedSlots: slot == null
            ? current.removedSlots
            : {...current.removedSlots, slot},
      ),
    );
    return true;
  }

  /// Which slot kind [id] names, or null for an ordinary button.
  static AppCategory? _slotCategoryOf(SeniorSettings current, String id) {
    for (final app in [...current.apps, ...fixedSlotApps]) {
      if (app.id == id && app.category.fixedSlot) return app.category;
    }
    return null;
  }

  /// Puts a slot button back where it was.
  ///
  /// Not [addApp]: that mints a fresh id and appends to the grid, and these
  /// four are not grid buttons. The canonical button comes back with whatever
  /// name and colour the family had given it, because removing one was never
  /// meant to throw that away.
  Future<void> restoreSlot(AppCategory category) async {
    final current = state.value ?? const SeniorSettings();
    if (!category.fixedSlot) return;
    final removed = {...current.removedSlots}..remove(category);
    final apps = [...current.apps];
    if (!apps.any((a) => a.category == category)) {
      apps.add(fixedSlotApps.firstWhere((a) => a.category == category));
    }
    await _write(
      current.copyWith(apps: List.unmodifiable(apps), removedSlots: removed),
    );
  }

  /// Indices follow `ReorderableListView`: [newIndex] is read against the list
  /// as it still stands, before the dragged button is lifted out, so a move
  /// downward has to shed one place once it is.
  ///
  /// **The indices are the grid's, not the saved list's.** A slot button
  /// joins `apps` as soon as somebody renames or recolours it, and it is
  /// never drawn in the reorderable list - so a saved list holding one would
  /// have made every index after it off by one, and a drag would have moved
  /// the wrong button.
  Future<void> reorderApps(int oldIndex, int newIndex) async {
    final current = state.value ?? const SeniorSettings();
    final grid = [...seniorGridApps(current.apps)];
    final slots = [
      for (final app in current.apps)
        if (app.category.fixedSlot) app,
    ];
    if (oldIndex < 0 || oldIndex >= grid.length) return;
    final target = newIndex > oldIndex ? newIndex - 1 : newIndex;
    final moved = grid.removeAt(oldIndex);
    grid.insert(target.clamp(0, grid.length), moved);
    // The slots go at the end and their order there means nothing: the home
    // screens look each one up by kind, not by position.
    await _write(current.copyWith(apps: [...grid, ...slots]));
  }

  Future<void> addApp({
    required String label,
    required AppCategory category,
    String? phoneNumber,
    String? packageName,
    Uint8List? iconBytes,
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
            packageName: packageName,
            iconBytes: iconBytes,
          ),
        ],
      ),
    );
  }

  /// Fills in an app button the guardian put there, once the senior has
  /// picked from their own phone's list.
  ///
  /// The label becomes the app's own name rather than whatever the guardian
  /// wrote on the slot: the tile is named after what it opens, and a 고스톱
  /// button that opens the bank is worse than one named 은행.
  Future<void> chooseInstalledApp(
    String id, {
    required String label,
    required String packageName,
    Uint8List? iconBytes,
  }) async {
    final current = state.value ?? const SeniorSettings();
    await _write(
      current.copyWith(
        apps: [
          for (final app in current.apps)
            if (app.id == id)
              app.copyWith(
                label: label,
                packageName: packageName,
                iconBytes: iconBytes,
              )
            else
              app,
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
