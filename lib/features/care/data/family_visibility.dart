import 'care_capabilities.dart';

/// Which part of 자녀가 보는 것 a line belongs to.
enum FamilySees {
  /// Goes to the family whatever the senior answers, because it is free and
  /// rides on the check-in. Saying so plainly is the point: the consent card
  /// deliberately leaves these out, since listing them there would imply that
  /// 아니요 stops something it does not stop.
  always,

  /// Only once 안심 케어 is bought **and** agreed to.
  withCare,
}

/// One line on 자녀가 보는 것.
class FamilyVisibility {
  const FamilyVisibility({
    required this.sees,
    required this.line,
    this.capabilityKey,
  });

  final FamilySees sees;

  /// The senior's own words. Short enough to be one line of the list at the
  /// sizes this app runs at.
  final String line;

  /// The `careCapabilities` entry this stands for, where there is one.
  ///
  /// It is what keeps the two lists from drifting: a capability added to the
  /// paid tier and not named here would leave the senior agreeing to
  /// something this screen never mentions, which is the gap this screen
  /// exists to close. `family_visibility_test.dart` walks it both ways.
  final String? capabilityKey;
}

/// What the senior's family can see, in one list.
///
/// A different question from the consent card's, which is why it is a
/// different list. The card asks **may we turn this on**, so it names only
/// what is paid and built. This answers **what do they see**, so it names the
/// free readings too.
///
/// **보지 못합니다 is gone, and it was five lines long.** 어디 계신지, 통화
/// 내용과 통화 기록, 연락처, 어떤 앱을 쓰시는지, 사진첩 - every one a
/// decision recorded elsewhere in this repository rather than a promise
/// written for a settings page, and all five true. It came off on the owner's
/// call, and the argument for it is sound: a list of things that are **not**
/// happening plants worries in a reader who did not arrive with them, and
/// this reader is on their own phone rather than reading a policy. The page
/// that owes a complete answer is `site/privacy.html`, which a reviewer
/// reads; this screen owes the senior the short one.
const familyVisibility = <FamilyVisibility>[
  // --- 늘 보입니다 ---------------------------------------------------------
  // Two lines, and it used to be five. 마지막으로 폰 쓰신 때, 배터리 and
  // 소리 moved to 안심 케어 on 2026-10-28, which is what the pricing
  // decision was for - and it leaves the free tier collecting almost nothing
  // about the senior. The consent card and what actually happens now say the
  // same thing, which they did not before.
  FamilyVisibility(sees: FamilySees.always, line: '홈 화면 버튼과 글씨 크기'),
  FamilyVisibility(sees: FamilySees.always, line: '주고받은 메시지'),

  // --- 안심 케어를 허락하시면 ----------------------------------------------
  FamilyVisibility(
    sees: FamilySees.withCare,
    line: '폰을 쓰신 때, 배터리와 소리',
    capabilityKey: 'device_status',
  ),
  FamilyVisibility(
    sees: FamilySees.withCare,
    line: '배터리가 얼마 안 남으면 알려 드립니다',
    capabilityKey: 'battery_low',
  ),
  FamilyVisibility(
    sees: FamilySees.withCare,
    line: '메시지를 읽으신 때',
    capabilityKey: 'message_read',
  ),
];

Iterable<FamilyVisibility> familySees(FamilySees sees) =>
    familyVisibility.where((v) => v.sees == sees);

/// The heading each section carries, in the senior's words.
String familySeesTitle(FamilySees sees) => switch (sees) {
  FamilySees.always => '늘 보입니다',
  FamilySees.withCare => '안심 케어를 허락하시면',
};

/// A line under a section's list, where one is owed.
///
/// The free week is the reason there is one: for the first seven days after
/// the senior agrees to the connection, the 안심 케어 readings are shown
/// without 안심 케어, and a heading saying 안심 케어를 허락하시면 over them
/// was true from the eighth day only. The link consent card says the same
/// thing in its own words.
String? familySeesNote(FamilySees sees) => switch (sees) {
  FamilySees.always => null,
  FamilySees.withCare =>
    '가족 연결을 허락하신 뒤 첫 1주일은 안심 케어 없이도 폰을 쓰신 때, 배터리와 소리가 보입니다.',
};

/// Which `CareReadiness` a section has to agree with.
CareReadiness readinessFor(FamilySees sees) => switch (sees) {
  FamilySees.always => CareReadiness.free,
  FamilySees.withCare => CareReadiness.live,
};
