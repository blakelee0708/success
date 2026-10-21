/// Whether the parent's phone will make a sound when somebody rings it.
///
/// A mode rather than a volume percentage, which is what the Phase 6 sketch
/// declared. The question a guardian is actually asking is 왜 전화를 안 받으시지,
/// and the answer to that is 무음 — a phone can sit in silent mode with its
/// ring volume at 100%, so a percentage answers the wrong question with a
/// confident-looking number.
enum RingerMode { silent, vibrate, normal }

/// One reading of the parent's phone, taken on the parent's phone.
///
/// Everything here is free: Android gives battery and ringer state to any app
/// without a runtime permission and without a Play declaration. That is the
/// whole reason this is the second capability to ship rather than the fourth —
/// it is the most of 안심 케어 that can exist before 위치정보 사업 신고 is
/// through.
///
/// Every field but [readAt] is nullable, and null means *this phone did not
/// say*. It is never rounded to 0: a dashboard that shows 배터리 0% for a
/// phone that declined to answer has invented the most alarming reading it
/// could.
class DeviceStatus {
  const DeviceStatus({
    required this.readAt,
    this.batteryPercent,
    this.isCharging,
    this.ringer,
  });

  /// When the parent's phone took this reading — not when the guardian's
  /// phone fetched it. A reading with no stated age is indistinguishable from
  /// a current one, which is the whole of what went wrong with `last_seen_at`.
  final DateTime readAt;

  final int? batteryPercent;
  final bool? isCharging;
  final RingerMode? ringer;

  /// True when there is nothing worth drawing. A row of 아직 beside 아직 is
  /// not a status card, it is noise where an empty state belongs.
  bool get isEmpty =>
      batteryPercent == null && isCharging == null && ringer == null;

  static RingerMode? ringerFrom(Object? raw) => switch (raw) {
    'silent' => RingerMode.silent,
    'vibrate' => RingerMode.vibrate,
    'normal' => RingerMode.normal,
    _ => null,
  };

  /// Reads a row of `senior_devices`. Returns null rather than an empty
  /// reading when the phone has never reported one.
  static DeviceStatus? fromRow(Map<String, Object?> row) {
    final readAt = switch (row['status_read_at']) {
      final String s => DateTime.tryParse(s)?.toLocal(),
      final DateTime d => d,
      _ => null,
    };
    if (readAt == null) return null;
    return DeviceStatus(
      readAt: readAt,
      batteryPercent: switch (row['battery_percent']) {
        final int v => v,
        final num v => v.round(),
        _ => null,
      },
      isCharging: switch (row['is_charging']) {
        final bool v => v,
        _ => null,
      },
      ringer: ringerFrom(row['ringer_mode']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DeviceStatus &&
      other.readAt == readAt &&
      other.batteryPercent == batteryPercent &&
      other.isCharging == isCharging &&
      other.ringer == ringer;

  @override
  int get hashCode => Object.hash(readAt, batteryPercent, isCharging, ringer);
}
