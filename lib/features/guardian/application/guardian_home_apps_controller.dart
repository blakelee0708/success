import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import 'home_edit_allowance.dart';
import '../../../domain/app_category.dart';
import '../../../domain/launcher_app.dart';
import '../../../domain/senior_device.dart';
import '../../../domain/senior_readings.dart';
import '../../../domain/senior_profile.dart';
import 'guardian_session_controller.dart';

/// Which parent the dashboard is showing, when the guardian manages more than
/// one. Null means "whichever comes first", which is the only sensible answer
/// before they have chosen and the common case of exactly one parent.
class SelectedSeniorProfileId extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String id) => state = id;
}

final selectedSeniorProfileIdProvider =
    NotifierProvider<SelectedSeniorProfileId, String?>(
      SelectedSeniorProfileId.new,
    );

/// The parent every tab is about.
///
/// Falls back to the first linked profile rather than showing nothing, so a
/// guardian with one parent never has to make a choice to see their dashboard.
final selectedSeniorProfileProvider = Provider<SeniorProfile?>((ref) {
  final profiles = ref.watch(linkedSeniorProfilesProvider).value ?? const [];
  if (profiles.isEmpty) return null;
  final chosen = ref.watch(selectedSeniorProfileIdProvider);
  for (final profile in profiles) {
    if (profile.id == chosen) return profile;
  }
  return profiles.first;
});

/// The phone that parent is currently using, or null if none has connected.
final selectedSeniorDeviceProvider = FutureProvider<SeniorDevice?>((ref) async {
  final profile = ref.watch(selectedSeniorProfileProvider);
  if (profile == null) return null;
  return ref.watch(seniorLinkRepositoryProvider).activeDevice(profile.id);
});

/// What the guardian may know about that phone's state, which the free week
/// and then 안심 케어 decide. Separate from the device itself: which handset
/// is connected is 연결 관리 and stays free.
final seniorReadingsProvider = FutureProvider<SeniorReadings>((ref) async {
  final profile = ref.watch(selectedSeniorProfileProvider);
  if (profile == null) return SeniorReadings.none;
  return ref.watch(seniorLinkRepositoryProvider).readings(profile.id);
});

/// The buttons on the parent's launcher, edited from the guardian's phone.
///
/// Every edit is applied locally first and then written whole through
/// `replace_home_apps` — and rolled back if that write does not land. The
/// dashboard tells the guardian the change reaches their parent's phone
/// immediately, so a change still on screen after a failed write would be a
/// lie about someone else's phone.
/// What came of a guardian saving their parent's home screen.
enum HomeEditOutcome {
  saved,

  /// The free lifetime allowance is spent. Not a failure: it is where the
  /// screen offers 안심 케어 instead of apologising.
  allowanceSpent,

  /// The write did not reach the server.
  failed,
}

class GuardianHomeAppsController extends AsyncNotifier<List<LauncherApp>> {
  @override
  Future<List<LauncherApp>> build() async {
    final profile = ref.watch(selectedSeniorProfileProvider);
    if (profile == null) return const [];
    return ref.watch(homeAppsRepositoryProvider).fetch(profile.id);
  }

  Future<HomeEditOutcome> rename(String id, String label) => _write(
    (apps) => [
      for (final app in apps)
        if (app.id == id) app.copyWith(label: label) else app,
    ],
  );

  /// Pass null to drop back to the button's category colour.
  Future<HomeEditOutcome> setColor(String id, ButtonColor? color) => _write(
    (apps) => [
      for (final app in apps)
        if (app.id == id) app.withColor(color) else app,
    ],
  );

  Future<HomeEditOutcome> remove(String id) =>
      _write((apps) => [for (final app in apps) if (app.id != id) app]);

  Future<HomeEditOutcome> add({
    required String label,
    required AppCategory category,
    String? phoneNumber,
  }) => _write(
    (apps) => [
      ...apps,
      LauncherApp(
        id: _freshId(apps),
        label: label,
        category: category,
        phoneNumber: phoneNumber,
      ),
    ],
  );

  /// Both halves of a person button at once — see the senior-side twin.
  Future<HomeEditOutcome> editContact(
    String id, {
    required String label,
    required String phoneNumber,
  }) => _write(
    (apps) => [
      for (final app in apps)
        if (app.id == id)
          app.copyWith(label: label, phoneNumber: phoneNumber)
        else
          app,
    ],
  );

  /// Indices follow `ReorderableListView`: [newIndex] is read against the list
  /// as it still stands, before the dragged button is lifted out.
  Future<HomeEditOutcome> reorder(int oldIndex, int newIndex) => _write((apps) {
    if (oldIndex < 0 || oldIndex >= apps.length) return apps;
    final next = [...apps];
    final target = newIndex > oldIndex ? newIndex - 1 : newIndex;
    next.insert(target.clamp(0, next.length - 1), next.removeAt(oldIndex));
    return next;
  });

  /// What came of a save, in the three answers the screen needs.
  ///
  /// It was a bool, and the day the free allowance arrived that stopped being
  /// enough: `false` would have made 무료 2번을 다 쓰셨어요 look exactly like
  /// 부모님 폰에 닿지 않았어요, and one of those is an offer while the other
  /// is a fault.
  Future<HomeEditOutcome> _write(
    List<LauncherApp> Function(List<LauncherApp>) transform,
  ) async {
    final profile = ref.read(selectedSeniorProfileProvider);
    if (profile == null) return HomeEditOutcome.failed;

    // Asked **before** the write, not after. The server refuses either way,
    // but a guardian who learns it from an error has already made the
    // arrangement and watched it snap back - and the screen then has to
    // explain a failure instead of making an offer.
    if (!ref.read(homeEditAllowanceProvider).canEdit) {
      return HomeEditOutcome.allowanceSpent;
    }

    final before = state.value ?? const <LauncherApp>[];
    final after = transform(before);
    // Shown first: dragging a row that snaps back while a round trip finishes
    // is worse than one that moves and then reverts on a real failure.
    state = AsyncData(after);
    try {
      await ref.read(homeAppsRepositoryProvider).replace(profile.id, after);
      // The count lives on the profile row, and the server has just moved it.
      // Without this the screen goes on saying 2번 남았어요 until something
      // else happens to reload.
      ref.invalidate(linkedSeniorProfilesProvider);
      return HomeEditOutcome.saved;
    } on Object {
      state = AsyncData(before);
      return HomeEditOutcome.failed;
    }
  }

  /// Buttons are identified by id rather than label, so two may share a name;
  /// the counter only has to avoid ids already in use.
  static String _freshId(List<LauncherApp> apps) {
    final taken = apps.map((a) => a.id).toSet();
    var n = apps.length + 1;
    while (taken.contains('app$n')) {
      n++;
    }
    return 'app$n';
  }
}

final guardianHomeAppsProvider =
    AsyncNotifierProvider<GuardianHomeAppsController, List<LauncherApp>>(
      GuardianHomeAppsController.new,
    );
