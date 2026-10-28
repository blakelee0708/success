import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../domain/device_status.dart';
import '../../domain/guardian_account.dart';
import '../../domain/senior_device.dart';
import '../../domain/senior_readings.dart';
import '../../domain/app_category.dart';
import '../../domain/senior_profile.dart';
import '../../domain/senior_settings.dart';

/// Raised when the server refuses a linking step for a reason worth showing.
class SeniorLinkException implements Exception {
  const SeniorLinkException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Creating and connecting the two halves of a family: the guardian's account,
/// the parent's profile, and the parent's phone.
///
/// Every write goes through a database function rather than a table. A profile
/// and its link have to be created together — a profile with no link is a row
/// that RLS makes unreadable to the person who just created it — and retiring
/// the previous phone touches a row the new phone does not own.
abstract interface class SeniorLinkRepository {
  /// The guardian's own row, created on first sign-in and safe to call again.
  Future<GuardianAccount> ensureGuardianAccount({
    String? displayName,
    String? phoneNumber,
  });

  /// Records where this guardian's phone can be reached, so their parent's
  /// message can arrive as a notification rather than only as a number on a
  /// tab they have to open first.
  ///
  /// Its own call rather than a column on something else, because the
  /// guardian's half has no equivalent of the senior's check-in to ride on.
  /// It is cheap and idempotent, so the dashboard makes it on every open -
  /// which is what keeps it fresh, and a token **rotates**.
  Future<void> registerPushToken(String token);

  Future<SeniorProfile> createSeniorProfile({
    required String displayName,
    String? ageBand,
  });

  Future<List<SeniorProfile>> linkedSeniorProfiles();

  /// Called from the parent's phone: claims [customerCode] for this install and
  /// retires whichever phone held the profile before.
  Future<SeniorProfile> registerSeniorDevice({
    required String customerCode,
    required String installId,
    String? deviceLabel,
    String? platform,
    String? osVersion,
  });

  /// 안부 신호 — the parent's phone saying it is still in use.
  ///
  /// Costs no permission and carries no reading: the launcher came to the
  /// foreground, which on a phone whose home screen it is means the parent
  /// unlocked it or came back from another app. Called often and never
  /// awaited by anything the senior is looking at.
  ///
  /// [status] rides along rather than going on a schedule of its own: a
  /// reading is worth having exactly when the parent used the phone, and a
  /// second trip would be a second thing to fail. Null when this phone could
  /// read nothing, which leaves whatever was last reported standing.
  Future<void> touchDevice(
    String installId, {
    DeviceStatus? status,
    String? pushToken,
  });

  Future<SeniorProfile> fetchProfile(String seniorProfileId);

  /// The phone currently carrying this profile, or null when none has
  /// connected yet. Only the active one: a retired install is history, and
  /// showing it would tell the guardian their parent is set up when they are
  /// holding a different phone.
  Future<SeniorDevice?> activeDevice(String seniorProfileId);

  /// What the guardian may know about that phone's state, which is a
  /// different question from which phone it is.
  ///
  /// Goes through `senior_readings` rather than reading the device row,
  /// because the gate has to live somewhere the app cannot skip and a column
  /// cannot be carved out of the table-level SELECT grant - tried for
  /// `push_token`, written into its migration so nobody tries it twice.
  Future<SeniorReadings> readings(String seniorProfileId);

  /// 문의하기's number: six digits the senior reads out to the support desk.
  ///
  /// **It creates the profile when this install has none**, which is the
  /// point. The senior this is for has no family on the phone at all, so
  /// nothing has ever made one for them - and a number is the only thing in
  /// the app that has to work for somebody with nobody to ask. Showing a
  /// pairing code does the same thing, and 연결됨 has never meant *a profile
  /// exists*; it means a guardian is attached.
  Future<String?> supportCode(String installId, {String? platform});

  /// Pushes the two settings that live on the profile rather than in
  /// `home_apps`, so the guardian's dashboard can show what the parent chose.
  Future<void> updateProfileSettings(
    String seniorProfileId, {
    ScreenMode? screenMode,
    FontSize? fontSize,
    Set<AppCategory>? removedSlots,
  });
}

class SupabaseSeniorLinkRepository implements SeniorLinkRepository {
  SupabaseSeniorLinkRepository(this._client);

