import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../domain/guardian_notice.dart';
import '../../domain/pair_link.dart';
import '../../domain/pending_guardian_link.dart';
import '../../domain/senior_profile.dart';
import 'senior_link_repository.dart';

/// The two ways a parent and their one child get connected, getting a
/// replaced phone back onto its profile, and leaving.
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

  // --- Guardians -------------------------------------------------------------

  /// Everyone looking after this parent. Includes the caller.
  Future<List<GuardianLink>> guardiansFor(String seniorProfileId);

  /// The guardian this phone's owner has not answered about yet, if any.
  ///
  /// One at a time, oldest first: two children connecting the same afternoon
  /// is two cards, each naming one person. A card saying 두 명이 연결을
  /// 부탁하셨어요 would be a single yes to two different people.
  Future<PendingGuardianLink?> pendingGuardianLink();

  /// 허락합니다 / 아니요, answered on the senior's own phone.
  ///
  /// A refusal removes the row rather than marking it: it is not final and
  /// not a punishment, the guardian can ask again, and a 아니요 pressed by
  /// mistake must not lock a family out.
  Future<bool> answerGuardianLink(String linkId, {required bool approve});

  /// The other side of the same wait, for the guardian's own screen.
  Future<List<PendingSeniorLink>> pendingSeniorLinks();

  /// The install invite for [seniorProfileId] that nobody has used yet, or
  /// null.
  ///
  /// **The number has to come back after the app does.** Issuing the invite
  /// makes a waiting link, which moves 홈 onto its 기다리고 있어요 page - and
  /// until this existed that page had no number on it at all, so a guardian
  /// whose parent asked 번호가 뭐였지 the next day had nothing to read out.
  /// Null once the parent's phone has used it: from then on what is
  /// outstanding is their answer, not an install.
  Future<PairLink?> openSeniorInvite(String seniorProfileId);

  // --- 끊기 -----------------------------------------------------------------

  /// 어르신이 끊는다, from 설정 → 가족 연결 설정 on their own phone.
  ///
  /// **One guardian at a time, by name.** A single button that took every
  /// child off was considered and refused: the person a mother is cross with
  /// is usually one of them, and a button that cannot tell her children
  /// apart makes her choose between all of them and none.
  ///
  /// Nothing about the phone changes. The buttons, the colours, the text
  /// size and the contact numbers all stay: leaving is stopping somebody
  /// looking, not putting a phone back how it was.
  Future<void> removeGuardianLink(String guardianAccountId);

  /// 자녀가 끊는다, from 연결 관리. Their own link and nobody else's - a
  /// guardian may leave, and may not remove a sibling.
  Future<void> leaveSenior(String seniorProfileId);

  /// 연결 요청 취소: this guardian's own request the parent has not answered.
  ///
  /// Takes the install numbers it issued with it, so nobody can spend one
  /// later, and the profile when that request was all it ever was - no phone,
  /// no message. An active link is [leaveSenior]'s.
  Future<void> withdrawLinkRequest(String seniorProfileId);

  /// 부모님이 폰을 바꾸셨을 때, answered on the **child's** phone.
  ///
  /// The senior does what they always do and presses 번호 보여주기, which on
  /// a new handset makes a second, empty parent. The child types the four
  /// digits, their app sees they already have this parent, and asks. This is
  /// 어머니 폰을 바꿨어요: the new phone takes the original profile, the old
  /// one steps down, and the conversation, buttons and text size are all
  /// where they were.
  Future<SeniorProfile> moveSeniorToNewPhone({
    required String code,
    required String seniorProfileId,
  });

  /// What the app owes this guardian, which today is one line: their parent
  /// cut the link.
  Future<List<GuardianNotice>> guardianNotices();

  /// Marks them read so the line is said once rather than every open.
  Future<void> markNoticesRead(List<String> ids);
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
  }) async => _link(
    await _rpc('start_senior_pairing', {
      'p_install_id': installId,
      'p_device_label': deviceLabel,
      'p_platform': platform,
      'p_os_version': osVersion,
    }),
  );

  @override
  Future<SeniorProfile> claimSeniorPairingCode({
    required String code,
    required String displayName,
    String? phoneNumber,
  }) async => _profile(
    await _rpc('claim_senior_pairing_code', {
      'p_code': code.trim(),
      'p_display_name': displayName.trim(),
      'p_phone_number': phoneNumber,
    }),
  );

  @override
  Future<PairLink> createSeniorInvite({required String displayName}) async =>
      _link(
        await _rpc('create_senior_invite', {
          'p_display_name': displayName.trim(),
        }),
      );

  @override
  Future<SeniorProfile> redeemSeniorInvite({
    required String installId,
    String? token,
    String? code,
    String? deviceLabel,
    String? platform,
    String? osVersion,
  }) async => _profile(
    await _rpc('redeem_senior_invite', {
      'p_install_id': installId,
      'p_token': token?.trim(),
      'p_code': code?.trim(),
      'p_device_label': deviceLabel,
      'p_platform': platform,
      'p_os_version': osVersion,
    }),
  );

  @override
  Future<PairLink> createRecoveryCode(String seniorProfileId) async => _link(
    await _rpc('create_recovery_code', {
      'p_senior_profile_id': seniorProfileId,
    }),
  );

  @override
  Future<SeniorProfile> redeemRecoveryCode({
    required String code,
    required String installId,
    String? deviceLabel,
    String? platform,
    String? osVersion,
  }) async => _profile(
    await _rpc('redeem_recovery_code', {
      'p_code': code.trim(),
      'p_install_id': installId,
      'p_device_label': deviceLabel,
      'p_platform': platform,
      'p_os_version': osVersion,
    }),
  );

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
  Future<PendingGuardianLink?> pendingGuardianLink() async {
    try {
      final rows = await _client.rpc('pending_guardian_link');
      if (rows is! List || rows.isEmpty) return null;
      final row = rows.first;
      return row is Map<String, Object?>
          ? PendingGuardianLink.fromRow(row)
          : null;
    } on Object {
      // A launcher with no signal draws its home screen, not an error.
      return null;
    }
  }

  @override
  Future<bool> answerGuardianLink(
    String linkId, {
    required bool approve,
  }) async {
    try {
      final answered = await _client.rpc(
        'answer_guardian_link',
        params: {'p_link_id': linkId, 'p_approve': approve},
      );
      return answered == true;
    } on sb.PostgrestException catch (e) {
      throw SeniorLinkException(e.message);
    }
  }

  @override
  Future<List<PendingSeniorLink>> pendingSeniorLinks() async {
    try {
      final rows = await _client.rpc('pending_guardian_links');
      if (rows is! List) return const [];
      return [
        for (final row in rows)
          if (row is Map<String, Object?>) ?PendingSeniorLink.fromRow(row),
      ];
    } on Object {
      return const [];
    }
  }

  @override
  Future<PairLink?> openSeniorInvite(String seniorProfileId) async {
    try {
      // Read from the table: `pair_links_owner_read` lets a guardian see
      // the rows they issued, which is exactly this one.
      final row = await _client
          .from('pair_links')
          .select()
          .eq('senior_profile_id', seniorProfileId)
          .eq('mode', PairMode.guardianInvitesSenior.wire)
          .isFilter('used_at', null)
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return row == null ? null : PairLink.fromRow(row);
    } on Object {
      // The waiting page still draws without it; it only loses the number.
      return null;
    }
  }

  @override
  Future<void> removeGuardianLink(String guardianAccountId) async {
    await _rpc('remove_guardian_link', {
      'p_guardian_account_id': guardianAccountId,
    });
  }

  @override
  Future<void> leaveSenior(String seniorProfileId) async {
    await _rpc('leave_senior', {'p_senior_profile_id': seniorProfileId});
  }

  @override
  Future<void> withdrawLinkRequest(String seniorProfileId) async {
    await _rpc('withdraw_link_request', {
      'p_senior_profile_id': seniorProfileId,
    });
  }

  @override
  Future<SeniorProfile> moveSeniorToNewPhone({
    required String code,
    required String seniorProfileId,
  }) async => _profile(
    await _rpc('move_senior_to_new_phone', {
      'p_code': code.trim(),
      'p_senior_profile_id': seniorProfileId,
    }),
  );

  @override
  Future<List<GuardianNotice>> guardianNotices() async {
    try {
      // Read from the table rather than through a function: the policy is
      // `guardian_account_id = current_guardian_account_id()`, so the row
      // the caller may see is exactly the row addressed to them.
      //
      // **Unread only.** The twin always returned unread ones and this did
      // not, so on the live project a notice marked read came back on every
      // 15-second refresh and sat on 홈 for good - the line written to be
      // said once, said forever.
      final rows = await _client
          .from('guardian_notices')
          .select()
          .isFilter('read_at', null)
          .order('created_at', ascending: false)
          .limit(20);
      return [for (final row in rows) ?GuardianNotice.fromRow(row)];
    } on Object {
      // A dashboard with no signal draws itself. There is nothing here a
      // guardian has to be stopped for.
      return const [];
    }
  }

  @override
  Future<void> markNoticesRead(List<String> ids) async {
    if (ids.isEmpty) return;
    try {
      await _client
          .from('guardian_notices')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .inFilter('id', ids);
    } on Object {
      // Said twice is better than a screen that will not open.
    }
  }

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
    if (message.contains('only the senior device')) {
      return '부모님 폰에서만 답할 수 있어요.';
    }
    if (message.contains('nothing to answer')) {
      return '답할 요청이 없어요.';
    }
    if (message.contains('not allowed to manage')) {
      return '이 부모님을 관리할 권한이 없어요.';
    }
    if (message.contains('already the one connected')) {
      return '이미 연결된 폰이에요.';
    }
    if (message.contains('already set up with a family')) {
      return '그 번호는 다른 가족이 쓰고 있는 폰이에요.';
    }
    if (message.contains('not an active senior device')) {
      return '부모님 폰에서만 끊을 수 있어요.';
    }
    // The 1대1 lock. Two sentences rather than one, because the two refusals
    // are about different people and only one of them is the reader's doing.
    if (message.contains('one senior per guardian') ||
        message.contains('family plan required')) {
      return '지금은 부모님 한 분만 연결할 수 있어요.';
    }
    if (message.contains('one guardian per senior')) {
      return '이 부모님께는 이미 다른 자녀가 연결되어 있어요.';
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
    final profileId = link.seniorProfileId!;
    // Both after the code resolves, exactly as the server does it: neither
    // question can be answered before the number says which parent it is.
    store.assertCanAddSenior(exceptProfileId: profileId);
    store.assertCanAddGuardian(profileId, actingGuardianId);
    store.rename(profileId, displayName.trim());
    // The server leaves this waiting on the senior's own answer. See
    // `pendingLinkConsent`.
    if (store.pendingLinkConsent) {
      store.pendingLinks[profileId] = 'link-$profileId-$actingGuardianId';
      store.pendingAskedBy[profileId] = actingGuardianId;
    } else {
      store.link(profileId, actingGuardianId, 'primary');
    }
    return store.profiles[profileId]!;
  }

  @override
  Future<PairLink> createSeniorInvite({required String displayName}) async {
    store.assertCanAddSenior();
    final profile = store.addProfile(displayName.trim());
    // `create_senior_profile` writes 'pending' on the server, so issuing an
    // invite puts the guardian on the waiting page there. Mirrored behind
    // the same switch as everywhere else.
    if (store.pendingLinkConsent) {
      store.pendingLinks[profile.id] = 'link-${profile.id}-$actingGuardianId';
      store.pendingAskedBy[profile.id] = actingGuardianId;
    } else {
      store.link(profile.id, actingGuardianId, 'primary');
    }
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
  Future<List<GuardianLink>> guardiansFor(String seniorProfileId) async => [
    for (final entry in (store.rolesByProfile[seniorProfileId] ?? {}).entries)
      GuardianLink(
        guardianAccountId: entry.key,
        role: entry.value,
        status: 'active',
        displayName: store.guardianNames[entry.key],
        phoneNumber: store.guardianPhones[entry.key],
      ),
    // **A waiting guardian is on this list too**, because the server's
    // `guardians_for_senior` returns every row that is not `removed`. Left
    // out, this twin could not express the state where the guardian has
    // typed the number and the parent has not answered - and that is the
    // state in which the senior's screen wrongly said 가족과 연결되었어요.
    if (store.pendingAskedBy[seniorProfileId] case final asked?)
      GuardianLink(
        guardianAccountId: asked,
        role: 'primary',
        status: 'pending',
        displayName: store.guardianNames[asked],
        phoneNumber: store.guardianPhones[asked],
      ),
  ];

  @override
  Future<PendingGuardianLink?> pendingGuardianLink() async {
    // Keyed off the waiting rows rather than off what this guardian is
    // linked to: a pending link is precisely one that has not been linked
    // yet, so looking in `linkedProfileIds` finds nothing by definition.
    final entry = store.pendingLinks.entries.firstOrNull;
    if (entry == null) return null;
    return PendingGuardianLink(
      linkId: entry.value,
      guardianName: store.guardianNames[store.pendingAskedBy[entry.key]],
      role: 'primary',
    );
  }

  @override
  Future<bool> answerGuardianLink(
    String linkId, {
    required bool approve,
  }) async {
    final profileId = store.pendingLinks.entries
        .where((e) => e.value == linkId)
        .map((e) => e.key)
        .firstOrNull;
    if (profileId == null) return false;
    store.pendingLinks.remove(profileId);
    if (approve) {
      store.link(
        profileId,
        store.pendingAskedBy[profileId] ?? store.guardianAccountId,
        'primary',
      );
    } else {
      // As the server does: one line, no reason, to the one who asked.
      store.notices.add(
        GuardianNotice(
          id: 'notice-${store.notices.length + 1}',
          type: 'link_declined',
          seniorName: store.profiles[profileId]?.displayName,
          body: '연결되지 않았어요.',
          createdAt: now(),
        ),
      );
    }
    store.pendingAskedBy.remove(profileId);
    return true;
  }

  @override
  Future<PairLink?> openSeniorInvite(String seniorProfileId) async => issued
      .where(
        (l) =>
            l.seniorProfileId == seniorProfileId &&
            l.mode == PairMode.guardianInvitesSenior &&
            !_spent.contains(l.id) &&
            !l.isExpiredAt(now()),
      )
      .lastOrNull;

  @override
  Future<List<PendingSeniorLink>> pendingSeniorLinks() async => [
    for (final entry in store.pendingLinks.entries)
      PendingSeniorLink(
        seniorProfileId: entry.key,
        seniorName: store.profiles[entry.key]?.displayName,
        hasPhone: store.activeDeviceByProfile.containsKey(entry.key),
      ),
  ];

  @override
  Future<void> removeGuardianLink(String guardianAccountId) async {
    // The server scopes this to the profile whose **active device** is the
    // caller, which is what stops a guardian cutting a sibling off. The twin
    // has one senior phone, so that is the profile it holds.
    final profileId = store.activeDeviceByProfile.entries
        .where((e) => e.value.installId == store.seniorInstallId)
        .map((e) => e.key)
        .firstOrNull;
    if (profileId == null) {
      throw const SeniorLinkException('부모님 폰에서만 끊을 수 있어요.');
    }
    store.unlink(profileId, guardianAccountId);
    store.notices.add(
      GuardianNotice(
        id: 'notice-${store.notices.length + 1}',
        type: 'link_removed',
        seniorName: store.profiles[profileId]?.displayName,
        body: '연결이 끊어졌습니다.',
        createdAt: now(),
      ),
    );
  }

  @override
  Future<void> leaveSenior(String seniorProfileId) async {
    store.unlink(seniorProfileId, actingGuardianId);
  }

  @override
  Future<void> withdrawLinkRequest(String seniorProfileId) async {
    if (store.pendingAskedBy[seniorProfileId] != actingGuardianId) return;
    store.pendingLinks.remove(seniorProfileId);
    store.pendingAskedBy.remove(seniorProfileId);
    for (final link in issued) {
      if (link.seniorProfileId == seniorProfileId) _spent.add(link.id);
    }
    // Only ever this request: no phone and nobody else on it.
    if (!store.activeDeviceByProfile.containsKey(seniorProfileId) &&
        (store.rolesByProfile[seniorProfileId] ?? const {}).isEmpty) {
      store.profiles.remove(seniorProfileId);
    }
  }

  @override
  Future<SeniorProfile> moveSeniorToNewPhone({
    required String code,
    required String seniorProfileId,
  }) async {
    _requireManages(seniorProfileId);
    final link = _claim(code, PairMode.seniorSharesCode);
    final emptyId = link.seniorProfileId;
    if (emptyId == null || emptyId == seniorProfileId) {
      throw const SeniorLinkException('이미 연결된 폰이에요.');
    }
    if ((store.rolesByProfile[emptyId] ?? const {}).isNotEmpty) {
      throw const SeniorLinkException('그 번호는 다른 가족이 쓰고 있는 폰이에요.');
    }
    final device = store.activeDeviceByProfile[emptyId];
    if (device != null) {
      store.attachDevice(
        seniorProfileId,
        device.installId,
        platform: device.platform,
      );
    }
    store.activeDeviceByProfile.remove(emptyId);
    store.profiles.remove(emptyId);
    return store.profiles[seniorProfileId]!;
  }

  @override
  Future<List<GuardianNotice>> guardianNotices() async =>
      List.unmodifiable(store.notices.where((n) => !n.isRead));

  @override
  Future<void> markNoticesRead(List<String> ids) async {
    for (var i = 0; i < store.notices.length; i++) {
      final notice = store.notices[i];
      if (!ids.contains(notice.id)) continue;
      store.notices[i] = GuardianNotice(
        id: notice.id,
        type: notice.type,
        seniorName: notice.seniorName,
        body: notice.body,
        createdAt: notice.createdAt,
        readAt: now(),
      );
    }
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
    if (link == null || _spent.contains(link.id) || link.isExpiredAt(now())) {
      throw const SeniorLinkException('연결 번호가 맞지 않거나 시간이 지났어요. 다시 확인해 주세요.');
    }
    _spent.add(link.id);
    return link;
  }
}
