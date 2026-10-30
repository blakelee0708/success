import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../guardian/application/home_edit_allowance.dart';

/// How far along a 안심 케어 capability actually is.
///
/// Named for readiness rather than stage: `CareStage` is already the
/// subscription flow — notBought, waitingOnSenior, refused, active — and the
/// two would read as the same idea on screens that use both.
enum CareReadiness {
  /// Running whether or not anyone subscribes, so never something to ask the
  /// senior about - putting it on a consent screen would imply that refusing
  /// stops it.
  ///
  /// **Nothing is in here as of 2026-10-28, and that is the result of the
  /// pricing decision rather than an oversight.** 기기 상태 was free, which
  /// meant three of the things that reassure the *child* cost nothing and
  /// the paid tier was two alerts. The line is now 무료는 부모님 폰을 편하게
  /// 만드는 것, 유료는 부모님이 어떻게 지내시는지 아는 것 - and everything in
  /// this file is the second half by definition, so it empties. What is free
  /// is the launcher, and the launcher is not a care capability.
  free,

  /// Paid and built. The moment a subscription exists and the senior has
  /// agreed, this runs. These, and only these, are what the consent card
  /// describes.
  live,

  /// Paid and not built. Named on the guardian's screen under the 준비 중
  /// block so nobody is sold a promise, and absent from the consent card so
  /// nobody is asked to agree to something that will switch on months later
  /// without being mentioned again.
  planned,
}

/// One thing 안심 케어 does, in both the words it is sold in and the words it
/// is agreed to in.
///
/// One list, read by the guardian's 돌봄 tab and by the senior's consent card,
/// because they had already drifted apart once and the drift is the dangerous
/// kind: the card asked the senior to agree to `5분마다 어디 계신지`, which is
/// not built and will not be until the 위치기반서비스사업 신고 is through, and
/// to `배터리와 소리, 인터넷 상태` — of which 인터넷 is never read and the rest
/// is free and already being sent, so refusing would not have stopped it.
///
/// `06_PERMISSION_AND_POLICY` is the reason this matters more here than
/// anywhere else in the app: 권한은 필요한 순간에 요청한다, and what is
/// described on that screen is what the senior is agreeing to.
class CareCapability {
  const CareCapability({
    required this.key,
    required this.stage,
    required this.title,
    required this.detail,
    required this.icon,
    required this.tint,
    required this.tintInk,
    this.aboutTheSenior = true,
    this.seniorLine,
  });

  final String key;
  final CareReadiness stage;

  /// The guardian's wording, on 돌봄.
  final String title;
  final String detail;

  final IconData icon;
  final Color tint;
  final Color tintInk;

  /// Whether this tells the family something **about the senior**.
  ///
  /// Most paid capabilities do, and those are what the consent card asks
  /// about. Two do not: 가족 메시지 무제한 and 홈 화면 정리 무제한 are
  /// conveniences bought by the guardian that collect nothing and change
  /// nothing a senior would want a say in. Putting them on the consent card
  /// would pad a screen whose whole value is that every line on it matters,
  /// and asking somebody to agree to their family being allowed to write to
  /// them more often is a question with one decent answer.
  final bool aboutTheSenior;

  /// The senior's wording, on the consent card. Required for [CareReadiness.live]
  /// and meaningless for the others — there is a test for both halves of
  /// that.
  ///
  /// Written as *when the guardian is told*, not as *what is collected*: the
  /// collection is the free check-in either way, and a line implying that
  /// refusing stops it would be the screen misdescribing its own 아니요.
  final String? seniorLine;
}

