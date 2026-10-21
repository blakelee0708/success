import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../domain/pair_link.dart';
import '../../domain/senior_profile.dart';
import 'senior_link_repository.dart';

/// Everything Phase 5 adds: the two ways a family gets connected, getting a
/// replaced phone back onto its profile, inviting a sibling, and moving who
/// the primary guardian is.
///
/// Every call is a database function. Redeeming a code is the case where the
/// caller cannot yet be allowed to read the row they are about to use, so none
/// of this can be table access.
abstract interface class PairingRepository {
  // --- 경로 B: the parent's phone shows a code -------------------------------

  /// Called by the parent's phone with no guardian involved. Creates the
  /// profile if this install has none, and returns the 4-digit code to show.
  Future<PairLink> startSeniorPairing({
    required String installId,
    String? deviceLabel,
    String? platform,
    String? osVersion,
  });

  /// Called by the guardian typing what their parent read out. The code cannot
  /// carry a name or a number, so both are supplied here.
  Future<SeniorProfile> claimSeniorPairingCode({
    required String code,
    required String displayName,
    String? phoneNumber,
  });

  // --- 경로 A: the guardian texts an install link ----------------------------

  /// Creates the parent's profile and the invite that goes in the message.
  Future<PairLink> createSeniorInvite({required String displayName});

  /// Called by the parent's phone. The token comes from the install link; the
  /// code is the fallback for when the Play referrer did not survive the
  /// install, which is most installs that did not come from the store.
  Future<SeniorProfile> redeemSeniorInvite({
    required String installId,
    String? token,
    String? code,
    String? deviceLabel,
    String? platform,
    String? osVersion,
  });

  // --- Recovery -------------------------------------------------------------

  Future<PairLink> createRecoveryCode(String seniorProfileId);

  /// Restores the existing profile onto a new install rather than making a
  /// second parent, and retires whichever phone held it before.
  Future<SeniorProfile> redeemRecoveryCode({
    required String code,
    required String installId,
    String? deviceLabel,
    String? platform,
    String? osVersion,
  });

  // --- Family guardians -----------------------------------------------------

  Future<PairLink> createFamilyInvite(String seniorProfileId);

  Future<SeniorProfile> redeemFamilyInvite(String code);

  /// Everyone looking after this parent. Includes the caller.
  Future<List<GuardianLink>> guardiansFor(String seniorProfileId);

  // --- Primary guardian -----------------------------------------------------

  /// Asks to take over as primary. Nothing changes until the senior's phone
  /// answers.
  Future<void> requestPrimaryGuardian(String seniorProfileId);

  /// Answered on the senior's phone, and nowhere else.
  Future<void> resolvePrimaryGuardian(String seniorProfileId, bool approve);
}

class SupabasePairingRepository implements PairingRepository {
  SupabasePairingRepository(this._client);

  final sb.SupabaseClient _client;

  @override
  Future<PairLink> startSeniorPairing({
    required String installId,
    String? deviceLabel,
    String? platform,
    String? osVersion,
  }) async => _link(await _rpc('start_senior_pairing', {
    'p_install_id': installId,
    'p_device_label': deviceLabel,
    'p_platform': platform,
    'p_os_version': osVersion,
  }));

  @override
  Future<SeniorProfile> claimSeniorPairingCode({
    required String code,
    required String displayName,
    String? phoneNumber,
  }) async => _profile(await _rpc('claim_senior_pairing_code', {
    'p_code': code.trim(),
    'p_display_name': displayName.trim(),
    'p_phone_number': phoneNumber,
  }));

  @override
  Future<PairLink> createSeniorInvite({required String displayName}) async =>
      _link(await _rpc('create_senior_invite', {
        'p_display_name': displayName.trim(),
      }));

