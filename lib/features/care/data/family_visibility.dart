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

  /// Never, and this is the part worth opening the screen for. The first two
  /// sections on their own are a list of worries; the third is what makes it
  /// a screen that reassures. Each line here is a decision recorded elsewhere
  /// in this repository, not a promise invented for a settings page.
  never,
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

/// What the senior's family can and cannot see, in one list.
///
/// A different question from the consent card's, which is why it is a
/// different list. The card asks **may we turn this on**, so it names only
/// what is paid and built. This answers **what do they see**, so it names the
/// free readings too - and the things nobody sees, which the card has no
/// reason to mention and a senior has every reason to want.
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
    line: '이틀 넘게 폰을 안 켜시면 알려 드립니다',
    capabilityKey: 'phone_unused',
  ),
  FamilyVisibility(
    sees: FamilySees.withCare,
    line: '메시지를 읽으신 때',
    capabilityKey: 'message_read',
  ),

  // --- 보지 못합니다 -------------------------------------------------------
  // 위치 is out of the product entirely - see `## 위치 is out of the product`.
  FamilyVisibility(sees: FamilySees.never, line: '어디 계신지'),
  // The manifest asks for no call permission, and 전화 opens the dialer
  // rather than placing a call.
  FamilyVisibility(sees: FamilySees.never, line: '통화 내용과 통화 기록'),
  // 사람 버튼's numbers are typed by the guardian on their own phone, which
  // is exactly so this stays true.
  FamilyVisibility(sees: FamilySees.never, line: '연락처'),
  // 폰에 있는 앱 sends the one app the senior picked and never the list, and
  // the icon bytes never leave the handset.
  FamilyVisibility(sees: FamilySees.never, line: '어떤 앱을 쓰시는지'),
  // The photo picker returns one chosen file. Nothing reads the album.
  FamilyVisibility(sees: FamilySees.never, line: '사진첩'),
];

Iterable<FamilyVisibility> familySees(FamilySees sees) =>
    familyVisibility.where((v) => v.sees == sees);

/// The heading each section carries, in the senior's words.
String familySeesTitle(FamilySees sees) => switch (sees) {
  FamilySees.always => '늘 보입니다',
  FamilySees.withCare => '안심 케어를 허락하시면',
  FamilySees.never => '보지 못합니다',
};

/// Which `CareReadiness` a section has to agree with, where it has one.
///
/// `FamilySees.never` has none: nothing unseen is a capability.
CareReadiness? readinessFor(FamilySees sees) => switch (sees) {
  FamilySees.always => CareReadiness.free,
  FamilySees.withCare => CareReadiness.live,
  FamilySees.never => null,
};
