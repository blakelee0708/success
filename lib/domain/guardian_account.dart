/// A signed-in guardian, as far as the app cares.
///
/// Only the two fields the UI actually shows. The provider token, refresh
/// timing and expiry stay inside the auth repository so no screen can be
/// tempted to make a decision from them.
class GuardianSession {
  const GuardianSession({required this.userId, this.email});

  final String userId;
  final String? email;

  @override
  bool operator ==(Object other) =>
      other is GuardianSession &&
      other.userId == userId &&
      other.email == email;

  @override
  int get hashCode => Object.hash(userId, email);
}

/// The guardian's row in `guardian_accounts`, created on first sign-in.
///
/// Separate from [GuardianSession] because the auth user and the account are
/// separate things: the session exists the moment they sign in, the account
/// only once `ensure_guardian_account` has run, and links hang off the account.
class GuardianAccount {
  const GuardianAccount({
    required this.id,
    required this.authUserId,
    this.displayName,
    this.phoneNumber,
    this.email,
  });

  final String id;
  final String authUserId;
  final String? displayName;
  final String? phoneNumber;
  final String? email;

  static GuardianAccount? fromRow(Map<String, Object?> row) {
    final id = row['id'];
    final authUserId = row['auth_user_id'];
    if (id is! String || authUserId is! String) return null;
    return GuardianAccount(
      id: id,
      authUserId: authUserId,
      displayName: row['display_name'] as String?,
      phoneNumber: row['phone_number'] as String?,
      email: row['email'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GuardianAccount &&
      other.id == id &&
      other.authUserId == authUserId &&
      other.displayName == displayName &&
      other.phoneNumber == phoneNumber &&
      other.email == email;

  @override
  int get hashCode =>
      Object.hash(id, authUserId, displayName, phoneNumber, email);
}
