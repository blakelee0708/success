library;

import '../../../domain/senior_profile.dart';

/// What is left of the four paid capabilities, as interfaces.
///
/// Two of the four have since been built, because neither needs a permission:
/// 안부 신호 (`SeniorPresenceReporter`) and the battery/ringer reading it
/// carries. What remains here is what still cannot be built or verified from
/// this environment.
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

/// The *background* half of 기기 상태, and the only half still missing.
///
/// The readings themselves now exist: the battery and the ringer ride on the
/// check-in the launcher already sends when the parent comes back to their
/// home screen, which is `SeniorPresenceReporter` and needs no permission, no
/// service and nothing from Play. `DeviceStatus` moved to the domain for that
/// reason, and the dashboard draws real numbers.
///
/// What this interface is still for is the five-minute figure
/// `06_PERMISSION_AND_POLICY` fixed: keeping the reading fresh while the phone
/// sits untouched. That needs a foreground service, which cannot be built or
/// verified from this environment — so it stays an interface, and the
/// dashboard states the age of every reading rather than implying one.
///
/// `latest` is gone: the reading is a column on the parent's device row now,
/// and an interface that returns null beside a screen showing a real number
/// would be the misleading one.
abstract interface class DeviceStatusSync {
  static const interval = Duration(minutes: 5);

  /// Starts the background schedule on the parent's phone. Must do nothing at
  /// all when [CareGate.isActive] is false.
  Future<void> start(String seniorProfileId);

  Future<void> stop();
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
