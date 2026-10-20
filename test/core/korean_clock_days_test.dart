import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/format/korean_clock.dart';

void main() {
  final now = DateTime(2026, 10, 20, 9, 0);

  test('today is 오늘 even when it was hours ago', () {
    expect(koreanDaysAgo(DateTime(2026, 10, 20, 1, 0), now), '오늘');
  });

  test('last night is 어제, not 1일 전', () {
    // 10 hours earlier, and still the day before — this counts calendar days
    // rather than elapsed hours, which is how people say it.
    expect(koreanDaysAgo(DateTime(2026, 10, 19, 23, 0), now), '어제');
  });

  test('older than that counts days', () {
    expect(koreanDaysAgo(DateTime(2026, 10, 16, 23, 0), now), '4일 전');
  });

  test('a clock that has run backwards does not say -1일 전', () {
    expect(koreanDaysAgo(DateTime(2026, 10, 21, 9, 0), now), '오늘');
  });
}
