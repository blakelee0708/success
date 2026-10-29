import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/format/korean_particle.dart';
import 'package:app/domain/subscription.dart';

void main() {
  test('a name ending in a vowel takes 와 and 가', () {
    expect(gwaWa('영희'), '영희와');
    expect(iGa('영희'), '영희가');
  });

  test('a name ending in a 받침 takes 과 and 이', () {
    expect(gwaWa('민준'), '민준과');
    expect(iGa('민준'), '민준이');
    expect(gwaWa('자녀분'), '자녀분과');
  });

  test('a name that is not Hangul takes the 받침 form', () {
    expect(gwaWa('Tom'), 'Tom과');
    expect(iGa(''), '이');
  });

  test('a cancelled month with no end date is not running', () {
    // The server reads `null > now()` as false, so the readings stopped the
    // moment such a row was cancelled. The screen has to agree.
    const sub = Subscription(
      id: 's',
      plan: SubscriptionPlan.care,
      status: SubscriptionStatus.canceled,
    );
    expect(sub.stillRunningAt(DateTime(2026, 10, 29)), isFalse);
  });
}
