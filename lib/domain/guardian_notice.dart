/// One line the app owes a guardian about something that happened while they
/// were not looking.
///
/// **`alerts` could not carry this, and that is the whole reason this exists.**
/// Alerts hang off the senior's profile and their policy is
/// `guardian_manages`, which goes false the instant a link is removed - so an
/// alert saying 연결이 끊어졌습니다 would be readable by every guardian except
/// the one it is about. This is addressed to a guardian rather than to a
/// family.
class GuardianNotice {
  const GuardianNotice({
    required this.id,
    required this.type,
    required this.body,
    required this.createdAt,
    this.seniorName,
    this.readAt,
  });

  final String id;
  final String type;

  /// The parent's name, copied at write time. A removed guardian cannot read
  /// `senior_profiles` any more, and 연결이 끊어졌습니다 with no name is
  /// useless to somebody looking after two parents.
  final String? seniorName;

  /// What to show. Written on the server so the sentence lives in one place.
  final String body;

  final DateTime createdAt;
  final DateTime? readAt;

  bool get isRead => readAt != null;

  static GuardianNotice? fromRow(Map<String, Object?> row) {
    final id = row['id'];
    final type = row['type'];
    final body = row['body'];
    final created = row['created_at'];
    if (id is! String || type is! String || body is! String) return null;
    final at = created is String ? DateTime.tryParse(created) : null;
    if (at == null) return null;
    final read = row['read_at'];
    return GuardianNotice(
      id: id,
      type: type,
      seniorName: row['senior_name'] as String?,
      body: body,
      createdAt: at.toLocal(),
      readAt: read is String ? DateTime.tryParse(read)?.toLocal() : null,
    );
  }
}