const careCapabilities = <CareCapability>[
  // Free until 2026-10-28, and moving it is most of what sharpened the line.
  // It is the single most reassuring thing the app can tell a child, and it
  // was costing nothing - so the paid tier was two alerts about a phone the
  // guardian could already watch. The first week is still free, which is
  // what lets somebody see it before deciding; `care_trial_ends_at` is the
  // server's half of that.
  CareCapability(
    key: 'device_status',
    stage: CareReadiness.live,
    title: '안부 신호와 폰 상태',
    detail: '폰을 쓰신 때, 배터리와 소리를 알려 드립니다',
    icon: Icons.favorite_rounded,
    tint: AppColors.guardianTintBlue,
    tintInk: AppColors.guardianTintBlueInk,
    seniorLine: '폰을 쓰신 때, 배터리와 소리',
  ),
  CareCapability(
    key: 'battery_low',
    stage: CareReadiness.live,
    title: '배터리 부족 알림',
    detail: '충전 없이 15% 아래로 내려가면 알려드립니다',
    icon: Icons.battery_alert_rounded,
    tint: AppColors.guardianTintAmber,
    tintInk: AppColors.guardianTintAmberInk,
    seniorLine: '배터리가 얼마 안 남았는지',
  ),
  // **폰 미사용 알림 was here and is out of the product**, decided
  // 2026-10-29 after reading Play's stalkerware policy. That rule bans
  // collecting and transmitting personal data to monitor another person,
  // and the only exceptions are 부모 → 자녀 and 기업 → 직원. This app is
  // 자녀 → 부모, which is one adult watching another, and the policy says
  // that is not allowed **even with the watched person's permission**.
  //
  // Everything else 안심 케어 sends is a value Android hands over with no
  // permission at all - a battery percentage, a ringer mode, the moment the
  // phone was last unlocked. `이틀 넘게 안 켜셨는지` is different in kind:
  // it is a pattern of use, watched over days, and it is the one line on
  // the consent card that reads as surveillance rather than as a reading.
  //
  // Taking it out costs the tier one of six things and removes the item a
  // reviewer would stop on. The SQL stays where it is - see
  // `20261021030000_care_alerts.sql` and the note in
  // `20261029050000_drop_unused_alert.sql`.
  CareCapability(
    key: 'message_read',
    stage: CareReadiness.live,
    title: '읽음 확인',
    detail: '보내신 메시지를 부모님이 읽으시면 표시됩니다',
    icon: Icons.done_all_rounded,
    tint: AppColors.guardianTintGreen,
    tintInk: AppColors.guardianTintGreenInk,
    seniorLine: '메시지를 읽으셨는지',
  ),
  // **소리 울리기 was here and is out of the product**, taken out whole on
  // 2026-10-29 along with its sheet, its gate, its listener and the card it
  // drew on the parent's home.
  //
  // It was the one capability with no policy problem at all - it collects
  // nothing and sends nothing about the parent - and the one with no
  // precedent: no published app was found that lets an adult make another
  // adult's phone sound. It was also the one that did not work: a message
  // only reaches the app while it is in the foreground, so it rang a phone
  // that was awake and not one that was asleep, which is the whole case it
  // existed for.
  //
  // Selling the half that worked, to a reviewer who has seen nothing like
  // it, on a tier whose other five things do work, was the trade worth
  // refusing. `request_phone_ring` is revoked from clients in
  // `20261029060000_drop_ring.sql`, so the server refuses it too.
  // **5분 주기 상태 갱신 was here and is gone.** It needed a foreground
  // service, which Android 14 makes a Play Console submission with a
  // description, a user-impact statement and a demo video - and the review
  // standard is work the user started or can perceive, which reading a
  // battery every five minutes is neither. It would also have left a
  // permanent notification on the senior's status bar. Selling it while it
  // could not be built was the thing worth stopping.
  //
  // Two capabilities arrive instead, and both were already enforced on the
  // server while appearing on no screen - so a guardian paying 5,900원 could
  // not see two of the things they were buying.
  CareCapability(
    key: 'message_unlimited',
    stage: CareReadiness.live,
    title: '가족 메시지 무제한',
    detail: '무료는 월 30회, 사진 5장까지입니다',
    icon: Icons.all_inclusive_rounded,
    tint: AppColors.guardianTintViolet,
    tintInk: AppColors.guardianTintVioletInk,
    // Nothing about the senior, so it is not on the consent card.
    aboutTheSenior: false,
  ),
  CareCapability(
    key: 'home_edits',
    stage: CareReadiness.live,
    title: '홈 화면 정리 무제한',
    detail: '무료는 $guardianHomeEditsFree번까지. 부모님 폰에서는 언제나 무제한입니다',
    icon: Icons.grid_view_rounded,
    tint: AppColors.guardianTintGreen,
    tintInk: AppColors.guardianTintGreenInk,
    aboutTheSenior: false,
  ),
];

/// Everything already running, free or paid — what 돌봄 lists above its
/// 준비 중 block.
Iterable<CareCapability> get builtCareCapabilities =>
    careCapabilities.where((c) => c.stage != CareReadiness.planned);

/// What the senior is actually being asked about.
///
/// `live` is not enough on its own: 가족 메시지 무제한 and 홈 화면 정리
/// 무제한 are paid and built and tell the family nothing about the person
/// reading this card.
Iterable<CareCapability> get consentedCareCapabilities => careCapabilities
    .where((c) => c.stage == CareReadiness.live && c.aboutTheSenior);

/// What is sold but not built.
Iterable<CareCapability> get plannedCareCapabilities =>
    careCapabilities.where((c) => c.stage == CareReadiness.planned);
