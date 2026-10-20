/// The home screen's clock and date, in the words a person would use.
///
/// Hand-written rather than `intl`: the app needs exactly these two strings in
/// exactly one language, and a localisation package would be a bigger change
/// than the thing it replaces.
library;

const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

/// `오후 2:30`. Twelve-hour, because that is how the time is said aloud.
String koreanTime(DateTime at) {
  final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
  final half = at.hour < 12 ? '오전' : '오후';
  return '$half $hour:${at.minute.toString().padLeft(2, '0')}';
}

/// `10월 20일 화요일`. No zero padding — nobody says "영시월".
String koreanDate(DateTime at) =>
    '${at.month}월 ${at.day}일 ${_weekdays[at.weekday - 1]}요일';

/// How long ago, in days, said the way a person would: `오늘`, `어제`,
/// `3일 전`.
///
/// Days rather than hours because the guardian's screen uses this for "how
/// long has the conversation been quiet", and nobody counts that in hours.
/// Compares calendar days, so 11pm last night is 어제 and not 1일 전.
String koreanDaysAgo(DateTime at, DateTime now) {
  final days = DateTime(now.year, now.month, now.day)
      .difference(DateTime(at.year, at.month, at.day))
      .inDays;
  return switch (days) {
    <= 0 => '오늘',
    1 => '어제',
    _ => '$days일 전',
  };
}
