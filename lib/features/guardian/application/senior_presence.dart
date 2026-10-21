import '../../../core/format/korean_clock.dart';

/// How old the parent's last check-in is, in the only brackets the guardian's
/// card is willing to speak in.
enum PresenceAge { never, now, today, yesterday, days }

/// What the dashboard may say about a parent's phone, and nothing more.
///
/// 안부 신호 is the one reading on this half that costs no permission: the
/// launcher reports that it came to the foreground, which on a phone whose
/// home screen it is means the parent unlocked the phone or came back from
/// another app. That is a real signal and it is worth paying for — but it is
/// a signal about a *phone*, and the wording here is what keeps it from being
/// read as a signal about a person. Nothing it produces says 안전, 괜찮,
/// 건강 or 이상 없음, and there is a test walking every bracket for those
/// words.
///
/// The card was honest about a *missing* check-in from the day it was built
/// and silent about a stale one, which is the same fabrication wearing a
/// timestamp: `last_seen_at` was written once, when the phone registered, so
/// a phone set up in July and never opened since still lit the green dot and
/// read 폰은 잘 켜져 있어요.
class SeniorPresence {
  const SeniorPresence._({
    required this.age,
    required this.daysAgo,
    this.lastSeen,
  });

  /// [now] is passed in rather than read, so the dashboard's clock is the one
  /// the tests and the review screenshots pin.
  factory SeniorPresence.from({
    required DateTime? lastSeen,
    required DateTime now,
  }) {
    if (lastSeen == null) {
      return const SeniorPresence._(age: PresenceAge.never, daysAgo: 0);
    }

    // Calendar days, not 24-hour blocks: 23:50 to 00:10 is twenty minutes and
    // nobody would call that two days, but it is two dates and 어제 is what a
    // person would say. Both ends are floored to midnight first.
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(lastSeen.year, lastSeen.month, lastSeen.day))
        .inDays;

    // A phone clock that runs fast stamps a check-in in the future. Reading
    // that literally gives `-1일째`, so anything not yet past counts as now.
    if (!lastSeen.isBefore(now.subtract(stillInHand))) {
      return SeniorPresence._(
        age: PresenceAge.now,
        daysAgo: 0,
        lastSeen: lastSeen,
      );
    }

    return SeniorPresence._(
      age: switch (days) {
        <= 0 => PresenceAge.today,
        1 => PresenceAge.yesterday,
        _ => PresenceAge.days,
      },
      daysAgo: days < 0 ? 0 : days,
      lastSeen: lastSeen,
    );
  }

  /// How recent a check-in has to be for the card to speak in the present
  /// tense. The launcher reports when the parent comes back to it, so an
  /// hour-old report means the phone has been lying on a table — which is not
  /// something to light a dot for.
  static const stillInHand = Duration(minutes: 10);

  final PresenceAge age;

  /// Whole calendar days since the last check-in; 0 unless [age] is
  /// [PresenceAge.days].
  final int daysAgo;

  final DateTime? lastSeen;

  /// The green dot, which claims *now* and may not be lit on anything else.
  bool get online => age == PresenceAge.now;

  /// The large figure on the hero card. Short: it is 26px and shares the row.
  String get headline => switch (age) {
    PresenceAge.never => '아직',
    PresenceAge.now => '방금',
    PresenceAge.today => koreanTime(lastSeen!),
    PresenceAge.yesterday => '어제',
    PresenceAge.days => '$daysAgo일째',
  };

  String get caption => switch (age) {
    PresenceAge.never => '연결되기 전이에요',
    PresenceAge.now => '폰을 쓰셨어요',
    PresenceAge.today => '까지 쓰고 계셨어요',
    PresenceAge.yesterday => '마지막으로 쓰셨어요',
    PresenceAge.days => '폰을 안 쓰셨어요',
  };

  /// The line under the tab's title, which carries the whole sentence.
  String get lede => switch (age) {
    PresenceAge.never => '폰이 아직 연결되기 전이에요',
    PresenceAge.now => '방금 폰을 쓰고 계셨어요',
    PresenceAge.today => '오늘 폰을 쓰셨어요',
    PresenceAge.yesterday => '어제 쓰시고, 오늘은 아직이에요',
    PresenceAge.days => '$daysAgo일째 폰을 안 쓰셨어요',
  };
}
