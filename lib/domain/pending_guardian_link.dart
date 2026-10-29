/// A guardian waiting for this senior to agree to being connected.
///
/// **A guardian typed a number and was connected.** Nothing ever asked the
/// person whose phone it is - and on the install-SMS path they did nothing at
/// all, while a sibling joining by invitation was never mentioned to their
/// mother. This is the row that waits for an answer.
class PendingGuardianLink {
  const PendingGuardianLink({
    required this.linkId,
    this.guardianName,
    this.role,
  });

  final String linkId;

  /// What the parent calls them, from `guardian_accounts.display_name`.
  ///
  /// Null when a guardian somehow has no name - which should not happen now
  /// that the question is asked once before the dashboard, but the card still
  /// has to say something rather than 보호자님이 and a blank.
  final String? guardianName;

  /// 'primary' or 'family'. The card does not say which: a senior being asked
  /// whether their second child may join does not need the word 가족 구성원.
  final String? role;

  static PendingGuardianLink? fromRow(Map<String, Object?> row) {
    final id = row['link_id'];
    if (id is! String) return null;
    return PendingGuardianLink(
      linkId: id,
      guardianName: (row['guardian_name'] as String?)?.trim(),
      role: row['role'] as String?,
    );
  }
}

/// The other side of the same wait, on the guardian's phone.
class PendingSeniorLink {
  const PendingSeniorLink({required this.seniorProfileId, this.seniorName});

  final String seniorProfileId;
  final String? seniorName;

  static PendingSeniorLink? fromRow(Map<String, Object?> row) {
    final id = row['senior_profile_id'];
    if (id is! String) return null;
    return PendingSeniorLink(
      seniorProfileId: id,
      seniorName: (row['senior_name'] as String?)?.trim(),
    );
  }
}
