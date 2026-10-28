import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/format/korean_clock.dart';

/// The home screen's clock. Written by hand because `intl` is not a
/// dependency and pulling it in for two strings would be the larger change.
void main() {
  group('koreanTime', () {
    test('an afternoon hour reads 오후 with no leading zero', () {
      expect(koreanTime(DateTime(2026, 10, 20, 14, 30)), '오후 2:30');
    });

    test('a morning hour reads 오전, and minutes keep their zero', () {
      expect(koreanTime(DateTime(2026, 10, 20, 9, 5)), '오전 9:05');
    });

    test('noon is 오후 12, not 오후 0', () {
      expect(koreanTime(DateTime(2026, 10, 20, 12, 0)), '오후 12:00');
    });

    test('midnight is 오전 12, not 오전 0', () {
      // The hour a senior is least likely to be reading this, and the one a
      // 12-hour clock written from scratch always gets wrong.
      expect(koreanTime(DateTime(2026, 10, 20, 0, 7)), '오전 12:07');
    });

    test('the last minute before noon is still 오전', () {
      expect(koreanTime(DateTime(2026, 10, 20, 11, 59)), '오전 11:59');
    });
  });

  group('koreanDate', () {
    test('reads as a person says it out loud', () {
      expect(koreanDate(DateTime(2026, 10, 20)), '10월 20일 화요일');
    });

    test('every weekday has a name', () {
      final names = [
        for (var day = 19; day <= 25; day++)
          koreanDate(DateTime(2026, 10, day)).split(' ').last,
      ];

      expect(names, ['월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일']);
    });

    test('a single-digit month and day carry no padding', () {
      expect(koreanDate(DateTime(2026, 3, 7)), '3월 7일 토요일');
    });
  });
}