  final sb.SupabaseClient _client;

  @override
  Future<GuardianAccount> ensureGuardianAccount({
    String? displayName,
    String? phoneNumber,
  }) async {
    final row = await _rpc('ensure_guardian_account', {
      'p_display_name': displayName,
      'p_phone_number': phoneNumber,
    });
    final account = GuardianAccount.fromRow(row);
    if (account == null) {
      throw const SeniorLinkException('보호자 계정을 만들지 못했어요.');
    }
    return account;
  }

  @override
  Future<void> registerPushToken(String token) async {
    await _rpc('register_guardian_push_token', {'p_token': token});
  }

  @override
  Future<SeniorProfile> createSeniorProfile({
    required String displayName,
    String? ageBand,
  }) async {
    final row = await _rpc('create_senior_profile', {
      'p_display_name': displayName,
      'p_age_band': ageBand,
    });
    return _profile(row, '부모님을 추가하지 못했어요.');
  }

  @override
  Future<List<SeniorProfile>> linkedSeniorProfiles() async {
    try {
      final rows = await _client
          .from('senior_profiles')
          .select()
          .order('created_at');
      return [for (final row in rows) ?SeniorProfile.fromRow(row)];
    } on sb.PostgrestException catch (e) {
      throw SeniorLinkException(e.message);
    }
  }

  @override
  Future<SeniorProfile> registerSeniorDevice({
    required String customerCode,
    required String installId,
    String? deviceLabel,
    String? platform,
    String? osVersion,
  }) async {
    final code = customerCode.trim().toUpperCase();
    try {
      final row = await _rpc('register_senior_device', {
        'p_customer_code': code,
        'p_install_id': installId,
        'p_device_label': deviceLabel,
        'p_platform': platform,
        'p_os_version': osVersion,
      });
      return _profile(row, '연결하지 못했어요.');
    } on SeniorLinkException catch (e) {
      // The function raises on a code nobody holds; that is the one failure the
      // person typing can actually fix, so it gets its own wording.
      if (e.message.contains('unknown customer code')) {
        throw const SeniorLinkException('연결 번호가 맞지 않아요. 다시 확인해 주세요.');
      }
      rethrow;
    }
  }

  @override
  Future<void> touchDevice(
    String installId, {
    DeviceStatus? status,
    String? pushToken,
  }) async {
    try {
      await _client.rpc(
        'touch_senior_device',
        params: {
          'p_install_id': installId,
          'p_battery_percent': status?.batteryPercent,
          'p_is_charging': status?.isCharging,
          'p_ringer_mode': status?.ringer?.name,
          'p_status_read_at': status?.readAt.toUtc().toIso8601String(),
          // Coalesced server-side like the rest: a resume that could not read
          // a token leaves the last good one in place.
          'p_push_token': pushToken,
        },
      );
    } on sb.PostgrestException catch (e) {
      throw SeniorLinkException(e.message);
    }
  }

  @override
  Future<SeniorProfile> fetchProfile(String seniorProfileId) async {
    try {
      final row = await _client
          .from('senior_profiles')
          .select()
          .eq('id', seniorProfileId)
          .maybeSingle();
      if (row == null) {
        throw const SeniorLinkException('부모님 정보를 찾지 못했어요.');
      }
      return _profile(row, '부모님 정보를 읽지 못했어요.');
    } on sb.PostgrestException catch (e) {
      throw SeniorLinkException(e.message);
    }
  }

  @override
  Future<SeniorDevice?> activeDevice(String seniorProfileId) async {
    try {
      final row = await _client
          .from('senior_devices')
          // Named rather than `*`, because `push_token` is revoked from
          // `authenticated` and a `select *` would be refused outright. See
          // `20261026020000_push_token.sql`.
          //
          // **The readings are gone from this list**, and that is the 안심
          // 케어 gate rather than tidying: `last_seen_at`, the battery and
          // the ringer are what the subscription buys, so the app asks
          // `senior_readings` for them and never selects them here. Which
          // phone is connected stays free - a family has to be able to see
          // they attached the right handset.
          .select('id, install_id, is_active, device_label, platform')
          .eq('senior_profile_id', seniorProfileId)
          .eq('is_active', true)
          .maybeSingle();
      return row == null ? null : SeniorDevice.fromRow(row);
    } on sb.PostgrestException catch (e) {
      throw SeniorLinkException(e.message);
    }
  }

