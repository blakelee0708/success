import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// How far along a 안심 케어 capability actually is.
///
/// Named for readiness rather than stage: `CareStage` is already the
/// subscription flow — notBought, waitingOnSenior, refused, active — and the
/// two would read as the same idea on screens that use both.
enum CareReadiness {
  /// In the PRD's 무료 list and already running. It happens whether or not
  /// anyone subscribes, so it is never something to ask the senior about —
  /// putting it on a consent screen would imply that refusing stops it.
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
  CareCapability(
    key: 'device_status',
    stage: CareReadiness.free,
    title: '기기 상태 확인',
    detail: '부모님이 폰을 쓰실 때마다 배터리와 소리를 확인합니다',
    icon: Icons.battery_charging_full_rounded,
    tint: AppColors.guardianTintBlue,
    tintInk: AppColors.guardianTintBlueInk,
  ),
  CareCapability(
    key: 'battery_low',
    stage: CareReadiness.live,
    title: '배터리 부족 알림',
    detail: '충전 없이 15% 아래로 내려가면 알려드립니다',
    icon: Icons.battery_alert_rounded,
    tint: AppColors.guardianTintAmber,
    tintInk: AppColors.guardianTintAmberInk,
    seniorLine: '배터리가 얼마 안 남았을 때',
  ),
  CareCapability(
    key: 'phone_unused',
    stage: CareReadiness.live,
    title: '폰 미사용 알림',
    detail: '이틀 넘게 폰을 켜지 않으시면 알려드립니다',
    icon: Icons.bedtime_rounded,
    tint: AppColors.guardianTintViolet,
    tintInk: AppColors.guardianTintVioletInk,
    seniorLine: '이틀 넘게 폰을 안 켜셨을 때',
  ),
  CareCapability(
    key: 'location',
    stage: CareReadiness.planned,
    title: '위치 확인',
    detail: '5분 주기로 어디 계신지 확인합니다',
    icon: Icons.place_rounded,
    tint: AppColors.guardianTintGreen,
    tintInk: AppColors.guardianTintGreenInk,
  ),
  CareCapability(
    key: 'status_sync',
    stage: CareReadiness.planned,
    title: '5분 주기 상태 갱신',
    detail: '폰을 쓰지 않으셔도 배터리를 계속 확인합니다',
    icon: Icons.sync_rounded,
    tint: AppColors.guardianTintBlue,
    tintInk: AppColors.guardianTintBlueInk,
  ),
  CareCapability(
    key: 'app_installed',
    stage: CareReadiness.planned,
    title: '앱 설치 알림',
    detail: '새 앱이 깔리면 알려드립니다',
    icon: Icons.download_rounded,
    tint: AppColors.guardianTintViolet,
    tintInk: AppColors.guardianTintVioletInk,
  ),
];

/// Everything already running, free or paid — what 돌봄 lists above its
/// 준비 중 block.
Iterable<CareCapability> get builtCareCapabilities =>
    careCapabilities.where((c) => c.stage != CareReadiness.planned);

/// What the senior is actually being asked about.
Iterable<CareCapability> get consentedCareCapabilities =>
    careCapabilities.where((c) => c.stage == CareReadiness.live);

/// What is sold but not built.
Iterable<CareCapability> get plannedCareCapabilities =>
    careCapabilities.where((c) => c.stage == CareReadiness.planned);
