import 'package:flutter_test/flutter_test.dart';

import 'package:app/domain/device_status.dart';
import 'package:app/features/guardian/application/device_status_lines.dart';

/// What the guardian's card may say about the parent's phone.
///
/// Same rule as the hero: a reading the phone did not give is said to be
/// missing, never rounded to a number. 배터리 0% for a phone that declined to
/// answer is the most alarming reading on the list and the app would have
/// invented it.
void main() {
  final now = DateTime(2026, 10, 20, 15, 10);

  DeviceStatusLines lines(DeviceStatus? status) =>
      DeviceStatusLines.from(status: status, now: now);

  test('no reading at all says so, and names no number', () {
    final l = lines(null);

    expect(l.hasReading, isFalse);
    expect(l.battery, '아직 받지 못했어요');
    expect(l.ringer, '아직 받지 못했어요');
    expect(l.battery, isNot(contains('%')));
  });

  test('a reading that answered nothing is the same as no reading', () {
    // The phone reported in but could read neither value. An empty reading is
    // not evidence of anything and must not look like one.
    final l = lines(DeviceStatus(readAt: now));

    expect(l.hasReading, isFalse);
    expect(l.battery, '아직 받지 못했어요');
  });

  test('a battery level is shown as the level it is', () {
    final l = lines(
      DeviceStatus(readAt: now, batteryPercent: 72, ringer: RingerMode.normal),
    );

    expect(l.hasReading, isTrue);
    expect(l.battery, '72%');
    expect(l.ringer, '소리 켜짐');
  });

  test('charging is worth saying, because 15% charging is not a problem', () {
    final l = lines(
      DeviceStatus(readAt: now, batteryPercent: 15, isCharging: true),
    );

    expect(l.battery, '15% · 충전 중');
  });

  test('a low battery that is not charging is called low', () {
    final l = lines(
      DeviceStatus(readAt: now, batteryPercent: 8, isCharging: false),
    );

    expect(l.battery, contains('8%'));
    expect(l.isBatteryLow, isTrue);
  });

  test('a full battery is not called low, charging or not', () {
    for (final charging in [true, false]) {
      final l = lines(
        DeviceStatus(readAt: now, batteryPercent: 80, isCharging: charging),
      );
      expect(l.isBatteryLow, isFalse);
    }
  });

  test('a low battery on the charger is not an alarm', () {
    final l = lines(
      DeviceStatus(readAt: now, batteryPercent: 8, isCharging: true),
    );

    expect(l.isBatteryLow, isFalse, reason: '충전 중인 8%는 곧 해결됩니다');
  });

  test('the three ringer modes each read as what they mean to a caller', () {
    expect(lines(DeviceStatus(readAt: now, ringer: RingerMode.silent)).ringer,
        '소리 꺼짐');
    expect(lines(DeviceStatus(readAt: now, ringer: RingerMode.vibrate)).ringer,
        '진동');
    expect(lines(DeviceStatus(readAt: now, ringer: RingerMode.normal)).ringer,
        '소리 켜짐');
  });

  test('one value missing does not take the other down with it', () {
    final l = lines(DeviceStatus(readAt: now, batteryPercent: 44));

    expect(l.battery, '44%');
    expect(l.ringer, '아직 받지 못했어요');
    expect(l.hasReading, isTrue);
  });

  test('a reading carries its own age, and an old one says so', () {
    // The readings arrive with the parent's check-in, so they are exactly as
    // old as that check-in. Shown without an age they would read as current,
    // which is what `폰은 잘 켜져 있어요` did for months.
    final fresh = lines(
      DeviceStatus(
        readAt: now.subtract(const Duration(minutes: 5)),
        batteryPercent: 60,
      ),
    );
    expect(fresh.age, '방금');

    final old = lines(
      DeviceStatus(readAt: DateTime(2026, 10, 17, 9), batteryPercent: 60),
    );
    expect(old.age, '3일 전');
  });

  test('an old reading still shows the number it actually was', () {
    // Hiding it would be its own kind of dishonesty: 사흘 전 12% is the most
    // useful thing the card could say about a phone that went quiet.
    final l = lines(
      DeviceStatus(readAt: DateTime(2026, 10, 17, 9), batteryPercent: 12),
    );

    expect(l.battery, contains('12%'));
  });

  test('nothing here says the parent is well', () {
    for (final status in <DeviceStatus?>[
      null,
      DeviceStatus(readAt: now),
      DeviceStatus(
        readAt: now,
        batteryPercent: 90,
        isCharging: true,
        ringer: RingerMode.normal,
      ),
    ]) {
      final l = lines(status);
      for (final line in [l.battery, l.ringer, l.age]) {
        for (final claim in ['안전', '괜찮', '잘 계', '건강', '이상 없']) {
          expect(line, isNot(contains(claim)), reason: line);
        }
      }
    }
  });
}
