library;

import '../../../domain/senior_profile.dart';

/// The four paid capabilities, as interfaces only.
///
/// `07_PHASE_PLAN` asks Phase 6 for a *location interface*, an *unknown-contact
/// call alert interface*, an *app install alert interface* and a *5-minute
/// background sync interface* — not the implementations. That is deliberate,
/// and `06_PERMISSION_AND_POLICY` says why: every one of these needs a system
/// permission whose Play policy has to be cleared first, and two of them
/// (background location, phone state) are the kind of permission a store review
/// rejects an app for asking about carelessly.
///
/// So each is declared here with the shape it will have and the rule it has to
/// obey, and each has exactly one implementation today: one that does nothing
/// and says so. Nothing may pretend to have a reading it does not have — a
/// dashboard whose job is to reassure is the worst place to guess.
///
/// Every one of them must be gated on [CareGate.isActive] before it runs. A
/// paid subscription without the senior's consent has to behave exactly like no
/// subscription at all.


/// Whether the paid features may run for a parent at all.
abstract interface class CareGate {
  /// True only when 안심 케어 is both paid for and consented to.
  Future<bool> isActive(String seniorProfileId);
}

/// Battery, ringer and network, read on a schedule.
///
/// Five minutes is the MVP figure from `06_PERMISSION_AND_POLICY`. The guardian
/// dashboard says so out loud, because a reading with no stated age is
/// indistinguishable from a current one.
abstract interface class DeviceStatusSync {
  static const interval = Duration(minutes: 5);

  /// Null when nothing has been collected yet — which is the honest answer
  /// until this is implemented, and the state the dashboard already renders.
  Future<DeviceStatus?> latest(String seniorProfileId);

  /// Starts reporting from the parent's phone. Must do nothing at all when
  /// [CareGate.isActive] is false.
  Future<void> start(String seniorProfileId);

  Future<void> stop();
}

/// One reading of the parent's phone.
class DeviceStatus {
  const DeviceStatus({
    required this.readAt,
    this.batteryPercent,
    this.ringerPercent,
    this.isOnline,
  });

  final DateTime readAt;
  final int? batteryPercent;
  final int? ringerPercent;
  final bool? isOnline;
}

/// Where the parent is, checked periodically.
///
/// Named for what it does. `06_PERMISSION_AND_POLICY` forbids calling this
/// real-time tracking, and that is not a wording preference: how the feature is
/// described is what the senior is consenting to, so a class called
/// `LiveLocationTracker` would make the consent screen a misrepresentation.
///
/// A refused permission turns the feature off and tells the guardian
/// `부모님이 위치 권한을 허락하지 않았어요`. It does not ask again.
abstract interface class PeriodicLocationCheck {
  static const interval = Duration(minutes: 5);

  Future<void> start(String seniorProfileId);
  Future<void> stop();
}

/// Calls to or from numbers the parent has no contact for.
///
/// Scoped exactly as `06_PERMISSION_AND_POLICY` scopes it: whether the number
/// is in the contact list, and nothing else. No call content is examined and no
/// spam database is consulted — which is also why the guardian-facing feature
/// named in `06_PERMISSION_AND_POLICY` and is the reason this is an interface.
abstract interface class AppInstallWatcher {
  Future<void> start(String seniorProfileId);
  Future<void> stop();
}

/// The only implementations that exist today.
///
/// Not a stub that returns plausible numbers — one that returns nothing, so a
/// screen wired to it has to render its empty state and cannot accidentally
/// ship fabricated readings.
class UnimplementedDeviceStatusSync implements DeviceStatusSync {
  const UnimplementedDeviceStatusSync();

  @override
  Future<DeviceStatus?> latest(String seniorProfileId) async => null;

  @override
  Future<void> start(String seniorProfileId) async {}

  @override
  Future<void> stop() async {}
}

class UnimplementedPeriodicLocationCheck implements PeriodicLocationCheck {
  const UnimplementedPeriodicLocationCheck();

  @override
  Future<void> start(String seniorProfileId) async {}

  @override
  Future<void> stop() async {}
}

class UnimplementedAppInstallWatcher implements AppInstallWatcher {
  const UnimplementedAppInstallWatcher();

  @override
  Future<void> start(String seniorProfileId) async {}

  @override
  Future<void> stop() async {}
}

/// Reads the gate from the profile the app already has.
///
/// Both halves matter, and the consent one is the one that decides: a paid
/// subscription whose senior said no must be indistinguishable from no
/// subscription.
bool careIsActiveFor({
  required SeniorProfile profile,
  required bool hasActiveCareSubscription,
}) =>
    hasActiveCareSubscription &&
    profile.paidConsentStatus == PaidConsentStatus.granted;
