import 'device_status.dart';

/// What the guardian is allowed to know about their parent's phone right now.
///
/// Separate from [SeniorDevice] because the two answer different questions.
/// Which phone is connected is 연결 관리 and stays free - a family has to be
/// able to see that they attached the right handset. **When it was last used,
/// and what state it is in, is 안심 케어**, and that is the whole of what the
/// 2026-10-28 pricing line moved: those were free, so the paid tier was two
/// alerts about a phone the guardian could already watch.
///
/// The gate is `senior_readings` in SQL, not a flag read here. What this
/// carries is the server's answer.
class SeniorReadings {
  const SeniorReadings({
    required this.visible,
    this.trialEndsAt,
    this.lastSeenAt,
    this.status,
  });

  /// A family with no phone attached at all. Not the same as [withheld]: the
  /// dashboard has a sentence for each, and only one of them is an offer.
  static const none = SeniorReadings(visible: true);

  /// Withheld because the free week is over and nobody has subscribed.
  static const withheld = SeniorReadings(visible: false);

  /// Whether the readings below may be shown. False means **we are not
  /// allowed to say**, never *this phone has never checked in* - the server
  /// returns nulls in that case rather than no row for exactly this reason.
  final bool visible;

  /// When the free week ends, or ended. Null for a family with no link yet.
  final DateTime? trialEndsAt;

  final DateTime? lastSeenAt;
  final DeviceStatus? status;

  /// Whether this family is inside the free week rather than subscribed.
  ///
  /// Both show the same readings, so `visible` cannot tell them apart - and
  /// one of them is about to stop.
  bool trialRunningAt(DateTime now) =>
      visible && trialEndsAt != null && trialEndsAt!.isAfter(now);

  /// Calendar days left, the same way 안부 신호 counts them: 23:50 to 00:10 is
  /// twenty minutes and two dates, and tomorrow is what a person would say.
  int trialDaysLeftAt(DateTime now) {
    final ends = trialEndsAt;
    if (ends == null) return 0;
    final today = DateTime(now.year, now.month, now.day);
    final last = DateTime(ends.year, ends.month, ends.day);
    return last.difference(today).inDays.clamp(0, 7);
  }

  static SeniorReadings fromRow(Map<String, Object?> row) {
    DateTime? at(Object? value) => switch (value) {
      final String s => DateTime.tryParse(s)?.toLocal(),
      final DateTime d => d,
      _ => null,
    };
    return SeniorReadings(
      visible: row['visible'] == true,
      trialEndsAt: at(row['trial_ends_at']),
      lastSeenAt: at(row['last_seen_at']),
      status: DeviceStatus.fromRow(row),
    );
  }
}