  @override
  Future<SeniorProfile> redeemSeniorInvite({
    required String installId,
    String? token,
    String? code,
    String? deviceLabel,
    String? platform,
    String? osVersion,
  }) async => _profile(await _rpc('redeem_senior_invite', {
    'p_install_id': installId,
    'p_token': token?.trim(),
    'p_code': code?.trim(),
    'p_device_label': deviceLabel,
    'p_platform': platform,
    'p_os_version': osVersion,
  }));

  @override
  Future<PairLink> createRecoveryCode(String seniorProfileId) async =>
      _link(await _rpc('create_recovery_code', {
        'p_senior_profile_id': seniorProfileId,
      }));

  @override
  Future<SeniorProfile> redeemRecoveryCode({
    required String code,
    required String installId,
    String? deviceLabel,
    String? platform,
    String? osVersion,
  }) async => _profile(await _rpc('redeem_recovery_code', {
    'p_code': code.trim(),
    'p_install_id': installId,
    'p_device_label': deviceLabel,
    'p_platform': platform,
    'p_os_version': osVersion,
  }));

  @override
  Future<PairLink> createFamilyInvite(String seniorProfileId) async =>
      _link(await _rpc('create_family_invite', {
        'p_senior_profile_id': seniorProfileId,
      }));

  @override
  Future<SeniorProfile> redeemFamilyInvite(String code) async =>
      _profile(await _rpc('redeem_family_invite', {'p_code': code.trim()}));

  @override
  Future<List<GuardianLink>> guardiansFor(String seniorProfileId) async {
    // Through a function rather than an embedded select. The embed inherits
    // `guardian_accounts_own` — `auth_user_id = auth.uid()` — so it answered
    // with the caller's own row and nulls for everyone else: the senior's
    // phone learned nothing at all about its guardians, and a guardian
    // learned nothing about a sibling.
    try {
      final rows = await _client.rpc(
        'guardians_for_senior',
        params: {'p_senior_profile_id': seniorProfileId},
      );
      if (rows is! List) return const [];
      return [
        for (final row in rows)
          if (row is Map<String, Object?>) ?GuardianLink.fromRow(row),
      ];
    } on sb.PostgrestException catch (e) {
      throw SeniorLinkException(e.message);
    }
  }

  @override
  Future<void> requestPrimaryGuardian(String seniorProfileId) =>
      _rpc('request_primary_guardian', {
        'p_senior_profile_id': seniorProfileId,
      });

  @override
  Future<void> resolvePrimaryGuardian(String seniorProfileId, bool approve) =>
      _rpc('resolve_primary_guardian', {
        'p_senior_profile_id': seniorProfileId,
        'p_approve': approve,
      });

  Future<Map<String, Object?>> _rpc(
    String name,
    Map<String, Object?> params,
  ) async {
    try {
      final result = await _client.rpc(name, params: params);
      if (result is Map<String, Object?>) return result;
      if (result is List && result.isNotEmpty && result.first is Map) {
        return (result.first as Map).cast<String, Object?>();
      }
      return const {};
    } on sb.PostgrestException catch (e) {
      throw SeniorLinkException(_readable(e.message));
    }
  }

  /// The database raises in English for developers. Only the cases someone can
  /// act on are translated; anything else keeps the original so a bug does not
  /// hide behind a friendly line.
  static String _readable(String message) {
    if (message.contains('no such code')) {
      return '연결 번호가 맞지 않거나 시간이 지났어요. 다시 확인해 주세요.';
    }
    if (message.contains('ambiguous code')) {
      return '같은 번호가 둘 있어요. 새 번호를 받아 주세요.';
    }
    if (message.contains('already the primary guardian')) {
      return '이미 대표 보호자예요.';
    }
    if (message.contains('only the senior device')) {
      return '부모님 폰에서만 답할 수 있어요.';
    }
    if (message.contains('nothing to answer')) {
      return '답할 요청이 없어요.';
    }
    if (message.contains('not allowed to manage')) {
      return '이 부모님을 관리할 권한이 없어요.';
    }
    return message;
  }