  @override
  Future<SeniorReadings> readings(String seniorProfileId) async {
    try {
      final rows = await _client.rpc(
        'senior_readings',
        params: {'p_senior_profile_id': seniorProfileId},
      );
      if (rows is! List || rows.isEmpty) return SeniorReadings.none;
      return SeniorReadings.fromRow(
        (rows.first as Map).cast<String, Object?>(),
      );
    } on sb.PostgrestException catch (e) {
      throw SeniorLinkException(e.message);
    }
  }

  @override
  Future<void> updateProfileSettings(
    String seniorProfileId, {
    ScreenMode? screenMode,
    FontSize? fontSize,
    Set<AppCategory>? removedSlots,
  }) async {
    final patch = <String, Object?>{
      if (screenMode != null) 'screen_mode': screenMode.name,
      if (fontSize != null) 'font_size': fontSize.name,
      // Written whole rather than added to: this is what is *off* the screen,
      // so an empty list is the meaningful answer "nothing is".
      if (removedSlots != null)
        'removed_slots': [for (final c in removedSlots) c.name],
    };
    if (patch.isEmpty) return;
    try {
      await _client
          .from('senior_profiles')
          .update(patch)
          .eq('id', seniorProfileId);
    } on sb.PostgrestException catch (e) {
      throw SeniorLinkException(e.message);
    }
  }

  @override
  Future<String?> supportCode(String installId, {String? platform}) async {
    try {
      final code = await _client.rpc(
        'ensure_senior_support_code',
        params: {'p_install_id': installId, 'p_platform': platform},
      );
      return code is String && code.isNotEmpty ? code : null;
    } on sb.PostgrestException catch (e) {
      throw SeniorLinkException(e.message);
    }
  }

  Future<Map<String, Object?>> _rpc(
    String name,
    Map<String, Object?> params,
  ) async {
    try {
      final result = await _client.rpc(name, params: params);
      if (result is Map<String, Object?>) return result;
      if (result is List && result.isNotEmpty) {
        final first = result.first;
        if (first is Map<String, Object?>) return first;
      }
      throw SeniorLinkException('$name 응답을 읽지 못했어요.');
    } on sb.PostgrestException catch (e) {
      throw SeniorLinkException(e.message);
    }
  }

  static SeniorProfile _profile(Map<String, Object?> row, String onFailure) {
    final profile = SeniorProfile.fromRow(row);
    if (profile == null) throw SeniorLinkException(onFailure);
    return profile;
  }
}

/// Stand-in used when the build carries no Supabase keys, and by tests.
///
/// Enforces the same two rules the database does: a profile is only visible to
/// a guardian linked to it, and only one install is live per profile.
class InMemorySeniorLinkRepository implements SeniorLinkRepository {
  InMemorySeniorLinkRepository({this.guardianAuthUserId = 'guardian-1'});

  final String guardianAuthUserId;

  final Map<String, SeniorProfile> profiles = {};
  final Map<String, SeniorDevice> activeDeviceByProfile = {};

  /// Whether this twin hands the readings over.
  ///
  /// **It does not simulate the clock**, deliberately: the real rule is a
  /// week from the first link, then a subscription, and reproducing it here
  /// would be a second copy that could drift from the server's.
  /// `tool/verify_supabase_pricing.py` proves the rule; this is the switch a
  /// widget test flips to see both screens.
  bool readingsVisible = true;

  /// What the trial countdown reads. Null means say nothing about it.
  DateTime? trialEndsAt;
  final List<String> linkedProfileIds = [];

  /// profile id -> guardian account id -> role. Phase 5 gave a profile more
  /// than one guardian, so a flat list of ids no longer says enough.
  final Map<String, Map<String, String>> rolesByProfile = {};

  /// guardian account id -> display name. The real `guardiansFor` joins
  /// `guardian_accounts` to get this; without it here the twin answered with
  /// nameless guardians and the home screen quietly fell back to "가족" while
  /// its test passed for the wrong reason.
  final Map<String, String> guardianNames = {};

  /// guardian account id -> phone number, the other half of what the real
  /// `guardians_for_senior` returns. Optional there and optional here.
  final Map<String, String> guardianPhones = {};

