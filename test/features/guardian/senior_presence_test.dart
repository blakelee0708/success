import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/guardian/application/senior_presence.dart';

/// 안부 신호 — the one reading on the dashboard that needs no permission at
/// all, and the one the hero card has been overstating.
///
/// `last_seen_at` used to be written only when the phone registered, and the
/// card read it in the present tense: a green dot and `폰은 잘 켜져 있어요` for
/// a phone that had not been touched since the day it was set up. These cases
/// are what it may say instead.
void main() {
  final now = DateTime(2026, 10, 20, 15, 10);

  test('a phone that has never checked in claims no time at all', () {
    final p = SeniorPresence.from(lastSeen: null, now: now);

    expect(p.age, PresenceAge.never);
    expect(p.online, isFalse);
    expect(p.headline, '아직');
    expect(p.lede, contains('아직'));
  });

  test('a check-in in the last few minutes is the only one called 방금', () {
    final p = SeniorPresence.from(
      lastSeen: now.subtract(const Duration(minutes: 4)),
      now: now,
    );

    expect(p.age, PresenceAge.now);
    expect(p.online, isTrue);
    expect(p.headline, '방금');
  });

  test('the dot goes out well before the day does', () {
    // The green dot claims *now*. The launcher pings when the parent comes
    // back to it, so an hour-old ping means the phone has been face-down on a
    // table — which is not something to light a dot for.
    final p = SeniorPresence.from(
      lastSeen: now.subtract(const Duration(hours: 1)),
      now: now,
    );

    expect(p.age, PresenceAge.today);
    expect(p.online, isFalse);
    expect(p.headline, '오후 2:10');
  });

  test('earlier today says the hour it was', () {
    final p = SeniorPresence.from(
      lastSeen: DateTime(2026, 10, 20, 8, 5),
      now: now,
    );

    expect(p.age, PresenceAge.today);
    expect(p.headline, '오전 8:05');
    expect(p.lede, '오늘 폰을 쓰셨어요');
  });

  test('yesterday is named, not counted', () {
    final p = SeniorPresence.from(
      lastSeen: DateTime(2026, 10, 19, 21, 40),
      now: now,
    );

    expect(p.age, PresenceAge.yesterday);
    expect(p.online, isFalse);
    expect(p.headline, '어제');
  });

  test('a silent phone is counted in days, and says so plainly', () {
    final p = SeniorPresence.from(
      lastSeen: DateTime(2026, 10, 17, 9, 0),
      now: now,
    );

    expect(p.age, PresenceAge.days);
    expect(p.daysAgo, 3);
    expect(p.headline, '3일째');
    expect(p.lede, '3일째 폰을 안 쓰셨어요');
  });

  test('the day count is calendar days, not 24-hour blocks', () {
    // 23:50 last night to 00:10 tonight is 20 minutes, and nobody would call
    // that two days. Late last night to this morning is 어제.
    final p = SeniorPresence.from(
      lastSeen: DateTime(2026, 10, 19, 23, 50),
      now: DateTime(2026, 10, 20, 0, 10),
    );

    expect(p.age, PresenceAge.yesterday);
  });

  test('nothing here ever says the parent is well', () {
    // The server knows a phone was unlocked. It does not know the person is
    // all right, and this is the most reassuring-looking object on the screen.
    for (final lastSeen in <DateTime?>[
      null,
      now.subtract(const Duration(minutes: 2)),
      DateTime(2026, 10, 20, 8, 5),
      DateTime(2026, 10, 19, 21, 40),
      DateTime(2026, 10, 14, 9, 0),
    ]) {
      final p = SeniorPresence.from(lastSeen: lastSeen, now: now);
      for (final line in [p.headline, p.caption, p.lede]) {
        for (final claim in ['안전', '괜찮', '잘 계', '건강', '이상 없']) {
          expect(
            line,
            isNot(contains(claim)),
            reason: '$line claims more than a check-in can show',
          );
        }
      }
    }
  });

  test('a clock running backwards does not produce a negative day count', () {
    // Phone clocks drift and time zones move; a check-in stamped in the
    // future must not come out as `-1일째`.
    final p = SeniorPresence.from(
      lastSeen: now.add(const Duration(minutes: 30)),
      now: now,
    );

    expect(p.age, PresenceAge.now);
    expect(p.daysAgo, 0);
  });
}
