/// Which kind of attachment a code or link grants.
///
/// The four are one table because they are one idea — a short-lived secret
/// that grants exactly one attachment — but they are not interchangeable, and
/// redeeming asks for the mode so a family invite can never be spent as a
/// recovery.
enum PairMode {
  /// 경로 A: the guardian creates the profile and texts an install link.
  guardianInvitesSenior('guardian_invites_senior'),

  /// 경로 B: the parent's phone shows a 4-digit code and the guardian types it.
  seniorSharesCode('senior_shares_code'),

  /// A replacement or reinstalled phone rejoining the profile it already had.
  recovery('recovery'),

  /// A sibling joining as a second guardian. Free, per the PRD.
  guardianInviteFamily('guardian_invite_family');

  const PairMode(this.wire);

  final String wire;
}

/// A code, and the link that carries it.
class PairLink {
  const PairLink({
    required this.id,
    required this.code,
    required this.token,
    required this.mode,
    required this.expiresAt,
    this.seniorProfileId,
  });

  final String id;

  /// Digits, read aloud or typed. Four for [PairMode.seniorSharesCode], six for
  /// everything else — the short one is displayed on the senior's own phone and
  /// used within minutes, the others travel further.
  final String code;

  /// Carried in the install link. Never shown to anyone.
  final String token;

  final PairMode mode;
  final DateTime expiresAt;
  final String? seniorProfileId;

  bool isExpiredAt(DateTime now) => !now.isBefore(expiresAt);

  /// The Play listing, with the token as the install referrer.
  ///
  /// This is what makes 경로 A automatic: Play hands the referrer to the app on
  /// first launch, and it carries the token that says which family this is.
  /// It only survives an install that actually went through the store, which
  /// is exactly why [code] travels alongside it.
  String installUrl(String applicationId) =>
      'https://play.google.com/store/apps/details'
      '?id=$applicationId&referrer=$token';

  /// The message body handed to the SMS app for 경로 A.
  ///
  /// The app cannot send it — `07_PHASE_PLAN` is explicit that handing it to
  /// the messaging app is as far as this goes — so nothing here or anywhere
  /// else may claim it was sent. This only produces the text.
  String installMessage({
    required String seniorName,
    required String applicationId,
  }) =>
      '$seniorName님, 자녀가 보낸 잘보이네 설치 링크예요.\n'
      '${installUrl(applicationId)}\n\n'
      '앱을 열고 나서 연결이 안 되면, 가족 연결 화면에 번호 $code 를 넣어 주세요.';

  static PairLink? fromRow(Map<String, Object?> row) {
    final id = row['id'];
    final code = row['code'];
    final token = row['token'];
    final expiresAt = row['expires_at'];
    if (id is! String || code is! String || token is! String) return null;
    final mode = _modeFrom(row['mode']);
    final expires = expiresAt is String ? DateTime.tryParse(expiresAt) : null;
    if (mode == null || expires == null) return null;
    return PairLink(
      id: id,
      code: code,
      token: token,
      mode: mode,
      expiresAt: expires,
      seniorProfileId: row['senior_profile_id'] as String?,
    );
  }

  static PairMode? _modeFrom(Object? wire) {
    for (final mode in PairMode.values) {
      if (mode.wire == wire) return mode;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is PairLink &&
      other.id == id &&
      other.code == code &&
      other.token == token &&
      other.mode == mode &&
      other.expiresAt == expiresAt &&
      other.seniorProfileId == seniorProfileId;

  @override
  int get hashCode =>
      Object.hash(id, code, token, mode, expiresAt, seniorProfileId);
}

/// One guardian's standing on a profile.
class GuardianLink {
  const GuardianLink({
    required this.guardianAccountId,
    required this.role,
    required this.status,
    this.displayName,
    this.email,
    this.phoneNumber,
  });

  final String guardianAccountId;

  /// `primary` or `family`. Only one guardian is primary at a time, and moving
  /// it needs the senior's phone to agree.
  final String role;

  /// `active`, `pending` or `removed`.
  final String status;

  final String? displayName;
  final String? email;

  /// Optional — the field the guardian fills when they connect says
  /// 비워 두셔도 됩니다. Null is why 긴급 연락's 보호자 button can be connected
  /// to a family and still have nothing to dial.
  final String? phoneNumber;

  bool get isPrimary => role == 'primary';
  bool get isActive => status == 'active';

  static GuardianLink? fromRow(Map<String, Object?> row) {
    final guardianAccountId = row['guardian_account_id'];
    final role = row['role'];
    final status = row['status'];
    if (guardianAccountId is! String || role is! String || status is! String) {
      return null;
    }
    // `guardians_for_senior` returns the columns flat; the older embedded
    // select nested them under the joined table's name.
    final account = row['guardian_accounts'];
    String? field(String name) => switch (account) {
      final Map<Object?, Object?> a => a[name] as String?,
      _ => row[name] as String?,
    };
    return GuardianLink(
      guardianAccountId: guardianAccountId,
      role: role,
      status: status,
      displayName: field('display_name'),
      email: field('email'),
      phoneNumber: field('phone_number'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GuardianLink &&
      other.guardianAccountId == guardianAccountId &&
      other.role == role &&
      other.status == status &&
      other.displayName == displayName &&
      other.email == email &&
      other.phoneNumber == phoneNumber;

  @override
  int get hashCode => Object.hash(
    guardianAccountId,
    role,
    status,
    displayName,
    email,
    phoneNumber,
  );
}
