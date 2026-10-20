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