  /// Who [resolvePrimaryGuardian] is waiting on, per profile.
  final Map<String, String> pendingPrimaryByProfile = {};

  /// The install this fake treats as the senior's own phone, so the twin can
  /// enforce "only the senior device may answer" the way the database does.
  String? seniorInstallId;

  GuardianAccount? _account;
  int _seq = 0;

  /// The guardian account id, creating it on demand the way the RPC does.
  String get guardianAccountId => (_account ??= GuardianAccount(
    id: 'account-1',
    authUserId: guardianAuthUserId,
  )).id;

  /// Registers a profile as belonging to [role], used by the pairing twin.
  void link(String profileId, String guardianId, String role) {
    (rolesByProfile[profileId] ??= {})[guardianId] = role;
    if (guardianId == guardianAccountId &&
        !linkedProfileIds.contains(profileId)) {
      linkedProfileIds.add(profileId);
    }
  }

  /// Adds a profile the way the pairing functions do, without a guardian.
  SeniorProfile addProfile(String displayName) {
    _seq++;
    final profile = SeniorProfile(
      id: 'profile-$_seq',
      displayName: displayName,
      customerCode: 'CODE${_seq.toString().padLeft(4, '0')}',
    );
    profiles[profile.id] = profile;
    return profile;
  }

  /// Records the senior's answer to 안심 케어, the way `resolve_care_consent`
  /// does. Kept on the store rather than the subscription twin because the
  /// profile is where the app reads it from.
  void setConsent(String profileId, PaidConsentStatus status) {
    final profile = profiles[profileId];
    if (profile == null) return;
    profiles[profileId] = profile.copyWith(paidConsentStatus: status);
  }

  /// How many remote home-screen saves this family has spent, for the tests
  /// that drive the free allowance. The server counts the real ones.
  void setGuardianHomeEdits(String profileId, int used) {
    final profile = profiles[profileId];
    if (profile == null) return;
    profiles[profileId] = profile.copyWith(guardianHomeEdits: used);
  }

  void rename(String profileId, String displayName) {
    final profile = profiles[profileId];
    if (profile == null) return;
    profiles[profileId] = profile.copyWith(displayName: displayName);
  }

  /// Retires whichever install held the profile and makes this one live.
  void attachDevice(String profileId, String installId, {String? platform}) {
    activeDeviceByProfile[profileId] = SeniorDevice(
      id: 'device-${activeDeviceByProfile.length + 1}',
      installId: installId,
      isActive: true,
      platform: platform,
    );
    seniorInstallId = installId;
  }

  @override
  Future<GuardianAccount> ensureGuardianAccount({
    String? displayName,
    String? phoneNumber,
  }) async {
    final account = _account = GuardianAccount(
      id: _account?.id ?? 'account-1',
      authUserId: guardianAuthUserId,
      displayName: displayName ?? _account?.displayName,
      phoneNumber: phoneNumber ?? _account?.phoneNumber,
      email: _account?.email,
    );
    if (account.displayName case final name?) guardianNames[account.id] = name;
    if (account.phoneNumber case final number?) {
      guardianPhones[account.id] = number;
    }
    return account;
  }

  /// Every token this guardian has reported, in order, so a test can see that
  /// a rotation lands rather than only that something was called once.
  final guardianPushTokens = <String>[];

  @override
  Future<void> registerPushToken(String token) async {
    if (_account == null) {
      throw const SeniorLinkException('보호자 계정이 없어요.');
    }
    guardianPushTokens.add(token);
  }

  @override
  Future<SeniorProfile> createSeniorProfile({
    required String displayName,
    String? ageBand,
  }) async {
    if (_account == null) {
      throw const SeniorLinkException('보호자 계정이 없어요.');
    }
    _seq++;
    final profile = SeniorProfile(
      id: 'profile-$_seq',
      displayName: displayName,
      customerCode: 'CODE${_seq.toString().padLeft(4, '0')}',
      ageBand: ageBand,
    );
    profiles[profile.id] = profile;
    link(profile.id, guardianAccountId, 'primary');
    return profile;
  }

  @override
  Future<List<SeniorProfile>> linkedSeniorProfiles() async => [
    for (final id in linkedProfileIds) ?profiles[id],
  ];