  static PairLink _link(Map<String, Object?> row) {
    final link = PairLink.fromRow(row);
    if (link == null) throw const SeniorLinkException('연결 번호를 만들지 못했어요.');
    return link;
  }

  static SeniorProfile _profile(Map<String, Object?> row) {
    final profile = SeniorProfile.fromRow(row);
    if (profile == null) throw const SeniorLinkException('부모님 정보를 읽지 못했어요.');
    return profile;
  }
}

/// Stand-in used when the build carries no Supabase keys, and by tests.
///
/// Shares its state with an [InMemorySeniorLinkRepository] rather than keeping
/// a second copy: the whole point of these paths is that they end in the same
/// profiles, devices and links the rest of the app reads.
///
/// Enforces the rules the screens depend on — a code is single-use and
/// expires, an invited guardian joins as family, and only the senior's device
/// may answer a change of primary guardian.
class InMemoryPairingRepository implements PairingRepository {
  InMemoryPairingRepository(this.store, {this.now = DateTime.now});

  final InMemorySeniorLinkRepository store;

  /// Overridden by tests that need a code to have expired.
  final DateTime Function() now;

  final List<PairLink> issued = [];
  final Set<String> _spent = {};

  /// Which guardian this fake is acting as. Tests set it to stand in for a
  /// sibling on a different phone.
  String actingGuardianId = 'account-1';

  int _seq = 0;

  @override
  Future<PairLink> startSeniorPairing({
    required String installId,
    String? deviceLabel,
    String? platform,
    String? osVersion,
  }) async {
    // A phone that already belongs to a profile is sharing a code for that
    // profile, not making a second parent.
    var profileId = store.activeDeviceByProfile.entries
        .where((e) => e.value.installId == installId)
        .map((e) => e.key)
        .firstOrNull;
    profileId ??= store.addProfile('부모님').id;
    store.attachDevice(profileId, installId, platform: platform);

    return _issue(
      mode: PairMode.seniorSharesCode,
      digits: 4,
      profileId: profileId,
      lifetime: const Duration(minutes: 10),
    );
  }

  @override
  Future<SeniorProfile> claimSeniorPairingCode({
    required String code,
    required String displayName,
    String? phoneNumber,
  }) async {
    final link = _claim(code, PairMode.seniorSharesCode);
    store.rename(link.seniorProfileId!, displayName.trim());
    store.link(link.seniorProfileId!, actingGuardianId, 'primary');
    return store.profiles[link.seniorProfileId]!;
  }

  @override
  Future<PairLink> createSeniorInvite({required String displayName}) async {
    final profile = store.addProfile(displayName.trim());
    store.link(profile.id, actingGuardianId, 'primary');
    return _issue(
      mode: PairMode.guardianInvitesSenior,
      digits: 6,
      profileId: profile.id,
      lifetime: const Duration(days: 14),
    );
  }

  @override
  Future<SeniorProfile> redeemSeniorInvite({
    required String installId,
    String? token,
    String? code,
    String? deviceLabel,
    String? platform,
    String? osVersion,
  }) async {
    if (token == null && code == null) {
      throw const SeniorLinkException('연결 번호가 필요해요.');
    }
    final link = token != null
        ? _claimToken(token, PairMode.guardianInvitesSenior)
        : _claim(code!, PairMode.guardianInvitesSenior);
    store.attachDevice(link.seniorProfileId!, installId, platform: platform);
    return store.profiles[link.seniorProfileId]!;
  }

  @override
  Future<PairLink> createRecoveryCode(String seniorProfileId) async {
    _requireManages(seniorProfileId);
    return _issue(
      mode: PairMode.recovery,
      digits: 6,
      profileId: seniorProfileId,
      lifetime: const Duration(hours: 24),
    );
  }

