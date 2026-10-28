import 'device_status.dart';

/// The parent's phone, as the guardian's dashboard sees it.
///
/// A profile outlives any device — replacing the phone adds a row rather than
/// creating a second parent — so this is only ever "which phone is live right
/// now", never the identity of the person.
class SeniorDevice {
  const SeniorDevice({
    required this.id,
    required this.installId,
    required this.isActive,
    this.deviceLabel,
    this.platform,
    this.lastSeenAt,
    this.status,
  });

  final String id;
  final String installId;
  final bool isActive;
  final String? deviceLabel;
  final String? platform;
  final DateTime? lastSeenAt;

  /// The last battery / ringer reading this phone sent, or null when it has
  /// sent none. Never an empty reading: see [DeviceStatus].
  final DeviceStatus? status;

  static SeniorDevice? fromRow(Map<String, Object?> row) {
    final id = row['id'];
    final installId = row['install_id'];
    if (id is! String || installId is! String) return null;
    return SeniorDevice(
      id: id,
      installId: installId,
      isActive: row['is_active'] == true,
      deviceLabel: row['device_label'] as String?,
      platform: row['platform'] as String?,
      lastSeenAt: switch (row['last_seen_at']) {
        final String value => DateTime.tryParse(value),
        _ => null,
      },
      status: DeviceStatus.fromRow(row),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SeniorDevice &&
      other.id == id &&
      other.installId == installId &&
      other.isActive == isActive &&
      other.deviceLabel == deviceLabel &&
      other.platform == platform &&
      other.lastSeenAt == lastSeenAt &&
      other.status == status;

  @override
  int get hashCode => Object.hash(
    id,
    installId,
    isActive,
    deviceLabel,
    platform,
    lastSeenAt,
    status,
  );
}