  @override
  Future<SeniorProfile> registerSeniorDevice({
    required String customerCode,
    required String installId,
    String? deviceLabel,
    String? platform,
    String? osVersion,
  }) async {
    final code = customerCode.trim().toUpperCase();
    final match = profiles.values.where((p) => p.customerCode == code);
    if (match.isEmpty) {
      throw const SeniorLinkException('연결 번호가 맞지 않아요. 다시 확인해 주세요.');
    }
    final profile = match.first;
    attachDevice(profile.id, installId, platform: platform);
    return profile;
  }

  /// How many times this phone has reported in, for the tests.
  int touchCount = 0;

  /// The FCM address each phone last reported, keyed by install id — the
  /// in-memory stand-in for `senior_devices.push_token`.
  final Map<String, String> pushTokenByInstallId = {};

  /// Makes every call fail, the way a phone with no signal does.
  bool offline = false;

  @override
  Future<void> touchDevice(
    String installId, {
    DeviceStatus? status,
    String? pushToken,
  }) async {
    if (offline) throw const SeniorLinkException('연결하지 못했어요.');
    touchCount++;
    if (pushToken != null) pushTokenByInstallId[installId] = pushToken;
    for (final entry in activeDeviceByProfile.entries) {
      final device = entry.value;
      if (device.installId != installId) continue;
      activeDeviceByProfile[entry.key] = SeniorDevice(
        id: device.id,
        installId: device.installId,
        isActive: device.isActive,
        deviceLabel: device.deviceLabel,
        platform: device.platform,
        lastSeenAt: DateTime.now(),
        // A phone that could read nothing leaves the last real reading
        // standing rather than wiping it.
        status: status ?? device.status,
      );
    }
  }

  @override
  Future<SeniorProfile> fetchProfile(String seniorProfileId) async {
    final profile = profiles[seniorProfileId];
    if (profile == null) {
      throw const SeniorLinkException('부모님 정보를 찾지 못했어요.');
    }
    return SeniorProfile(
      id: profile.id,
      displayName: profile.displayName,
      customerCode: profile.customerCode,
      ageBand: profile.ageBand,
      screenMode: profile.screenMode,
      fontSize: profile.fontSize,
      paidConsentStatus: profile.paidConsentStatus,
      pendingPrimaryGuardianId: pendingPrimaryByProfile[seniorProfileId],
    );
  }

  @override
  Future<SeniorDevice?> activeDevice(String seniorProfileId) async =>
      activeDeviceByProfile[seniorProfileId];

  @override
  Future<SeniorReadings> readings(String seniorProfileId) async {
    final device = activeDeviceByProfile[seniorProfileId];
    // No phone attached is not the same as withheld, and the dashboard has a
    // different sentence for each - only one of them is an offer.
    if (device == null) return SeniorReadings.none;
    if (!readingsVisible) {
      return SeniorReadings(visible: false, trialEndsAt: trialEndsAt);
    }
    return SeniorReadings(
      visible: true,
      trialEndsAt: trialEndsAt,
      lastSeenAt: device.lastSeenAt,
      status: device.status,
    );
  }

  /// The number 문의하기 shows. Fixed rather than random so a screenshot and
  /// a test can both name it.
  String supportCodeValue = '482913';

  @override
  Future<String?> supportCode(String installId, {String? platform}) async {
    if (offline) throw const SeniorLinkException('번호를 읽지 못했어요.');
    return supportCodeValue;
  }

  @override
  Future<void> updateProfileSettings(
    String seniorProfileId, {
    ScreenMode? screenMode,
    FontSize? fontSize,
    Set<AppCategory>? removedSlots,
  }) async {
    final profile = profiles[seniorProfileId];
    if (profile == null) return;
    // `copyWith`, not a rebuild by hand. Listing the fields dropped
    // `pendingPrimaryGuardianId` and `guardianHomeEdits`, so a settings push
    // in a test silently cancelled a pending handover and refunded the
    // guardian's spent edits.
    profiles[seniorProfileId] = profile.copyWith(
      screenMode: screenMode ?? profile.screenMode,
      fontSize: fontSize ?? profile.fontSize,
      removedSlots: removedSlots ?? profile.removedSlots,
    );
  }
}