  @override
  Future<SeniorProfile> redeemRecoveryCode({
    required String code,
    required String installId,
    String? deviceLabel,
    String? platform,
    String? osVersion,
  }) async {
    final link = _claim(code, PairMode.recovery);
    store.attachDevice(link.seniorProfileId!, installId, platform: platform);
    return store.profiles[link.seniorProfileId]!;
  }

  @override
  Future<PairLink> createFamilyInvite(String seniorProfileId) async {
    _requireManages(seniorProfileId);
    return _issue(
      mode: PairMode.guardianInviteFamily,
      digits: 6,
      profileId: seniorProfileId,
      lifetime: const Duration(days: 7),
    );
  }

  @override
  Future<SeniorProfile> redeemFamilyInvite(String code) async {
    final link = _claim(code, PairMode.guardianInviteFamily);
    // Never 'primary': joining by invitation does not take over the account.
    store.link(link.seniorProfileId!, actingGuardianId, 'family');
    return store.profiles[link.seniorProfileId]!;
  }

  @override
  Future<List<GuardianLink>> guardiansFor(String seniorProfileId) async => [
    for (final entry in (store.rolesByProfile[seniorProfileId] ?? {}).entries)
      GuardianLink(
        guardianAccountId: entry.key,
        role: entry.value,
        status: 'active',
        displayName: store.guardianNames[entry.key],
        phoneNumber: store.guardianPhones[entry.key],
      ),
  ];

  @override
  Future<void> requestPrimaryGuardian(String seniorProfileId) async {
    _requireManages(seniorProfileId);
    if (store.rolesByProfile[seniorProfileId]?[actingGuardianId] == 'primary') {
      throw const SeniorLinkException('이미 대표 보호자예요.');
    }
    store.pendingPrimaryByProfile[seniorProfileId] = actingGuardianId;
  }

  @override
  Future<void> resolvePrimaryGuardian(String seniorProfileId, bool approve) async {
    // Only the phone in the senior's hand. A guardian approving their own
    // request would make the approval ceremonial.
    if (store.activeDeviceByProfile[seniorProfileId]?.installId !=
        store.seniorInstallId) {
      throw const SeniorLinkException('부모님 폰에서만 답할 수 있어요.');
    }
    final pending = store.pendingPrimaryByProfile.remove(seniorProfileId);
    if (pending == null) throw const SeniorLinkException('답할 요청이 없어요.');
    if (!approve) return;

    final roles = store.rolesByProfile[seniorProfileId] ??= {};
    for (final id in roles.keys.toList()) {
      if (roles[id] == 'primary') roles[id] = 'family';
    }
    roles[pending] = 'primary';
  }

  void _requireManages(String seniorProfileId) {
    if (store.rolesByProfile[seniorProfileId]?[actingGuardianId] == null) {
      throw const SeniorLinkException('이 부모님을 관리할 권한이 없어요.');
    }
  }

  PairLink _issue({
    required PairMode mode,
    required int digits,
    required String profileId,
    required Duration lifetime,
  }) {
    _seq++;
    final link = PairLink(
      id: 'link-$_seq',
      code: _seq.toString().padLeft(digits, '0'),
      token: 'token-$_seq',
      mode: mode,
      expiresAt: now().add(lifetime),
      seniorProfileId: profileId,
    );
    issued.add(link);
    return link;
  }

  PairLink _claim(String code, PairMode mode) => _spend(
    issued.where((l) => l.code == code.trim() && l.mode == mode).lastOrNull,
  );

  PairLink _claimToken(String token, PairMode mode) => _spend(
    issued.where((l) => l.token == token.trim() && l.mode == mode).lastOrNull,
  );

  PairLink _spend(PairLink? link) {
    if (link == null ||
        _spent.contains(link.id) ||
        link.isExpiredAt(now())) {
      throw const SeniorLinkException('연결 번호가 맞지 않거나 시간이 지났어요. 다시 확인해 주세요.');
    }
    _spent.add(link.id);
    return link;
  }
}
