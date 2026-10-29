import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../domain/device_status.dart';
import '../../domain/guardian_account.dart';
import '../../domain/guardian_notice.dart';
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

  /// 계정 삭제, which Play's user-data policy requires an app to offer **in
  /// the app and from a web page** - and says in as many words that
  /// deactivating or suspending does not count.
  ///
  /// It does not reach the senior: they never make an account, their phone
  /// signs in anonymously, so the requirement is the guardian's alone.
  ///
  /// What survives is the part worth reading. The parent's profile and phone
  /// settings stay, because the parent is still holding that phone and a
  /// child deleting their own account must not collapse their mother's home
  /// screen. The messages stay too, with the sender removed: those are also
  /// something the parent received.
  Future<void> deleteGuardianAccount();

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
    String? appVersion,
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
  /// cannot be carved out of the table-level SELECT grant that
  /// `authenticated` holds - tried, and written into
  /// `20261026020000_push_token.sql` so nobody tries it twice.
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

  /// Which profile this install's active device row belongs to on the
  /// server, or null when it cannot say.
  ///
  /// **The phone does not otherwise find out it was moved.** 어머니 폰을
  /// 바꿨어요 is answered on the child's phone: the server moves the new
  /// handset's row onto the original profile and deletes the empty one this
  /// phone had saved. Nothing told this phone, so it went on asking about a
  /// profile that no longer existed and showed no family at all.
  Future<String?> profileOfThisPhone(String installId);

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
  Future<void> deleteGuardianAccount() async {
    await _call('delete_guardian_account', const {});
  }

  @override
  Future<void> registerPushToken(String token) async {
    await _call('register_guardian_push_token', {'p_token': token});
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
          .order('created_at', ascending: true);
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
    String? appVersion,
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
          // Why the guardian can be told 부모님 폰의 앱이 오래됐어요: Play
          // will not update the app that is in front of the user, and this
          // app is the home screen.
          'p_app_version': appVersion,
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
          // Named rather than `*`, and the list is the point rather than
          // style: **the readings are gone from it**, and that is the 안심
          // 케어 gate rather than tidying: `last_seen_at`, the battery and
          // the ringer are what the subscription buys, so the app asks
          // `senior_readings` for them and never selects them here. Which
          // phone is connected stays free - a family has to be able to see
          // they attached the right handset.
          .select(
            'id, install_id, is_active, device_label, platform, app_version',
          )
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

  @override
  Future<String?> profileOfThisPhone(String installId) async {
    try {
      // `senior_devices_read` lets a device read its own row by
      // `auth_user_id`, which is the row this asks about.
      final row = await _client
          .from('senior_devices')
          .select('senior_profile_id')
          .eq('install_id', installId)
          .eq('is_active', true)
          .maybeSingle();
      final id = row?['senior_profile_id'];
      return id is String ? id : null;
    } on Object {
      return null;
    }
  }

  /// For a function that **returns nothing** - PostgREST answers those with
  /// an empty body, which is success.
  ///
  /// They went through [_rpc] until 2026-10-29, which treats an answer with no
  /// row in it as a failure. That was right for the calls that need a row back
  /// and wrong for these two: `delete_guardian_account` **deleted the account
  /// on the server** and then the app said 지우지 못했어요, stayed signed in to
  /// an account that no longer existed, and never reached the sign-out. Found
  /// on a real phone. `register_guardian_push_token` had the same fault and it
  /// was invisible, because nothing waits on it - the token was stored and the
  /// app quietly believed it was not.
  Future<void> _call(String name, Map<String, Object?> params) async {
    try {
      await _client.rpc(name, params: params);
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

  /// Links waiting on the senior's own answer: profile id -> link id.
  ///
  /// **The twin attaches a guardian straight away and the server does not.**
  /// `claim_senior_pairing_code` and `create_senior_profile` both write `status = 'pending'` now, and the
  /// parent answers on their own phone before anything is shared. Mirroring
  /// that here by default would mean rewriting the harness of every test that
  /// connects a family, so it is behind [pendingLinkConsent] and the server
  /// rule is proved by `tool/verify_supabase_link_consent.py` instead.
  final Map<String, String> pendingLinks = {};

  /// Who is waiting, per profile. The card names them.
  final Map<String, String> pendingAskedBy = {};

  /// Whether the pairing twin leaves new links waiting, as the server does.
  bool pendingLinkConsent = false;

  /// Refuses a second parent. `exceptProfileId` is the reconnect case: a
  /// guardian re-entering a code for the parent they already have is not
  /// taking on another one.
  ///
  /// Always on, because the product is 1대1 - 무조건 자녀 하나, 부모 하나.
  void assertCanAddSenior({String? exceptProfileId}) {
    // Waiting links count, as `assert_can_add_senior` counts 'pending':
    // without them a second invite passed here and the server refused it.
    final mine = {
      ...rolesByProfile.entries
          .where((e) => e.value.containsKey(guardianAccountId))
          .map((e) => e.key),
      ...pendingAskedBy.entries
          .where((e) => e.value == guardianAccountId)
          .map((e) => e.key),
    }.where((id) => id != exceptProfileId);
    if (mine.isNotEmpty) {
      throw const SeniorLinkException('지금은 부모님 한 분만 연결할 수 있어요.');
    }
  }

  /// Refuses a second child on one parent.
  void assertCanAddGuardian(String profileId, String guardianId) {
    final others = {
      ...(rolesByProfile[profileId] ?? const {}).keys,
      ?pendingAskedBy[profileId],
    }.where((id) => id != guardianId);
    if (others.isNotEmpty) {
      throw const SeniorLinkException('부모님 한 분에 자녀 한 명만 연결할 수 있어요.');
    }
  }

  /// What the app owes this guardian, written by the pairing twin's
  /// [InMemoryPairingRepository.removeGuardianLink] the way
  /// `remove_guardian_link` writes `guardian_notices`.
  final List<GuardianNotice> notices = [];

  /// Takes a guardian off a profile, the way `'removed'` does on the server.
  ///
  /// The row is dropped rather than marked, which is the one place this twin
  /// is simpler than the database: nothing in the app reads a removed link,
  /// and RLS - the thing that actually makes a removal mean something - has
  /// no equivalent here at all. `tool/verify_supabase_leaving.py` is what
  /// proves the removal, and this is what lets a screen be driven.
  void unlink(String profileId, String guardianId) {
    rolesByProfile[profileId]?.remove(guardianId);
    if ((rolesByProfile[profileId] ?? const {}).isEmpty) {
      rolesByProfile.remove(profileId);
    }
    if (guardianId == guardianAccountId) linkedProfileIds.remove(profileId);
    pendingLinks.remove(profileId);
    pendingAskedBy.remove(profileId);
  }

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
  Future<void> deleteGuardianAccount() async {
    // Mirrors what the server keeps rather than what it deletes, because
    // what it keeps is the part a screen can get wrong: the profiles stay,
    // and only this guardian's links to them go.
    for (final profileId in [...linkedProfileIds]) {
      rolesByProfile[profileId]?.remove(guardianAccountId);
    }
    linkedProfileIds.clear();
    notices.clear();
  }

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
    assertCanAddSenior();
    _seq++;
    final profile = SeniorProfile(
      id: 'profile-$_seq',
      displayName: displayName,
      customerCode: 'CODE${_seq.toString().padLeft(4, '0')}',
      ageBand: ageBand,
    );
    profiles[profile.id] = profile;
    // The server leaves this waiting on the parent's own phone too, which it
    // has not got yet - the card is drawn the moment one connects. Behind
    // [pendingLinkConsent] for the same reason `claimSeniorPairingCode` is:
    // mirroring it by default would mean rewriting the harness of every test
    // that adds a parent.
    if (pendingLinkConsent) {
      pendingLinks[profile.id] = 'link-${profile.id}-$guardianAccountId';
      pendingAskedBy[profile.id] = guardianAccountId;
    } else {
      link(profile.id, guardianAccountId, 'primary');
    }
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

  /// Makes every call fail, the way a phone with no signal does.
  bool offline = false;

  @override
  Future<void> touchDevice(
    String installId, {
    DeviceStatus? status,
    String? appVersion,
  }) async {
    if (offline) throw const SeniorLinkException('연결하지 못했어요.');
    touchCount++;
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
        appVersion: appVersion ?? device.appVersion,
      );
    }
  }

  @override
  Future<SeniorProfile> fetchProfile(String seniorProfileId) async {
    final profile = profiles[seniorProfileId];
    if (profile == null) {
      throw const SeniorLinkException('부모님 정보를 찾지 못했어요.');
    }
    return profile;
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
  Future<String?> profileOfThisPhone(String installId) async =>
      activeDeviceByProfile.entries
          .where((e) => e.value.installId == installId)
          .map((e) => e.key)
          .firstOrNull;

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
    // `guardianHomeEdits`, so a settings push in a test silently refunded
    // the guardian's spent edits.
    profiles[seniorProfileId] = profile.copyWith(
      screenMode: screenMode ?? profile.screenMode,
      fontSize: fontSize ?? profile.fontSize,
      removedSlots: removedSlots ?? profile.removedSlots,
    );
  }
}
