import '../../../domain/device_status.dart';
import 'senior_presence.dart';

/// What the guardian's card is allowed to say about the parent's phone.
///
/// The same discipline as [SeniorPresence], for the same reason: readings
/// arrive with the parent's check-in, so a reading is exactly as old as the
/// check-in that carried it, and a number shown without its age reads as
/// current. That is precisely how `폰은 잘 켜져 있어요` survived for months on
/// a column nothing had written since July.
///
/// A value the phone did not give is reported missing and never rounded to
/// zero — 배터리 0% is the most alarming reading on the card and inventing it
/// would be worse than the silence it replaced.
class DeviceStatusLines {
  const DeviceStatusLines._({
    required this.hasReading,
    required this.battery,
    required this.ringer,
    required this.age,
    required this.isBatteryLow,
  });

  factory DeviceStatusLines.from({
    required DeviceStatus? status,
    required DateTime now,
  }) {
    // An empty reading is not evidence. A phone that reported in but could
    // read neither value tells the guardian exactly as much as a phone that
    // never reported, so it is said the same way.
    if (status == null || status.isEmpty) {
      return const DeviceStatusLines._(
        hasReading: false,
        battery: missing,
        ringer: missing,
        age: '',
        isBatteryLow: false,
      );
    }

    final percent = status.batteryPercent;
    final charging = status.isCharging;
    final presence = SeniorPresence.from(lastSeen: status.readAt, now: now);

    return DeviceStatusLines._(
      hasReading: true,
      battery: switch ((percent, charging)) {
        (null, _) => missing,
        (final p, true) => '$p% · 충전 중',
        (final p, _) => '$p%',
      },
      ringer: switch (status.ringer) {
        null => missing,
        RingerMode.silent => '소리 꺼짐',
        RingerMode.vibrate => '진동',
        RingerMode.normal => '소리 켜짐',
      },
      // Shown under its own label (읽은 때), so it is the time and nothing
      // else. It is not the hero's line repeated: a phone that checked in but
      // could not read its battery keeps an older reading than its check-in,
      // and these two dates drift apart exactly when that matters.
      age: switch (presence.age) {
        PresenceAge.never => '',
        PresenceAge.now => '방금',
        PresenceAge.today => presence.headline,
        PresenceAge.yesterday => '어제',
        PresenceAge.days => '${presence.daysAgo}일 전',
      },
      // A low battery on the charger is not a problem, it is a problem being
      // solved. Flagging it would teach the guardian to ignore the flag.
      isBatteryLow: percent != null && percent <= 15 && charging != true,
    );
  }

  /// Said in full rather than as a dash, because a dash on a card like this
  /// is read as a zero or as a bug.
  static const missing = '아직 받지 못했어요';

  /// False when there is nothing worth drawing — no reading, or one that
  /// answered nothing.
  final bool hasReading;

  final String battery;
  final String ringer;

  /// How old the reading is, in the same brackets the hero uses. Empty when
  /// there is no reading to age.
  final String age;

  /// Worth drawing attention to: under 15% and not on the charger.
  final bool isBatteryLow;
}
